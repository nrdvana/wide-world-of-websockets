package Chat::Controller::Root;
use Moose;
use namespace::autoclean;
use Protocol::WebSocket::Handshake::Server;
use AnyEvent::WebSocket::Connection;
use AnyEvent::WebSocket::Server;

BEGIN { extends 'Catalyst::Controller' }

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');

=encoding utf-8

=head1 NAME

Chat::Controller::Root - Root Controller for Chat

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=head2 index

The root page (/)

=cut

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;
	$c->res->redirect('/chat.html');
}

=head2 chat.io

This is the action for the websocket.

=cut

has connections => ( is => 'rw', default => sub { +{} } );

sub chat_io :Path('chat.io') :Args(0) {
	my ($self, $c)= @_;
	my $username= $c->req->param('username');
	my $env= $c->req->env;
	if (!$env->{'psgix.io'}) {
		# Must be using a PSGI server that exposes the file handle to us
		_respond_err($c, 500, 'psgix.io not supported by this server');
	}
	elsif (!$env->{'psgi.nonblocking'}) {
		# Can't do anything useful with a websocket unless the webserver is
		# written with an I/O event loop
		_respond_err($c, 500, 'Nonblocking communication not supported by this server');
	}
	elsif (!$c->req->headers->header('Sec-Websocket-Key')) {
		# Early (obsolete) versions of WebSocket required reading additional body bytes,
		# which is awkward to do in a nonblocking manner.  If the client supplied this
		# header, we can skip that mess.  If not, just refuse the connection.
		_respond_err($c, 400, 'Unsupported version of WebSocket');
	}
	else {
		# Tell Catalyst that we're handling the rest of the communications with the client,
		# by accessing the io_fh attribute.
		my $fh= $c->req->io_fh;
		# AnyEvent::WebSocket::Server handles the rest
		AnyEvent::WebSocket::Server->new->establish_psgi($env)->cb(sub {
			my $conn;
			unless (eval { $conn= shift->recv; 1 }) {
				warn "Rejected connection: $@\n";
				close($fh);
				return;
			}
			# If username is taken, reject with a message
			if ($self->connections->{$username}) {
				$conn->send("Username is taken");
				$conn->close;
			}
			else {
				$self->connections->{$username}= $conn;
				$conn->on(each_message => sub { my @args= @_; eval { $self->handle_message($username, @args); 1 } || warn $@ });
				$conn->on(finish => sub { delete $self->connections->{$username} });
			}
		});
		$c->detach();
	}
}

sub _respond_err {
	my ($c, $code, $message)= @_;
	$c->res->code($code);
	$c->res->content_type('text/plain; charset=utf-8');
	$c->res->body($message);
	$c->log->error($message);
}

sub handle_message {
	my ($self, $username, $conn, $msg)= @_;
	# Messages can be several different types.  We only care about text.
	if ($msg->is_text) {
		my $text= $username . ': ' . $msg->decoded_body;
		# re-broadcast message to every connection, prefixed with connection name
		$_->send($text) for values %{$self->connections};
	}
}

=head2 default

Standard 404 error page

=cut

sub default :Path {
    my ( $self, $c ) = @_;
    $c->response->body( 'Page not found' );
    $c->response->status(404);
}

=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
