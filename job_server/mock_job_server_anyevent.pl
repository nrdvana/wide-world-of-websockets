#! /usr/bin/env perl

=head1 DESCRIPTION

This is a demonstration of a simple "Job Server" which receives connections from a trusted
source (such as the back-end of public-facing HTTP controllers) and executes long-running
tasks on their behalf.  It sends notifications to each connected client when their job's
position in the queue changes, and progress of the job as it executes.

The simplest way to write this would be lines of JSON over AnyEvent::Handle, but I'm using
WebSockets here just to have an example of using them on the back-end.

=cut

use strict;
use warnings;
use JSON;
use AnyEvent;
use AnyEvent::Socket qw(tcp_server);
use AnyEvent::WebSocket::Server;

my $job_in_progress;
my %jobs;
my %clients;
my $wss= AnyEvent::WebSocket::Server->new();

my $j= JSON->new; # methods below are using unicode strings, but encode_json generates UTF-8 bytes
sub to_json { $j->encode(shift) }
sub from_json { $j->decode(shift) }

# Listen on port 3456 for incoming connections
my $next_id= 1;
tcp_server undef, 3456, sub {
	my ($fh)= @_;
	# For each connection, hand off to $wss to talk HTTP and upgrade to websocket
	$wss->establish($fh)->cb(sub {
		if (my ($conn)= eval { shift->recv }) {
			$clients{$conn}= $conn;
			$conn->on(each_message => \&handle_client_message);
			$conn->on(finish => sub {
				my ($conn)= @_;
				delete $clients{$conn};
				delete $_->{watchers}{$conn} for values %jobs;
			});
		} else {
			warn "Rejected connection: $@\n";
			close($fh);
		}
	});
};

sub handle_client_message {
	my ($conn, $msg)= @_;
	# Messages can be several different types.  We only care about text, and assume them to contain JSON
	if ($msg->is_text) {
		my $msg= from_json($msg->decoded_body);
		if ($msg->{queue_job}) {
			my $job_id= $next_id++;
			$jobs{$job_id}= { name => $msg->{queue_job}, watchers => { $conn => $conn } };
			$conn->send(to_json({ job_id => $job_id, queue_pos => -1+scalar keys %jobs }));
			run_next_job();
		}
		elsif ($msg->{watch_job}) {
			my $job= $jobs{$msg->{watch_job}};
			if ($job) {
				$job->{watchers}{$conn}= $conn;
			}
			else {
				$conn->send(to_json({ error => 'No such job '.$msg->{watch_job} }));
			}
		}
	}
}

# Send a notification to every job watcher about their job's new position in the queue
sub notify_queue_pos {
	my @queue= sort { $a <=> $b } keys %jobs;
	for my $pos (0 .. $#queue) {
		$_->send(to_json({ job_id => $queue[$pos], queue_pos => $_ }))
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
	$_->send(to_json({ job_id => $job_id, running => \1, progress => 0 }))
		for values %{ $jobs{$job_id}{watchers} // {} };
	# Every 1 second, pretend that the job gave is a progress update.  After $steps progress updates,
	# pretend that the job completes, and then notify the listers and advance to next job in queue.
	$job_in_progress= AE::timer 1, 1, sub {
		my $finished= ++$i >= $steps;
		$_->send(to_json({ job_id => $job_id, running => \1, finished => $finished? \1:\0, progress => ($i/$steps) }))
			for values %{ $jobs{$job_id}{watchers} // {} };
		if ($finished) {
			delete $jobs{$job_id};
			undef $job_in_progress;
			notify_queue_pos();
			run_next_job();
		}
	};
}

# Standard AnyEvent boilerplate to keep running the event loop until end of program
my $term= AE::cv;
AE::signal $_ => sub { $term->send } for qw( TERM INT HUP );
$term->recv;
