/*

	Net::oRTP: Real-time Transport Protocol (rfc3550)

	Nicholas Humfrey
	University of Southampton
	njh@ecs.soton.ac.uk
	
*/

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"


#include <stdio.h>
#include <sys/types.h>
#include <ortp/ortp.h>



#ifndef rtp_get_markbit
#define rtp_get_markbit(mp)			((rtp_header_t*)((mp)->b_rptr))->markbit
#endif

#ifndef rtp_get_seqnumber
#define rtp_get_seqnumber(mp)		((rtp_header_t*)((mp)->b_rptr))->seq_number
#endif

#ifndef rtp_get_timestamp
#define rtp_get_timestamp(mp)		((rtp_header_t*)((mp)->b_rptr))->timestamp
#endif

#ifndef rtp_get_ssrc
#define rtp_get_ssrc(mp)			((rtp_header_t*)((mp)->b_rptr))->ssrc
#endif

#ifndef rtp_get_payload_type
#define rtp_get_payload_type(mp)	((rtp_header_t*)((mp)->b_rptr))->paytype
#endif

// Declare internel API functions for RTP
int rtp_session_rtp_send (RtpSession * session, mblk_t * m);

// Declare internal API functions for RTCP
mblk_t *rtcp_create_simple_bye_packet(uint32_t ssrc, const char *reason);
int rtp_session_rtcp_send (RtpSession * session, mblk_t * m);

static void sender_info_init(sender_info_t *info, RtpSession *session, uint64_t ntp){
//	struct timeval tv;
// 	uint64_t ntp;
//	gettimeofday(&tv,NULL);
//	ntp=ortp_timeval_to_ntp(&tv);
	printf("msw: %llu lsw: %llu, input: %llu\n", (ntp >> 32), (ntp & 0xFFFFFFFF), ntp);
	info->ntp_timestamp_msw=htonl(ntp >>32);
	info->ntp_timestamp_lsw=htonl(ntp & 0xFFFFFFFF);
	info->rtp_timestamp=htonl(session->rtp.snd_last_ts);
	info->senders_packet_count=(uint32_t) htonl((u_long) session->rtp.stats.packet_sent);
	info->senders_octet_count=(uint32_t) htonl((u_long) session->rtp.sent_payload_bytes);
	session->rtp.last_rtcp_packet_count=session->rtp.stats.packet_sent;
}

// Helper functions
int get_rtcp_fd(RtpSession * session){
	return session->rtcp.socket;
}
int get_rtp_fd(RtpSession * session){
	return session->rtp.socket;
}
MODULE = Net::oRTP	PACKAGE = Net::oRTP


## Library initialisation
void
ortp_initialize()
  CODE:
	ortp_set_log_level_mask( ORTP_WARNING|ORTP_ERROR|ORTP_FATAL );
	ortp_init();
	ortp_scheduler_init();

void
ortp_shutdown()
  CODE:
	ortp_exit();

void
rtp_session_set_multicast_loopback(session,yesno)
	RtpSession*	session
	int		yesno

void
rtp_session_set_multicast_ttl(session,ttl)
	RtpSession*	session
	int		ttl	

void
rtp_session_set_reuseaddr(session,yesno)
	RtpSession*	session
	int		yesno

## Get socket fd
int
_get_rtp_fd(session)
	RtpSession* session
CODE:
	RETVAL = get_rtp_fd(session);
OUTPUT:
	RETVAL

## Get socket fd
int
_get_rtcp_fd(session)
	RtpSession* session
CODE:
	RETVAL = get_rtcp_fd(session);
OUTPUT:
	RETVAL



## Set SDES items
bool
_set_sdes_items(session,cname)
	RtpSession* session
	char*cname
CODE:
	rtp_session_set_source_description(session, cname, "", "", "", "loc", "MCLURS", "note");
OUTPUT:
	0

## Send RAW RTCP SDES packet
int
_raw_rtcp_sdes_send(session)
	RtpSession* session
CODE:
	mblk_t *cm;
	mblk_t *sdes;
	
	/* Make a BYE packet (will be on the end of the compund packet). */
	sdes = rtp_session_create_rtcp_sdes_packet(session);
	cm=sdes;

	/* Send compound packet. */
	RETVAL = rtp_session_rtcp_send(session, cm);
