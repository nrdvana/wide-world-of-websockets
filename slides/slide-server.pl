#! /usr/bin/env perl
use Log::Any '$log';
use Log::Any::Adapter 'Daemontools', -init => { env => 1 };
use Mojolicious::Lite -signatures;
use Mojo::WebSocket 'WS_PING';

our $presenter_key= $ENV{PRESENTER_KEY} or die "Missing env PRESENTER_KEY";
@ARGV= qw( daemon --listen=http://*:3210 ) unless @ARGV;
my $ip= get_public_ip();
say "sudo iptables -t nat -A PREROUTING -d $ip -p tcp -m tcp --dport 80 -j DNAT --to-destination $ip:3210";

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
	update_stats(viewer_count => scalar keys %viewers);
	
	my $mode= $c->req->params->param('mode') || '';
	my $key= $c->req->params->param('key') || '';
	if ($mode eq 'presenter' && $key eq $presenter_key) {
		$c->stash(presenter => 1, driver => 1, mode => 'presenter');
	} elsif ($mode eq 'main' && $key eq $presenter_key) {
		$c->stash(driver => 1, mode => 'main');
		if (my $ip= get_public_ip()) {
			$c->send({ json => { slide_host => "http://$ip" } });
		}
	} else {
		$c->stash(mode => 'obs');
	}
	
	$log->infof("%s (%s) connected as %s", $id, $c->tx->remote_address, $c->stash('mode'));
	
	$c->on(json => sub {
		my ($c, $msg)= @_;
		$log->debugf("client %s %s msg=%s", $id, $c->tx->original_remote_address, $msg) if $log->is_debug;
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
	$c->inactivity_timeout(3600);
	#my $keepalive= Mojo::IOLoop->recurring(60 => sub { $viewers{$id}->send([1, 0, 0, 0, WS_PING, '']); });
	#$c->stash(keepalive => $keepalive);
	$c->on(finish => sub {
		#Mojo::IOLoop->remove($keepalive);
		delete $viewers{$id};
		update_stats(viewer_count => scalar keys %viewers);
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
		$c->inactivity_timeout(300);
		$c->on(message => sub {
			my ($c, $msg)= @_;
			my $text= $c->stash('username') . ': ' . $msg;
			# re-broadcast message to every connection, prefixed with connection name
			$_->send($text) for values %chatters;
		});
		$c->on(finish => sub { delete $chatters{$username}; });
	}
};

my %stats;
my %stats_monitors;
websocket '/stats.io' => sub {
	my $c= shift;
	$stats_monitors{$c}= $c;
	$c->on(finish => sub { delete $stats_monitors{$c} });
};
sub update_stats {
	%stats= ( %stats, @_ );
	$_->send({ json => \%stats }) for values %stats_monitors;
}

sub get_public_ip {
	my $ip= `ip addr show dev wlp2s0`;
	$ip =~ /inet ([0-9.]+)/ and return $1;
	$log->warn("Can't find public IP in $ip");
	return undef;
}

app->start;
