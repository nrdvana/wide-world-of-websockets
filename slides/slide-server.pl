#! /usr/bin/env perl
use Log::Any '$log';
use Log::Any::Adapter 'Daemontools', -init => { env => 1 };
use Mojolicious::Lite;
my %connections;
my $cur_extern= '';

get '/' => sub {
	shift->redirect_to('slides.html')
};

websocket '/link.io' => sub {
	my $c= shift;
	$connections{$c}= $c;
	$c->inactivity_timeout(3600);
	$c->on(json => sub {
		my @args= @_;
		eval { handle_message(@args); 1 } || warn $@;
	});
	$c->on(finish => sub {
		delete $connections{shift()};
	});
};

sub handle_message {
	my ($conn, $msg)= @_;
	$log->debugf("msg=%s", $msg) if $log->is_debug;
	$log->info(
		$conn.' : '
		.($msg->{slide_num}//'-').'.'.($msg->{step_num}//'-')
		.' extern='.($msg->{extern}//'-')
	);
	if ($msg->{extern} && $cur_extern ne $msg->{extern}) {
		#if ($extern_pid) {
		#	kill TERM => $extern_pid;
		#	undef $extern_pid;
		#}
		#$log->info("Launch $msg->{extern}");
		#$cur_extern= $msg->{extern};
		#run_extern($msg->{extern}, $msg->{elem_rect});
	}
	if ($msg->{slide_num} || $msg->{step_num}) {
		$_ ne $conn && $_->send({ json => { slide_num => $msg->{slide_num}, step_num => $msg->{step_num} }})
			for values %connections;
	}
	if ($msg->{notes}) {
		$log->info("\n$msg->{notes}\n\n");
	}
};

app->start;