OUTPUT:
	RETVAL

## Send RAW RTCP SR packet
int
_raw_rtcp_sr_send(session, abs_timestamp)
	RtpSession* session
	IV abs_timestamp
CODE:

	mblk_t *cm = allocb(sizeof(rtcp_sr_t), 0);
	size_t size = sizeof(rtcp_sr_t);
	rtcp_sr_t *sr=(rtcp_sr_t*)cm->b_wptr;
	##int rr=(session->stats.packet_recv>0);
	
	size_t sr_size=sizeof(rtcp_sr_t)-sizeof(report_block_t);
	if (size<sr_size) return 0;
	
	rtcp_common_header_init(&sr->ch,session,RTCP_SR,0,sr_size);
	sr->ssrc=htonl(session->snd.ssrc);
printf("Timestamp c: %llu\n", abs_timestamp);
	sender_info_init(&sr->si,session, abs_timestamp);
	
	cm->b_wptr += sr_size;
	/* Send compound packet. */
	RETVAL = rtp_session_rtcp_send(session, cm);
OUTPUT:
	RETVAL




## Send RAW RTCP Bye packet
int
_raw_rtcp_bye_send(session, reason)
	RtpSession* session
	char *reason
CODE:
	mblk_t *cm;
	mblk_t *sdes = NULL;
	mblk_t *bye = NULL;
	
	/* Make a BYE packet (will be on the end of the compund packet). */
	bye = rtcp_create_simple_bye_packet(session->snd.ssrc, reason);
	cm=bye;

	/* Send compound packet. */
	RETVAL = rtp_session_rtcp_send(session, cm);
OUTPUT:
	RETVAL

## Send RAW RTP packet
int
_raw_rtp_send(session, packet_ts, buffer, payload_len, marker)
	RtpSession* session
	int packet_ts
	char *buffer
	int payload_len
	int marker
CODE:
	mblk_t *m;
	m = rtp_session_create_packet(session,RTP_FIXED_HEADER_SIZE,(uint8_t*)buffer,payload_len);

	rtp_header_t *rtp;
	rtp=(rtp_header_t*)m->b_rptr;
	rtp->timestamp=packet_ts;
	rtp->markbit = marker;
	session->rtp.snd_seq=rtp->seq_number+1;
	RETVAL = rtp_session_rtp_send (session, m);
OUTPUT:
	RETVAL

## Session Stuff
RtpSession*
rtp_session_new(mode)
	int mode
  CODE:
  	RETVAL=rtp_session_new(mode);
  	rtp_session_signal_connect(RETVAL,"ssrc_changed",(RtpCallback)rtp_session_reset,0);
  OUTPUT:
	RETVAL
	
	
void
rtp_session_set_scheduling_mode(session,yesno)
	RtpSession*	session
	int			yesno
	
void
rtp_session_set_blocking_mode(session,yesno)
	RtpSession*	session
	int			yesno

int
rtp_session_set_local_addr(session,addr,port, port2)
	RtpSession*	session
	const char*	addr
	int		port
	int		port2

int
rtp_session_get_local_port(session)
	RtpSession* session
	
int
rtp_session_set_remote_addr(session,addr,port)
	RtpSession*	session
	const char*	addr
	int			port

void
rtp_session_set_jitter_compensation(session,milisec)
	RtpSession*	session
	int			milisec

int
rtp_session_get_jitter_compensation(session)
	RtpSession*	session
  CODE:
	RETVAL = session->rtp.jittctl.jitt_comp;
  OUTPUT:
	RETVAL
	

void
rtp_session_enable_adaptive_jitter_compensation(session,val)
	RtpSession*	session
	int			val

int
rtp_session_adaptive_jitter_compensation_enabled(session)
	RtpSession*	session
  CODE:
	RETVAL = rtp_session_adaptive_jitter_compensation_enabled( session );
  OUTPUT:
	RETVAL


void
rtp_session_set_ssrc(session,ssrc)
	RtpSession*	session
	int			ssrc
	
