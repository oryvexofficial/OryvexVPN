#ifndef ORYVEX_FAKE_H
#define ORYVEX_FAKE_H

#include "platform.h"
#include "proto.h"

/* A decoy first segment: the filter reads it, the server never does.
 *
 * TCP retransmits anything it has not had acknowledged, so a decoy is only
 * safe if the bytes the kernel will resend can still be changed after they
 * have gone out once. Linux can: pages gifted to the socket with
 * vmsplice(SPLICE_F_GIFT) stay writable, so the retransmission carries the
 * real request.
 *
 * Windows cannot, and the failure is worse than having no decoy at all.
 * TransmitFile hands the bytes to the transport when it is called, so
 * rewriting the file afterwards changes nothing and the decoy itself is
 * delivered. Worse, our decoy is the real request with only the server name
 * swapped, so the server answers it with a well-formed handshake — the attempt
 * passes our reply check, gets remembered as "this technique works", and the
 * browser then fails on a certificate for the wrong name, for every later
 * visit. A technique that cannot be verified is not worth a cached lie, so it
 * is not built there. Windows reaches the same filters through tlsrec, split,
 * disorder and oob — the combination Turkish users actually run — and through
 * Advanced mode, which does this properly at the packet layer.
 *
 * macOS offers neither mechanism, for the same reason.
 */
#if defined(__linux__)
#define ORYVEX_HAS_FAKE 1
#endif

/* 1 when this build can send decoys. */
int fake_available(void);

/* Send bytes [0,n) of `real` as a decoy. The server receives the real bytes
 * when TCP retransmits the segment. Returns how many bytes were handed to the
 * socket (the caller continues from there), or -1 if nothing was sent. */
int fake_send_first(sock_t s, int family, const uint8_t *real, int n,
                    const proto_info *pi, int ttl, int use_md5);

#endif
