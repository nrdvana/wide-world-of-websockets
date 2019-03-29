#! /usr/bin/env perl
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Socket qw(tcp_server);
use AnyEvent::WebSocket::Server;

my %connections;
my $server= AnyEvent::WebSocket::Server->new();

# Listen on port 5000 for incoming connections
tcp_server undef, 5000, sub {
	my ($fh)= @_;
	# For each connection, hand off to $server to talk HTTP and upgrade to websocket
	$server->establish($fh)->cb(sub {
		my ($conn)= eval { shift->recv };
		if ($@) {
			warn "Rejected connection: $@\n";
			close($fh);
			return;
		}
		# Ignore the HTTP details of the request, and accept the client as a new chat user
		$connections{$conn}= $conn;
		$conn->on(each_message => sub { my @args= @_; eval { handle_message(@args); 1 } || warn $@ });
		$conn->on(finish => sub { delete $connections{$conn}; undef $conn });
	});
};

sub handle_message {
	my ($conn, $msg)= @_;
	# Messages can be several different types.  We only care about text.
	if ($msg->is_text) {
		my $text= $msg->decoded_body;
		# re-broadcast message to every other connection
		$_->send($text) for grep { $_ ne $conn } values %connections;
	}
}

# Standard AnyEvent boilerplate to keep running the event loop until end of program
my $term= AE::cv;
AE::signal $_ => sub { $term->send } for qw( TERM INT HUP );
$term->recv;

1;
