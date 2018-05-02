use strict;
use warnings;

use Data::Dumper;

use Net::oRTP;
use IO::Async::Timer::Periodic;
use IO::Async::Loop;


# Unbuffered
$|=1;

# Create a send/receive object
my $rtp = new Net::oRTP('SENDRECV');
# Set it up
$rtp->set_blocking_mode( 0 );
$rtp->set_remote_addr( '127.0.0.1', 1337 );
$rtp->set_send_payload_type( 0 );

my $ts = 1234;
my $loop = IO::Async::Loop->new;
my $timer = IO::Async::Timer::Periodic->new(
	interval => 1,
	on_tick => sub {
		print "Sends RTP & RTCP bye\n";
		$rtp->raw_rtp_send($ts,"Hello World:>");
		$rtp->raw_rtcp_bye_send("I'm out:>");
		$ts+=1;
	},
);

$timer->start;
$loop->add( $timer );
$loop->run;
