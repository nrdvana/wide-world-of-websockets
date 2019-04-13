#! /usr/bin/env perl
use strict;
use warnings;
use Socket;
use JSON;
use Try::Tiny;
use IO::Handle;
use Time::HiRes 'time';
use Protocol::WebSocket;

=head1 DESCRIPTION

This is a demonstration of a simple "Job Server" which receives connections from a trusted
source (such as the back-end of public-facing HTTP controllers) and executes long-running
tasks on their behalf.  It sends notifications to each connected client when their job's
position in the queue changes, and progress of the job as it executes.

This example shows how it could be written using no event-framework at all, with just Perl's
basic 'select' call.

=cut

my $job_in_progress;
my %jobs;
my %clients;
my $next_id;
my @time_events; # arrayref of [ $wake_time, $callback ], sorted with next event first

# Listen on port 3456 for incoming connections
my $listen_port= shift // 3456;

# perldoc perlipc
socket(my $listen_fh, AF_INET, SOCK_STREAM, 0)
	or die "socket: $!";
bind($listen_fh, pack_sockaddr_in($listen_port, inet_aton("localhost")))
	or die "bind(localhost:$listen_port): $!";
listen($listen_fh, SOMAXCONN)
	or die "listen: $!";
$listen_fh->blocking(0);

warn "Listening on localhost:$listen_port\n";

# perldoc -f select
sub fhbits {
	my $bits= '';
	vec($bits, fileno($_), 1)= 1 for @_;
	return $bits;
}
sub is_temporary_error {
	$!{EAGAIN} || $!{EWOULDBLOCK} || $!{EINTR}
}

my $term= 0;
$SIG{TERM}= sub { $term= 1; };
$SIG{INT}= sub { $term= 1; };

while (!$term) {
	# Make a list of all file handles (listening socket, and each client socket)
	my @all_fh= ($listen_fh, map $_->{fh}, values %clients);
	my @pending_wr= map $_->{fh}, grep length $_->{wbuf}, values %clients;
	# call select() to wait for any socket to be readable or in an error condition
	# or any which is writable and had a leftover wbuf.
	my $now= time;
	my $wake_delay= !@time_events? undef : $now > $time_events[0][0]? 0 : $time_events[0][0] - $now;
	my $ready= select(
		(my $rd= fhbits(@all_fh)),
		(my $wr= fhbits(@pending_wr)),
		(my $err= fhbits(@all_fh)),
		$wake_delay
	);
	die "select: $!" unless $ready >= 0 or is_temporary_error;
	$now= time;
	while (@time_events && $now >= $time_events[0][0]) {
		my $event= shift @time_events;
		try {
			$event->[1]->($event);
		}
		catch {
			warn "Exception in event: $_";
		};
	}
	
	# Iterate all file handles and see if each was listed as ready to read or errored
	my $to_send= '';
	for (values %clients) {
		# If client socket marked as errored, close and clean up client connection
		if (vec($err, fileno($_->{fh}), 1)) {
			close_client($_);
		}
		# Else if readable, check if we have a whole websocket frame
		elsif (vec($rd, fileno($_->{fh}), 1)) {
			my $got= sysread($_->{fh}, $_->{rbuf}, 0x7FFFFFFF, length($_->{rbuf}));
			if ($got) {
				parse_client_rbuf($_); # client can get deleted here
			}
			elsif (defined $got || !is_temporary_error) {
				warn "Read error on client $_->{id}: $!" unless defined $got;
				close_client($_);
			}
		}
	}
	# And also check listening socket for new connections
	if (vec($rd, fileno($listen_fh), 1)) {
		if (defined accept(my $client_fh, $listen_fh)) {
			$client_fh->blocking(0);
			my $id= $next_id++;
			warn "New client $id\n";
			$clients{$id}= { id => $id, rbuf => '', wbuf => '', fh => $client_fh };
		}
	}
	if (@pending_wr) {
		for (values %clients) {
			$_->{wbuf} .= $to_send;
			my $wrote= syswrite($_->{fh}, $_->{wbuf});
			if ($wrote) {
				substr($_->{wbuf}, 0, $wrote)= '';
			}
			elsif (defined $wrote || !is_temporary_error) {
				warn "Write error on client $_->{id}: $!" unless defined $wrote;
				close_client($_);
			}
		}
	}
}

sub close_client {
	my $client= shift;
	my $id= $client->{id};
	warn "Closing client $id\n";
	close($client->{fh});
	delete $_->{watchers}{$id} for values %jobs;
	delete $clients{$id};
}

