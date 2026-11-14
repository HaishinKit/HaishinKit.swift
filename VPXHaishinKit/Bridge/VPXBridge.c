#include "VPXBridge.h"
#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <vpx/vp8cx.h>
#include <vpx/vp8dx.h>
#include <vpx/vpx_encoder.h>
#include <vpx/vpx_decoder.h>

struct HKVPXSession {
    vpx_codec_ctx_t codec;
    vpx_codec_enc_cfg_t config;
    vpx_codec_iter_t iterator;
    vpx_image_t image;
    int initialized;
    int has_keyframe;
    int64_t last_keyframe_pts;
    int64_t keyframe_interval_us;
};

void hk_vpx_destroy(HKVPXSession *session) {
    if (!session) return;
    if (session->initialized) vpx_codec_destroy(&session->codec);
    free(session);
}

HKVPXSession *hk_vpx_encoder_create(int codec, unsigned int width, unsigned int height,
    unsigned int bitrate_kbps, double fps, int64_t keyframe_interval_us, int constant_bitrate, int *status) {
    *status = VPX_CODEC_INVALID_PARAM;
    if ((codec != 8 && codec != 9) || !width || !height || !bitrate_kbps || !isfinite(fps) || fps <= 0 || keyframe_interval_us <= 0) return NULL;
    HKVPXSession *session = calloc(1, sizeof(*session));
    if (!session) { *status = VPX_CODEC_MEM_ERROR; return NULL; }
    vpx_codec_iface_t *iface = codec == 8 ? vpx_codec_vp8_cx() : vpx_codec_vp9_cx();
    *status = vpx_codec_enc_config_default(iface, &session->config, 0);
    if (*status != VPX_CODEC_OK) goto fail;
    session->config.g_w = width;
    session->config.g_h = height;
    session->config.g_timebase.num = 1;
    session->config.g_timebase.den = 1000000;
    session->config.g_threads = 2;
    session->config.g_lag_in_frames = 0;
    session->config.rc_target_bitrate = bitrate_kbps;
    session->config.rc_end_usage = constant_bitrate ? VPX_CBR : VPX_VBR;
    session->config.rc_dropframe_thresh = 0;
    session->config.kf_mode = VPX_KF_AUTO;
    session->config.kf_max_dist = INT_MAX;
    session->keyframe_interval_us = keyframe_interval_us;
    *status = vpx_codec_enc_init(&session->codec, iface, &session->config, 0);
    if (*status != VPX_CODEC_OK) goto fail;
    session->initialized = 1;
    *status = vpx_codec_control(&session->codec, VP8E_SET_CPUUSED, codec == 8 ? 8 : 7);
    if (*status != VPX_CODEC_OK) goto fail;
    *status = vpx_codec_control(&session->codec, VP8E_SET_ENABLEAUTOALTREF, 0);
    if (*status != VPX_CODEC_OK) goto fail;
    session->image.fmt = VPX_IMG_FMT_I420;
    session->image.w = session->image.d_w = width;
    session->image.h = session->image.d_h = height;
    session->image.bit_depth = 8;
    session->image.x_chroma_shift = session->image.y_chroma_shift = 1;
    session->image.range = VPX_CR_STUDIO_RANGE;
    return session;
fail:
    hk_vpx_destroy(session);
    return NULL;
}

int hk_vpx_encoder_update(HKVPXSession *session, unsigned int bitrate_kbps, double fps) {
    if (!session || !bitrate_kbps || !isfinite(fps) || fps <= 0) return VPX_CODEC_INVALID_PARAM;
    vpx_codec_enc_cfg_t config = session->config;
    config.rc_target_bitrate = bitrate_kbps;
    int status = vpx_codec_enc_config_set(&session->codec, &config);
    if (status == VPX_CODEC_OK) session->config = config;
    return status;
}

int hk_vpx_encoder_encode(HKVPXSession *session, const uint8_t *y, int y_stride,
    const uint8_t *u, int u_stride, const uint8_t *v, int v_stride, int64_t pts, unsigned long duration) {
    if (!session || !y || !u || !v || !duration) return VPX_CODEC_INVALID_PARAM;
    session->image.planes[0] = (uint8_t *)y;
    session->image.planes[1] = (uint8_t *)u;
    session->image.planes[2] = (uint8_t *)v;
    session->image.stride[0] = y_stride;
    session->image.stride[1] = u_stride;
    session->image.stride[2] = v_stride;
    session->iterator = NULL;
    int flags = session->has_keyframe && pts >= session->last_keyframe_pts &&
        (uint64_t)pts - (uint64_t)session->last_keyframe_pts >= (uint64_t)session->keyframe_interval_us ? VPX_EFLAG_FORCE_KF : 0;
    return vpx_codec_encode(&session->codec, &session->image, pts, duration, flags, VPX_DL_REALTIME);
}

const uint8_t *hk_vpx_encoder_next_packet(HKVPXSession *session, size_t *size,
    int64_t *pts, unsigned long *duration, int *keyframe) {
    const vpx_codec_cx_pkt_t *packet;
    while ((packet = vpx_codec_get_cx_data(&session->codec, &session->iterator))) {
        if (packet->kind != VPX_CODEC_CX_FRAME_PKT) continue;
        *size = packet->data.frame.sz;
        *pts = packet->data.frame.pts;
        *duration = packet->data.frame.duration;
        *keyframe = (packet->data.frame.flags & VPX_FRAME_IS_KEY) != 0;
        if (*keyframe) {
            session->has_keyframe = 1;
            session->last_keyframe_pts = *pts;
        }
        return packet->data.frame.buf;
    }
    return NULL;
}

HKVPXSession *hk_vpx_decoder_create(int codec, int *status) {
    *status = VPX_CODEC_INVALID_PARAM;
    if (codec != 8 && codec != 9) return NULL;
    HKVPXSession *session = calloc(1, sizeof(*session));
    if (!session) { *status = VPX_CODEC_MEM_ERROR; return NULL; }
    vpx_codec_dec_cfg_t config = { .threads = 2 };
    *status = vpx_codec_dec_init(&session->codec, codec == 8 ? vpx_codec_vp8_dx() : vpx_codec_vp9_dx(), &config, 0);
    if (*status != VPX_CODEC_OK) { hk_vpx_destroy(session); return NULL; }
    session->initialized = 1;
    return session;
}

int hk_vpx_decoder_decode(HKVPXSession *session, const uint8_t *data, unsigned int size) {
    if (!session || !data || !size) return VPX_CODEC_INVALID_PARAM;
    session->iterator = NULL;
    return vpx_codec_decode(&session->codec, data, size, NULL, 0);
}

int hk_vpx_decoder_next_image(HKVPXSession *session, HKVPXImage *image) {
    vpx_image_t *decoded = vpx_codec_get_frame(&session->codec, &session->iterator);
    if (!decoded) return 0;
    /* This artifact and the Swift pixel-buffer pipeline support 8-bit 4:2:0. */
    if (decoded->fmt != VPX_IMG_FMT_I420 || decoded->bit_depth != 8) return -1;
    image->y = decoded->planes[0]; image->u = decoded->planes[1]; image->v = decoded->planes[2];
    image->y_stride = decoded->stride[0]; image->u_stride = decoded->stride[1]; image->v_stride = decoded->stride[2];
    image->width = decoded->d_w; image->height = decoded->d_h;
    image->full_range = decoded->range == VPX_CR_FULL_RANGE;
    return 1;
}
