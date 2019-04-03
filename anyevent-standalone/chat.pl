#! /usr/bin/env perl
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Socket qw(tcp_server);
use AnyEvent::WebSocket::Server;

my %connections;
my $server= AnyEvent::WebSocket::Server->new(
	handshake => sub {
		my ($req, $res)= @_;
		my ($username)= ($req->resource_name =~ /username=([^&]*)/);
		return $res, $username;
	},
);

# Listen on port 5000 for incoming connections
my $next_id= 1;
tcp_server undef, 5000, sub {
	my ($fh)= @_;
	# For each connection, hand off to $server to talk HTTP and upgrade to websocket
	$server->establish($fh)->cb(sub {
		my ($conn, $username)= eval { shift->recv };
		if ($@) {
			warn "Rejected connection: $@\n";
			close($fh);
			return;
		}
		# If username is taken, reject with a message
		if ($connections{$username}) {
			$conn->send("Username is taken");
			$conn->close;
		}
		else {
			$connections{$username}= $conn;
			$conn->on(each_message => sub { my @args= @_; eval { handle_message($username, @args); 1 } || warn $@ });
			$conn->on(finish => sub { delete $connections{$username}; });
		}
	});
};

sub handle_message {
	my ($username, $conn, $msg)= @_;
	# Messages can be several different types.  We only care about text.
	if ($msg->is_text) {
		my $text= $username . ': ' . $msg->decoded_body;
		# re-broadcast message to every connection, prefixed with connection name
		$_->send($text) for values %connections;
	}
}

# Standard AnyEvent boilerplate to keep running the event loop until end of program
my $term= AE::cv;
AE::signal $_ => sub { $term->send } for qw( TERM INT HUP );
$term->recv;

1;
