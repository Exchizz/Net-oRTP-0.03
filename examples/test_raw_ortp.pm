use strict;
use warnings;
use Data::Dumper;
# load Net::oRTP
use Net::oRTP;

# Create a send/receive object
my $rtp = new Net::oRTP('SENDRECV');
# Set it up
$rtp->set_blocking_mode( 0 );
$rtp->set_remote_addr( '127.0.0.1', 1337 );
$rtp->set_send_payload_type( 0 );

for(my $i = 0; $i <10; $i++){
	$rtp->raw_rtp_send2(12345,"Hello World:>");
}
