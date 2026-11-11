#ifndef ORYVEX_DESYNC_H
#include <stdint.h>
#define ORYVEX_DESYNC_H

#include "platform.h"
#include "strategy.h"
#include "proto.h"

/* Send the first client payload to the upstream socket applying the strategy.
 * `family` is the upstream address family (for TTL ops). `cap` is the capacity
 * of `payload`, which may be rewritten in place (TLS record fragmentation adds
 * five bytes per extra record). Returns 0 on success. */
int desync_send_first(sock_t up, int family,
                      uint8_t *payload, int len, int cap,
                      const proto_info *pi, const strategy *st,
                      _Atomic uint64_t *desync_counter);

#endif
