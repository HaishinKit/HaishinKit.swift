#include "AOMBridge.h"
#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <aom/aomcx.h>
#include <aom/aomdx.h>
#include <aom/aom_encoder.h>
#include <aom/aom_decoder.h>

struct HKAOMSession {
    aom_codec_ctx_t codec;
    aom_codec_enc_cfg_t config;
    aom_codec_iter_t iterator;
    aom_image_t image;
    int initialized;
    int has_keyframe;
    int64_t last_keyframe_pts;
    int64_t keyframe_interval_us;
};

void hk_aom_destroy(HKAOMSession *session) {
    if (!session) return;
    if (session->initialized) aom_codec_destroy(&session->codec);
    free(session);
}

HKAOMSession *hk_aom_encoder_create(unsigned int width, unsigned int height,
    unsigned int bitrate_kbps, double fps, int64_t keyframe_interval_us, int constant_bitrate, int *status) {
    *status = AOM_CODEC_INVALID_PARAM;
    if (!width || !height || !bitrate_kbps || !isfinite(fps) || fps <= 0 || keyframe_interval_us <= 0) return NULL;
    HKAOMSession *session = calloc(1, sizeof(*session));
    if (!session) { *status = AOM_CODEC_MEM_ERROR; return NULL; }
    aom_codec_iface_t *iface = aom_codec_av1_cx();
    *status = aom_codec_enc_config_default(iface, &session->config, AOM_USAGE_REALTIME);
    if (*status != AOM_CODEC_OK) goto fail;
    session->config.g_profile = 0;
    session->config.monochrome = 0;
    session->config.g_bit_depth = AOM_BITS_8;
    session->config.g_input_bit_depth = 8;
    session->config.rc_resize_mode = 0;
    session->config.rc_superres_mode = AOM_SUPERRES_NONE;
    session->config.g_w = width;
    session->config.g_h = height;
    session->config.g_timebase.num = 1;
    session->config.g_timebase.den = 1000000;
    session->config.g_threads = 2;
    session->config.g_lag_in_frames = 0;
    session->config.rc_target_bitrate = bitrate_kbps;
    session->config.rc_end_usage = constant_bitrate ? AOM_CBR : AOM_VBR;
    session->config.rc_dropframe_thresh = 0;
    session->config.kf_mode = AOM_KF_AUTO;
    session->config.kf_max_dist = INT_MAX;
    session->keyframe_interval_us = keyframe_interval_us;
    *status = aom_codec_enc_init(&session->codec, iface, &session->config, 0);
    if (*status != AOM_CODEC_OK) goto fail;
    session->initialized = 1;
    *status = aom_codec_control(&session->codec, AOME_SET_CPUUSED, 8);
    if (*status != AOM_CODEC_OK) goto fail;
    *status = aom_codec_control(&session->codec, AOME_SET_ENABLEAUTOALTREF, 0);
    if (*status != AOM_CODEC_OK) goto fail;
    *status = aom_codec_control(&session->codec, AV1E_SET_CHROMA_SAMPLE_POSITION, AOM_CSP_UNKNOWN);
    if (*status != AOM_CODEC_OK) goto fail;
    *status = aom_codec_control(&session->codec, AV1E_SET_COLOR_RANGE, 0);
    if (*status != AOM_CODEC_OK) goto fail;
    session->image.fmt = AOM_IMG_FMT_I420;
    session->image.w = session->image.d_w = width;
    session->image.h = session->image.d_h = height;
    session->image.bit_depth = 8;
    session->image.x_chroma_shift = session->image.y_chroma_shift = 1;
    session->image.range = AOM_CR_STUDIO_RANGE;
    return session;
fail:
    hk_aom_destroy(session);
    return NULL;
}

int hk_aom_encoder_update(HKAOMSession *session, unsigned int bitrate_kbps, double fps) {
    if (!session || !bitrate_kbps || !isfinite(fps) || fps <= 0) return AOM_CODEC_INVALID_PARAM;
    aom_codec_enc_cfg_t config = session->config;
    config.rc_target_bitrate = bitrate_kbps;
    int status = aom_codec_enc_config_set(&session->codec, &config);
    if (status == AOM_CODEC_OK) session->config = config;
    return status;
}

