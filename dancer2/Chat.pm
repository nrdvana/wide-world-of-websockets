package Chat;
use Dancer2;
use Dancer2::Plugin::WebSocket;
my %connections= ( taken => 1 );

get '/' => sub { redirect 'chat.html'; };

websocket_on_open sub {
	my ($conn, $env)= @_;
	print "websocket_on_open env=".JSON->new->encode($env)."\n";
	print "query_parameters=".JSON->new->encode([query_parameters->flatten])."\n";
	my $username= query_parameters->get('username');
	# If username is taken, reject with a message
	if ($connections{$username}) {
		$conn->send("Username is taken");
		$conn->disconnect;
	}
	else {
		$connections{$username}= $conn;
		print STDERR "Setting message handler and finish handler\n";
		$conn->on(message => sub { my @args= @_; eval { handle_message($username, @args); 1 } || warn $@ });
		$conn->on(finish => sub { delete $connections{$username}; });
	}
};

sub handle_message {
	my ($username, $conn, $msg)= @_;
	# Messages can be several different types.  We only care about text.
	my $text= $username . ': ' . $msg;
	# re-broadcast message to every connection, prefixed with connection name
	$_->send($text) for values %connections;
};

1;
