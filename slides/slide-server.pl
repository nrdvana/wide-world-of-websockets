#! /usr/bin/env perl
use Log::Any '$log';
use Log::Any::Adapter 'Daemontools', -init => { env => 1 };
use Mojolicious::Lite -signatures;
use Mojo::WebSocket 'WS_PING';
use Time::HiRes 'time';
use Socket qw(IPPROTO_TCP TCP_NODELAY TCP_CORK);
use IO::All;

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
my $stattimer;
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
			if ($msg->{extern} eq 'stats') {
				$log->info("Stats active");
				my $prev_t= time;
				my $prev_rx= io('/sys/class/net/wlp2s0/statistics/rx_bytes')->slurp + 0;
				my $prev_tx= io('/sys/class/net/wlp2s0/statistics/tx_bytes')->slurp + 0;
				$stattimer= Mojo::IOLoop->recurring(.1 => sub {
					my $loop= shift;
					my $now= time;
					my $rx= io('/sys/class/net/wlp2s0/statistics/rx_bytes')->slurp + 0;
					my $tx= io('/sys/class/net/wlp2s0/statistics/tx_bytes')->slurp + 0;
					my $dt= $now - $prev_t;
					update_stats(rx_rate => ($rx-$prev_rx)/$dt, tx_rate => ($tx-$prev_tx)/$dt);
					$prev_t= $now;
					$prev_rx= $rx;
					$prev_tx= $tx;
					$log->info("rx $rx tx $tx");
				});
			}
			elsif ($stattimer) {
				$log->info("Stats off");
				Mojo::IOLoop->remove($stattimer);
			}
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
	#use DDP; &p($c->tx->req->env);
	# How do I get to the socket of a mojo transaction?
	#setsockopt($c->tx->handshake->connection, IPPROTO_TCP, TCP_NODELAY, 1) || warn "setsockopt failed: $!";
	#setsockopt($c->tx->handshake->connection, IPPROTO_TCP, TCP_CORK, 0) || warn "setsockopt failed: $!";
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
