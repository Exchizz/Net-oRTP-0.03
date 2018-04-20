use strict;
use warnings;

use Data::Dumper;

use Net::oRTP;
use IO::Async::Timer::Periodic;
use IO::Async::Loop;

# Create a send/receive object
my $rtp_session1 = new Net::oRTP('SENDRECV');
my $rtp_session2 = new Net::oRTP('SENDRECV');


# Set it up
$rtp_session1->set_blocking_mode( 0 );
$rtp_session1->set_remote_addr( '127.0.0.1', 1337 );
$rtp_session1->set_send_payload_type( 96 );

$rtp_session2->set_blocking_mode( 0 );
$rtp_session2->set_remote_addr( '127.0.0.1', 1020 );
$rtp_session2->set_send_payload_type( 96 );

my $loop = IO::Async::Loop->new;
my $timer = IO::Async::Timer::Periodic->new(
	interval => 2,
	on_tick => sub {
		print "Sends RTP & RTCP bye\n";
		$rtp_session1->raw_rtp_send(12345,"Hello World:>");
		$rtp_session1->raw_rtcp_bye_send("I'm out:>");

		$rtp_session2->raw_rtp_send(010101,"Hello World 2");
		$rtp_session2->raw_rtcp_bye_send("I'm out2:>");
	},
);

$timer->start;
$loop->add( $timer );
$loop->run;
