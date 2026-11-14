#ifndef IMPORTED_PROTOCOL_PEER_H
#define IMPORTED_PROTOCOL_PEER_H
#include <stdint.h>
struct imported_protocol_peer;
struct imported_protocol_peer *imported_protocol_peer_create(int *descriptor);
uint32_t imported_protocol_peer_global(struct imported_protocol_peer *peer);
uint32_t imported_protocol_peer_compositor_global(struct imported_protocol_peer *peer);
int imported_protocol_peer_dispatch(struct imported_protocol_peer *peer);
unsigned imported_protocol_peer_pongs(struct imported_protocol_peer *peer);
unsigned imported_protocol_peer_positioner_sizes(struct imported_protocol_peer *peer);
unsigned imported_protocol_peer_configure_acks(struct imported_protocol_peer *peer);
unsigned imported_protocol_peer_resources(struct imported_protocol_peer *peer);
void imported_protocol_peer_destroy(struct imported_protocol_peer *peer);
#endif
