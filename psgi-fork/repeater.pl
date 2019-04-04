#! /usr/bin/env perl
use strict;
use warnings;
use Socket;
use IO::Handle;

# This script accepts connections on a listening socket, and then for every
# line of text received by any socket it re-broadcasts that text to all
# client sockets.

# This could be much more easily written using AnyEvent, but for sake of
# demonstration, I'm avoiding any external dependencies.  This also means it
# probably had bugs on non-posix systems, like Win32, which probably needs all
# sorts of special cases to make a correct program...

my $next_id= 1;
my %clients;

my $listen_path= shift
	or die "Socket path expected as first argument";

# perldoc perlipc
socket(my $listen_fh, AF_UNIX, SOCK_STREAM, 0) or die "socket: $!";
$listen_fh->blocking(0);
bind($listen_fh, sockaddr_un($listen_path)) or die "bind($listen_path): $!";
listen($listen_fh, SOMAXCONN) or die "listen: $!";

warn "Listening on $listen_path\n";

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
	my $ready= select(
		(my $rd= fhbits(@all_fh)),
		(my $wr= fhbits(@pending_wr)),
		(my $err= fhbits(@all_fh)),
		undef # no timeout
	);
	die "select: $!" unless $ready >= 0 or is_temporary_error;
	
	# Iterate all file handles and see if each was listed as ready to read or errored
	my $to_send= '';
	for (values %clients) {
		# If client socket marked as errored, close and clean up client connection
		if (vec($err, fileno($_->{fh}), 1)) {
			close_client($_);
		}
		# Else if readable, check if we have a whole line.
		elsif (vec($rd, fileno($_->{fh}), 1)) {
			my $got= sysread($_->{fh}, $_->{rbuf}, 0x7FFFFFFF, length($_->{rbuf}));
			if ($got) {
				# Extract as many lines of text as found in te buffer, but leave the final
				# one if it is not terminated with \n yet.
				if ((my $end= rindex($_->{rbuf},"\n")) >= 0) {
					$to_send .= substr($_->{rbuf}, 0, $end+1);
					substr($_->{rbuf}, 0, $end+1)= '';
				}
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
	if (length $to_send || @pending_wr) {
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
	warn "Closing client $client->{id}\n";
	close($client->{fh});
	delete $clients{$client->{id}};
}
