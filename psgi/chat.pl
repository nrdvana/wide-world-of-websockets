#! /usr/bin/env perl
use strict;
use warnings;
use URI::Escape;

# This example is about PSGI, but in order to talk to the socket in an
# event-driven manner we need to use the same event loop as the PSGI Server,
# and there's no way to know that ahead of time.  AnyEvent works with...
# "any" event loop.  mostly.
use AnyEvent::WebSocket::Server;
# For examples of using various event loops directly, see the examples/
# directory in the distribution for Protocol::WebSocket

my %connections;
my $wss= AnyEvent::WebSocket::Server->new;

sub handle_message {
	my ($username, $conn, $msg)= @_;
	# Messages can be several different types.  We only care about text.
	if ($msg->is_text) {
		my $text= $username . ': ' . $msg->decoded_body;
		# re-broadcast message to every connection, prefixed with connection name
		$_->send($text) for values %connections;
	}
}

my $app= sub {
	my $env= shift;
	
	# This PSGI app serves chat.html and chat.io
	if ($env->{PATH_INFO} eq '' || $env->{PATH_INFO} eq '/') {
		return [ 302, [Location => ($env->{SCRIPT_NAME}||'').'/chat.html'], [] ];
	}
	elsif ($env->{PATH_INFO} eq '/chat.html') {
		open(my $fh, '<', '../static/chat.html') or return [ 500, [], ["Can't open ../static/chat.html"] ];
		return [ 200, ['Content-Type'=>'text/html;charset=UTF-8'], $fh ];
	}
	elsif ($env->{PATH_INFO} eq '/jquery-3.5.0.min.js') {
		open(my $fh, '<', '../static/jquery-3.5.0.min.js') or return [ 500, [], ["Can't open ../static/jquery-3.5.0.min.js"] ];
		return [ 200, ['Content-Type'=>'application/javascript;charset=UTF-8'], $fh ];
	}
	elsif ($env->{PATH_INFO} eq '/chat.io') {
		# Environment must supply the TCP socket being used to talk to the client, else
		# we can't begin the websocket handshake.
		(my $fh= $env->{'psgix.io'}) and $env->{'psgi.nonblocking'}
			or return [ 500, ['Content-type'=>'text/plain'], ['Webserver does not support nonblocking websockets'] ];
		# Expecting a query param of 'username'
		my ($username)= ($env->{QUERY_STRING} =~ /(?:^|&)username=([^&]+)/);
		defined $username
			or return [ 422, [], ['username required'] ];
		$username= uri_unescape($username);
		# Return a PSGI callback, letting the server know that we are going
		# to deliver an asynchronous response.  Server will call the callback
		# giving us a "responder".
		return sub {
			my $responder= shift;
			# But then never use the responder, because we don't want the server talking
			# on the socket anymore.  We handle all communications from here on via the
			# $conn object.
			# But, make sure the responder doesn't get garbage collected until we are
			# done talking, by referencing it in a callback.
			# Websocket needs to begin a protocol handshake, involving both reads
			# and writes on the socket, so it needs to be handled in event callbacks.
			$wss->establish_psgi($env)->cb(sub {
				my ($conn)= eval { shift->recv };
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
					$conn->on(finish => sub { delete $connections{$username}; undef $responder });
				}
			});
		};
	}
	else {
		return [ 404, [], [] ];
	}
};