int
rtp_session_get_send_ssrc(session)
	RtpSession*	session
  CODE:
	RETVAL = 450851100;
  OUTPUT:
	RETVAL

void
rtp_session_set_seq_number(session,seq)
	RtpSession*	session
	int			seq

int
rtp_session_get_send_seq_number(session)
	RtpSession*	session
  CODE:
	RETVAL = session->rtp.snd_seq;
  OUTPUT:
	RETVAL

int
rtp_session_set_send_payload_type(session,pt)
	RtpSession*	session
	int			pt

int
rtp_session_get_send_payload_type(session)
	RtpSession*	session

int
rtp_session_get_recv_payload_type(session)
	RtpSession*	session
	
int
rtp_session_set_recv_payload_type(session,pt)
	RtpSession*	session
	int			pt

int
rtp_session_send_with_ts(session,sv,userts)
	RtpSession*	session
	SV*			sv
	int			userts
  PREINIT:
	STRLEN len = 0;
	const char * ptr = NULL;
  CODE:
  	ptr = SvPV( sv, len );
  	RETVAL = rtp_session_send_with_ts( session, ptr, len, userts );
  OUTPUT:
	RETVAL


SV*
rtp_session_recv_with_ts(session,wanted,userts)
	RtpSession*	session
	int			wanted
	int			userts
  PREINIT:
  	char* buffer = malloc( wanted );
  	char* ptr = buffer;
  	int buf_len = wanted;
  	int buf_used=0, bytes=0;
  	int have_more=1;
  CODE:
	while (have_more) {
		bytes = rtp_session_recv_with_ts(session,ptr,buf_len-buf_used,userts,&have_more);
		if (bytes<=0) break;
		buf_used += bytes;
		
		// Allocate some more memory
		if (have_more) {
			buffer = realloc( buffer, buf_len + wanted );
			buf_len += wanted;
			ptr = buffer + buf_used;
		}
	}
	
	if (bytes<=0) {
 		RETVAL = &PL_sv_undef;
  	} else {
		RETVAL = newSVpvn( buffer, buf_used );
  	}
  	
  	free( buffer );
  OUTPUT:
	RETVAL


void
rtp_session_flush_sockets(session)
	RtpSession*	session
	
void
rtp_session_release_sockets(session)
	RtpSession*	session
	
void
rtp_session_reset(session)
	RtpSession*	session

	
void
rtp_session_destroy(session)
	RtpSession*	session



mblk_t*
rtp_session_recvm_with_ts(session,user_ts)
	RtpSession*	session
	int			user_ts


void
rtp_set_markbit(mp,value)
	mblk_t* mp
	int     value
  CODE:
    rtp_set_markbit( mp, value );


void
rtp_set_seqnumber(mp,value)
	mblk_t* mp
	int     value
  CODE:
    rtp_set_seqnumber( mp, value );


void
rtp_set_timestamp(mp,value)
	mblk_t* mp
	int     value
  CODE:
    rtp_set_timestamp( mp, value );


void
rtp_set_ssrc(mp,value)
	mblk_t* mp
	int     value
  CODE:
    rtp_set_ssrc( mp, value );


void
rtp_set_payload_type(mp,value)
	mblk_t* mp
	int     value
  CODE:
    rtp_set_payload_type( mp, value );



int
rtp_get_markbit(mp)
	mblk_t* mp
  CODE:
	RETVAL = rtp_get_markbit(mp);
  OUTPUT:
	RETVAL

int
rtp_get_seqnumber(mp)
	mblk_t* mp
  CODE:
	RETVAL = rtp_get_seqnumber(mp);
  OUTPUT:
	RETVAL


int
rtp_get_timestamp(mp)
	mblk_t* mp
  CODE:
	RETVAL = rtp_get_timestamp(mp);
  OUTPUT:
	RETVAL

int
rtp_get_ssrc(mp)
	mblk_t* mp
  CODE:
	RETVAL = rtp_get_ssrc(mp);
  OUTPUT:
	RETVAL

int
rtp_get_payload_type(mp)
	mblk_t* mp
  CODE:
	RETVAL = rtp_get_payload_type(mp);
  OUTPUT:
	RETVAL

