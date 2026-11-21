#ifndef HK_AOM_BRIDGE_H
#define HK_AOM_BRIDGE_H
#include <stddef.h>
#include <stdint.h>

/* Sessions and returned buffers are confined to a single caller. Output pointers
 * remain valid only until the next encode/decode call or session destruction. */
typedef struct HKAOMSession HKAOMSession;
typedef struct {
    const uint8_t *y, *u, *v;
    int y_stride, u_stride, v_stride;
    unsigned int width, height;
    int full_range;
} HKAOMImage;

HKAOMSession *hk_aom_encoder_create(unsigned int width, unsigned int height,
    unsigned int bitrate_kbps, double fps, int64_t keyframe_interval_us, int constant_bitrate, int *status);
int hk_aom_encoder_update(HKAOMSession *session, unsigned int bitrate_kbps, double fps);
int hk_aom_encoder_encode(HKAOMSession *session, const uint8_t *y, int y_stride,
    const uint8_t *u, int u_stride, const uint8_t *v, int v_stride, int64_t pts, unsigned long duration);
int hk_aom_encoder_flush(HKAOMSession *session);
const uint8_t *hk_aom_encoder_next_packet(HKAOMSession *session, size_t *size,
    int64_t *pts, unsigned long *duration, int *keyframe);
HKAOMSession *hk_aom_decoder_create(int *status);
int hk_aom_decoder_decode(HKAOMSession *session, const uint8_t *data, unsigned int size);
int hk_aom_decoder_next_image(HKAOMSession *session, HKAOMImage *image);
void hk_aom_destroy(HKAOMSession *session);
#endif