sub parse_client_rbuf {
	my $client= shift;
	# If client is still in handshake, finish that first
	my $hs= ($client->{handshake} ||= Protocol::WebSocket::Handshake::Server->new);
	unless ($hs->is_done) {
		if (!$hs->parse($client->{rbuf})) { # removes bytes from 'rbuf'
			warn "Error in handshake from client $client->{id}: ".$hs->error;
			close_client($client);
		}
		if ($hs->is_done) {
			client_push_write($hs->res);
		}
		return;
	}
	# See how many WebSocket messages we can extract from the framing object
	my $frame= $client->{frame} ||= $hs->build_frame;
	$frame->append($client->{rbuf});
	while (defined (my $body= $frame->next_bytes)) {
		try {
			if ($frame->is_ping) {
				# Send pong
				client_push_write($client->{handshake}->build_frame(opcode => 'pong')->to_bytes);
			}
			elsif ($frame->is_close) {
				# immediately reply with a close
				client_push_write($client->{handshake}->build_frame(opcode => 'close')->to_bytes);
			}
			elsif ($frame->is_text) {
				# body is bytes in UTF-8, and decode_json implies UTF-8 decoding
				handle_client_message($client, decode_json($body));
			}
			elsif ($frame->is_binary) {
				warn "Ignoring binary message from client $client->{id}\n";
			}
			else {
				warn "Ignoring message of opcode ".$frame->opcode." from client $client->{id}\n";
			}
		} catch {
			warn "error handling mesage for client $client->{id}: $_";
		};
	}
}

sub client_push_write {
	my ($client, $bytes)= @_;
	return unless length $bytes;
	# If no pending write, then can probably make syscall without EWOULDBLOCK
	if (!length $client->{wbuf}) {
		my $wrote= syswrite($client->{fh}, $bytes);
		return if length($bytes) == ($wrote||0);
		if ($wrote) {
			substr($bytes, 0, $wrote)= '';
		}
		elsif (defined $wrote || !is_temporary_error) {
			warn "Write error on client $_->{id}: $!" unless defined $wrote;
			close_client($_);
		}
	}
	$client->{wbuf} .= $bytes;
}

sub client_push_json_message {
	my ($client, $data)= @_;
	my $msg= $client->{handshake}->build_frame(opcode => 'text', buffer => encode_json($data));
	client_push_write($msg->to_bytes);
}

# API implied here is that $msg was JSON decoded to an arrayref or hashref
sub handle_client_message {
	my ($client, $msg)= @_;
	# Messages can be several different types.  We only care about text, and assume them to contain JSON
	if ($msg->{queue_job}) {
		my $job_id= $next_id++;
		$jobs{$job_id}= { name => $msg->{queue_job}, watchers => { $client->{id} => $client } };
		client_push_json_message($client, { job_id => $job_id, queue_pos => -1+scalar keys %jobs });
		run_next_job();
	}
	elsif ($msg->{watch_job}) {
		my $job= $jobs{$msg->{watch_job}};
		if ($job) {
			$job->{watchers}{$client->{id}}= $client;
		}
		else {
			client_push_json_message($client, { error => 'No such job '.$msg->{watch_job} });
		}
	}
}

# Send a notification to every job watcher about their job's new position in the queue
sub notify_queue_pos {
	my @queue= sort { $a <=> $b } keys %jobs;
	for my $pos (0 .. $#queue) {
		client_push_json_message($_, { job_id => $queue[$pos], queue_pos => $_ })
			for values %{ $jobs{$queue[$pos]}{watchers} // {} };
	}
}

sub run_next_job {
	return if $job_in_progress or !keys %jobs;
	my ($job_id)= (sort { $a <=> $b } keys %jobs);
	# Pretend that a job gives us feedback on it's progress.
	# Pretend that jobs take 10-20 seconds to execute
	my $steps= 10+int(rand 10);
	my $i= 0;
	# Send notification that the job is starting
	client_push_json_message($_, { job_id => $job_id, running => \1, progress => 0 })
		for values %{ $jobs{$job_id}{watchers} // {} };
	# Every 1 second, pretend that the job gave is a progress update.  After $steps progress updates,
	# pretend that the job completes, and then notify the listers and advance to next job in queue.
	$job_in_progress= sub {
		my $event= shift;
		my $finished= ++$i >= $steps;
		client_push_json_message($_, { job_id => $job_id, running => \1, finished => $finished? \1:\0, progress => ($i/$steps) })
			for values %{ $jobs{$job_id}{watchers} // {} };
		if ($finished) {
			delete $jobs{$job_id};
			undef $job_in_progress;
			notify_queue_pos();
			run_next_job();
		}
		else {
			$event->[0]++;
			push @time_events, $event;
		}
	};
	push @time_events, [ time+1, $job_in_progress ];
}
