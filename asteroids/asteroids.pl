#! /usr/bin/env perl
use utf8;
use Log::Any '$log';
use Log::Any::Adapter 'Daemontools', -init => { env => 1 };
use Mojolicious::Lite -signatures;
use Mojo::WebSocket 'WS_PING';
use Time::HiRes 'time';
use Math::Trig qw( pi );
use Socket qw(IPPROTO_TCP TCP_NODELAY TCP_CORK);
use IO::All;
use JSON;

app->secrets(['sdjflskjdflsejf']);

get '/' => sub($c) { $c->reply->static('asteroids.html'); };

my %players;
my @bullets;
my @asteroids;
my $pending_update= 0;
websocket '/asteroids.io' => sub($c) {
	my $id= $c->req->request_id;
	$players{$id}= { ship => Ship->new(x => 100, y => 100, color => 'white'), c => $c, id => $id, thrust => 0, turn => 0 };
	update_all();
	$c->inactivity_timeout(600);
	$c->on(json => sub($c, $msg) {
		my $t= time;
		$players{$id}{ship}->update($t); # update all ship variables to current time
		if (defined $msg->{shoot}) {
			print encode_json($msg)."\n";
		}
		if (defined $msg->{shoot} && (!!$msg->{shoot} ne !!$players{$id}{shoot})) {
			if (!$players{$id}{shoot}) {
				shoot($players{$id}{ship}, $t);
				$players{$id}{shoot}= Mojo::IOLoop->recurring(.3 => sub { shoot($players{$id}{ship}); });
			} else {
				Mojo::IOLoop->remove(delete $players{$id}{shoot});
			}
		}
		if (defined $msg->{turn} && ($msg->{turn} ne $players{$id}{turn})) {
			$players{$id}{ship}->set_dθ_dt($msg->{turn} * .25);
			$players{$id}{turn}= $msg->{turn};
			update_all();
		}
		if (defined $msg->{thrust} && ($msg->{thrust} ne $players{$id}{thrust})) {
			$players{$id}{ship}->set_a(15 * $msg->{thrust});
			$players{$id}{thrust}= $msg->{thrust};
			update_all();
		}
	});
	$c->on(finish => sub { delete $players{$id} });
};

package Ship {
	use strict;
	use warnings;
	use experimental 'signatures';
	use Math::Trig qw( pi );
	sub new {
		my ($class, %ship)= @_;
		$ship{t}     //= time;
		$ship{x}     //= 0; # x position
		$ship{y}     //= 0; # y position
		$ship{dx_dt} //= 0; # velocity x component
		$ship{dy_dt} //= 0; # velocity y component
		$ship{θ}     //= 0; # heading
		$ship{dθ_dt} //= 0; # rate of turn
		$ship{a}     //= 0; # magnitude of acceleration
		$ship{color} //= 'white';
		$ship{gun_ofs}//= 6;
		$ship{cooldown} //= $ship{t};
		bless \%ship, $class;
	}
	sub update($self, $new_t=time) {
		my $t= $new_t - $self->{t}; # $t is the time offset since last update
		return $self unless $t;
		# convert angles to radians
		my $θ= $self->{θ} * 2 * pi;
		my ($cosθ, $sinθ)= ( cos($θ), sin($θ) );
		my $dθ_dt= $self->{dθ_dt} * 2 * pi;
		# If rotating, ship motion is determined by
		#  x(t) = ∫∫ a * cos(θ + dθ_dt * t) dt
		#  y(t) = ∫∫ a * sin(θ + dθ_dt * t) dt
		if ($dθ_dt) {
			my ($cosθt, $sinθt)= ( cos($θ + $t * $dθ_dt), sin($θ + $t * $dθ_dt) );
			my $a_over_dθdt= $self->{a} / $dθ_dt;
			my $a_over_dθdt2= $a_over_dθdt / $dθ_dt;
			# Calculate integration constants
			my $C1_x= $self->{dx_dt} - $a_over_dθdt * $sinθ;
			my $C1_y= $self->{dy_dt} + $a_over_dθdt * $cosθ;
			my $C0_x= $self->{x} + $a_over_dθdt2 * $cosθ;
			my $C0_y= $self->{y} + $a_over_dθdt2 * $sinθ;
			# New instantaneous position at time T:
			$self->{x}= -$a_over_dθdt2 * $cosθt + $t*$C1_x + $C0_x;
			$self->{y}= -$a_over_dθdt2 * $sinθt + $t*$C1_y + $C0_y;
			# New instantaneous velocity at time T:
			$self->{dx_dt}=  $a_over_dθdt * $sinθt + $C1_x;
			$self->{dy_dt}= -$a_over_dθdt * $cosθt + $C1_y;
		}
		# else (no rotation) ship motion is determined by
		#  x(t) = ∫∫ a dt
		else {
			my $ax= $self->{a} * $cosθ;
			my $ay= $self->{a} * $sinθ;
			# New instantaneous position at time T:
			$self->{x} += $ax/2 * $t*$t + $self->{dx_dt}*$t;
			$self->{y} += $ay/2 * $t*$t + $self->{dy_dt}*$t;
			# New instantaneous velocity at time T:
			$self->{dx_dt} += $ax * $t;
			$self->{dy_dt} += $ay * $t;
		}
		# New angle at time T:
		$self->{θ} += $self->{dθ_dt} * $t;
		$self->{t}= $new_t;
		$self;
	}
	sub set_a($self, $acc) {
		$self->{a}= $acc;
		$self;
	}
	sub set_dθ_dt($self, $θ) {
		$self->{dθ_dt}= $θ;
		$self;
	}
	sub shoot($self, $t=time) {
		return unless $t >= $self->{cooldown};
		$self->update($t);
		$self->{cooldown}= $t + .29;
		my $θ= $self->{θ}*2*pi;
		my ($sinθ, $cosθ)= (sin($θ), cos($θ));
		my $x= $self->{x} + $self->{gun_ofs} * $cosθ;
		my $y= $self->{y} + $self->{gun_ofs} * $sinθ;
		my $velocity= 30;
		my $duration= 5;
		return {
			x => $x, dx_dt => $self->{dx_dt} + $cosθ * $velocity,
			y => $y, dy_dt => $self->{dy_dt} + $sinθ * $velocity,
			t => $t, end_t => $t + $duration,
		};
	}
	sub TO_JSON {
		return +{ shift->%* }
	}
}

sub shoot($ship, $t=time) {
	$t //= time;
	if (my $bullet= $ship->shoot($t)) {
		push @bullets, $bullet;
		update_all();
	}
}

sub update_all {
	unless ($pending_update++) {
		Mojo::IOLoop->next_tick(sub {
			$pending_update= 0;
			my %stats= (
				t => time,
				ships => [ map $_->{ship}->TO_JSON, values %players ],
				bullets => \@bullets,
				asteroids => \@asteroids,
			);
			for (values %players) {
				say "Send update to player $_->{id}";
				$_->{c}->send({ json => \%stats }); 
			}
		});
	}
}

app->start;
