#! /usr/bin/env perl
use Log::Any '$log';
use Log::Any::Adapter 'Daemontools', -init => { env => 1 };
use Mojolicious::Lite -signatures;
use Mojo::WebSocket 'WS_PING';

our $presenter_key= $ENV{PRESENTER_KEY} or die "Missing env PRESENTER_KEY";

get '/' => sub ($c) {
	$c->reply->static('slides.html');
};
get '/main' => sub ($c) {
	$c->reply->static('slides.html');
};
get '/presenter' => sub ($c) {
	$c->reply->static('slides.html');
};

my $cur_extern= '';
my %viewers;
websocket '/slidelink.io' => sub {
	my $c= shift;
	my $id= $c->req->request_id;
	$viewers{$id}= $c;
	
	my $mode= $c->req->params->param('mode') || '';
	my $key= $c->req->params->param('key') || '';
	if ($mode eq 'presenter' && $key eq $presenter_key) {
		$c->stash(presenter => 1, driver => 1, mode => 'presenter');
	} elsif ($mode eq 'main' && $key eq $presenter_key) {
		$c->stash(driver => 1, mode => 'main');
		my $ip= `ip addr show dev wlp2s0`;
		if ($ip =~ /inet ([0-9.]+)/) {
			$c->send({ json => { slide_host => $1 } });
		} else {
			$log->warn("Can't find public IP in $ip");
		}
	} else {
		$c->stash(mode => 'obs');
	}
	
	$log->infof("%s (%s) connected as %s", $id, $c->tx->remote_address, $c->stash('mode'));
	
	$c->on(json => sub {
		my ($c, $msg)= @_;
		$log->debugf("client %s %s msg=%s", $c->request_id, $c->original_remote_address, $msg) if $log->is_debug;
		$log->info(
			$id.' ('.$c->stash('mode').') : '
			.($msg->{slide_num}//'-').'.'.($msg->{step_num}//'-')
			.' extern='.($msg->{extern}//'-')
		);
		if (defined $msg->{extern} && $c->stash('driver')) {
			#if ($extern_pid) {
			#	kill TERM => $extern_pid;
			#	undef $extern_pid;
			#}
			#$log->info("Launch $msg->{extern}");
			#$cur_extern= $msg->{extern};
			#run_extern($msg->{extern}, $msg->{elem_rect});
		}
		if (defined $msg->{slide_num} && $c->stash('driver')) {
			$_ ne $c && $_->send({ json => { slide_num => $msg->{slide_num}, step_num => $msg->{step_num} }})
				for values %viewers;
		}
		if (defined $msg->{notes} && $c->stash('mode') eq 'main') {
			$log->info("\n$msg->{notes}\n\n");
		}
	});
	$c->on(finish => sub {
		delete $viewers{shift()};
	});
};

my %chatters;
websocket '/chat.io' => sub {
	my $c= shift;
	my $username= $c->req->params->param('username');
	# If username is taken, reject with a message
	if ($chatters{$username}) {
		$c->send("Username is taken");
		$c->disconnect;
	}
	else {
		$c->stash(username => $username);
		$chatters{$username}= $c;
		$c->inactivity_timeout(60);
		$c->on(message => sub {
			my ($c, $msg)= @_;
			my $text= $c->stash('username') . ': ' . $msg;
			# re-broadcast message to every connection, prefixed with connection name
			$_->send($text) for values %chatters;
		});
		$c->on(finish => sub { delete $chatters{$username}; });
	}
};

app->start;