int hk_aom_encoder_encode(HKAOMSession *session, const uint8_t *y, int y_stride,
    const uint8_t *u, int u_stride, const uint8_t *v, int v_stride, int64_t pts, unsigned long duration) {
    if (!session || !y || !u || !v || !duration) return AOM_CODEC_INVALID_PARAM;
    session->image.planes[0] = (uint8_t *)y;
    session->image.planes[1] = (uint8_t *)u;
    session->image.planes[2] = (uint8_t *)v;
    session->image.stride[0] = y_stride;
    session->image.stride[1] = u_stride;
    session->image.stride[2] = v_stride;
    session->iterator = NULL;
    int flags = session->has_keyframe && pts >= session->last_keyframe_pts &&
        (uint64_t)pts - (uint64_t)session->last_keyframe_pts >= (uint64_t)session->keyframe_interval_us ? AOM_EFLAG_FORCE_KF : 0;
    return aom_codec_encode(&session->codec, &session->image, pts, duration, flags);
}

int hk_aom_encoder_flush(HKAOMSession *session) {
    if (!session) return AOM_CODEC_INVALID_PARAM;
    session->iterator = NULL;
    return aom_codec_encode(&session->codec, NULL, 0, 0, 0);
}

const uint8_t *hk_aom_encoder_next_packet(HKAOMSession *session, size_t *size,
    int64_t *pts, unsigned long *duration, int *keyframe) {
    const aom_codec_cx_pkt_t *packet;
    while ((packet = aom_codec_get_cx_data(&session->codec, &session->iterator))) {
        if (packet->kind != AOM_CODEC_CX_FRAME_PKT) continue;
        *size = packet->data.frame.sz;
        *pts = packet->data.frame.pts;
        *duration = packet->data.frame.duration;
        *keyframe = (packet->data.frame.flags & AOM_FRAME_IS_KEY) != 0;
        if (*keyframe) {
            session->has_keyframe = 1;
            session->last_keyframe_pts = *pts;
        }
        return packet->data.frame.buf;
    }
    return NULL;
}

HKAOMSession *hk_aom_decoder_create(int *status) {
    *status = AOM_CODEC_INVALID_PARAM;
    HKAOMSession *session = calloc(1, sizeof(*session));
    if (!session) { *status = AOM_CODEC_MEM_ERROR; return NULL; }
    aom_codec_dec_cfg_t config = { .threads = 2, .allow_lowbitdepth = 1 };
    *status = aom_codec_dec_init(&session->codec, aom_codec_av1_dx(), &config, 0);
    if (*status != AOM_CODEC_OK) { hk_aom_destroy(session); return NULL; }
    session->initialized = 1;
    return session;
}

int hk_aom_decoder_decode(HKAOMSession *session, const uint8_t *data, unsigned int size) {
    if (!session || !data || !size) return AOM_CODEC_INVALID_PARAM;
    session->iterator = NULL;
    return aom_codec_decode(&session->codec, data, size, NULL);
}

int hk_aom_decoder_next_image(HKAOMSession *session, HKAOMImage *image) {
    aom_image_t *decoded = aom_codec_get_frame(&session->codec, &session->iterator);
    if (!decoded) return 0;
    /* This artifact and the Swift pixel-buffer pipeline support 8-bit 4:2:0. */
    if (decoded->fmt != AOM_IMG_FMT_I420 || decoded->bit_depth != 8) return -1;
    image->y = decoded->planes[0]; image->u = decoded->planes[1]; image->v = decoded->planes[2];
    image->y_stride = decoded->stride[0]; image->u_stride = decoded->stride[1]; image->v_stride = decoded->stride[2];
    image->width = decoded->d_w; image->height = decoded->d_h;
    image->full_range = decoded->range == AOM_CR_FULL_RANGE;
    return 1;
}
