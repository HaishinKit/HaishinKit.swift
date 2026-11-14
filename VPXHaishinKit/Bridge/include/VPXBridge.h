#ifndef HK_VPX_BRIDGE_H
#define HK_VPX_BRIDGE_H
#include <stddef.h>
#include <stdint.h>

/* Sessions and returned buffers are confined to a single caller. Output pointers
 * remain valid only until the next encode/decode call or session destruction. */
typedef struct HKVPXSession HKVPXSession;
typedef struct {
    const uint8_t *y, *u, *v;
    int y_stride, u_stride, v_stride;
    unsigned int width, height;
    int full_range;
} HKVPXImage;

HKVPXSession *hk_vpx_encoder_create(int codec, unsigned int width, unsigned int height,
    unsigned int bitrate_kbps, double fps, int64_t keyframe_interval_us, int constant_bitrate, int *status);
int hk_vpx_encoder_update(HKVPXSession *session, unsigned int bitrate_kbps, double fps);
int hk_vpx_encoder_encode(HKVPXSession *session, const uint8_t *y, int y_stride,
    const uint8_t *u, int u_stride, const uint8_t *v, int v_stride, int64_t pts, unsigned long duration);
const uint8_t *hk_vpx_encoder_next_packet(HKVPXSession *session, size_t *size,
    int64_t *pts, unsigned long *duration, int *keyframe);
HKVPXSession *hk_vpx_decoder_create(int codec, int *status);
int hk_vpx_decoder_decode(HKVPXSession *session, const uint8_t *data, unsigned int size);
int hk_vpx_decoder_next_image(HKVPXSession *session, HKVPXImage *image);
void hk_vpx_destroy(HKVPXSession *session);
#endif
