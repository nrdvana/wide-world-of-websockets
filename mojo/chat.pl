#! /usr/bin/env perl
use Mojolicious::Lite;
my %connections;

get '/' => sub { shift->redirect_to('chat.html') };

websocket '/chat.io' => sub {
	my $c= shift;
	my $username= $c->req->params->param('username');
	# If username is taken, reject with a message
	if ($connections{$username}) {
		$c->send("Username is taken");
		$c->disconnect;
	}
	else {
		$connections{$username}= $c;
		$c->on(message => sub { my @args= @_; eval { handle_message($username, @args); 1 } || warn $@ });
		$c->on(finish => sub { delete $connections{$username}; });
	}
};

sub handle_message {
	my ($username, $conn, $msg)= @_;
	# Messages can be several different types.  We only care about text.
	my $text= $username . ': ' . $msg;
	# re-broadcast message to every connection, prefixed with connection name
	$_->send($text) for values %connections;
};

app->start;

1;
