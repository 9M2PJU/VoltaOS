#include "CarVideoDecoder.h"

#include <QDebug>
#include <QImage>
#include <QMetaObject>
#include <QVideoFrame>
#include <QVideoFrameFormat>
#include <cstring>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/frame.h>
#include <libavutil/imgutils.h>
}

CarVideoDecoder::CarVideoDecoder() = default;
CarVideoDecoder::~CarVideoDecoder() { close(); }

void CarVideoDecoder::setSink(QVideoSink *sink)
{
    QMutexLocker l(&m_sinkLock);
    m_sink = sink;
}

bool CarVideoDecoder::open()
{
    const AVCodec *codec = avcodec_find_decoder(AV_CODEC_ID_H264);
    if (!codec) { qWarning() << "[AA] H.264 decoder not available in FFmpeg"; return false; }
    m_ctx = avcodec_alloc_context3(codec);
    // Low latency: no frames held back for reordering, one thread per slice
    m_ctx->flags |= AV_CODEC_FLAG_LOW_DELAY;
    m_ctx->flags2 |= AV_CODEC_FLAG2_FAST;
    m_ctx->thread_count = 0;
    m_ctx->thread_type = FF_THREAD_SLICE;
    if (avcodec_open2(m_ctx, codec, nullptr) < 0) {
        qWarning() << "[AA] opening the H.264 decoder failed";
        avcodec_free_context(&m_ctx);
        return false;
    }
    m_frame = av_frame_alloc();
    m_pkt = av_packet_alloc();
    return true;
}

void CarVideoDecoder::close()
{
    if (m_pkt) av_packet_free(&m_pkt);
    if (m_frame) av_frame_free(&m_frame);
    if (m_ctx) avcodec_free_context(&m_ctx);
}

void CarVideoDecoder::reset()
{
    close();
    m_frames = 0;
}

void CarVideoDecoder::decode(const QByteArray &h264)
{
    if (!m_ctx && !open()) return;
    // libavcodec wants some zero padding at the end of the buffer
    QByteArray buf = h264;
    buf.append(QByteArray(AV_INPUT_BUFFER_PADDING_SIZE, '\0'));
    m_pkt->data = reinterpret_cast<uint8_t *>(buf.data());
    m_pkt->size = int(h264.size());
    if (avcodec_send_packet(m_ctx, m_pkt) < 0) return;
    while (avcodec_receive_frame(m_ctx, m_frame) == 0) {
        deliver(m_frame);
        av_frame_unref(m_frame);
    }
}

void CarVideoDecoder::deliver(AVFrame *f)
{
    QPointer<QVideoSink> sink;
    {
        QMutexLocker l(&m_sinkLock);
        sink = m_sink;
    }
    ++m_frames;
    if (!sink) return;
    if (f->format != AV_PIX_FMT_YUV420P && f->format != AV_PIX_FMT_YUVJ420P) {
        if (m_frames == 1) qWarning() << "[AA] formato video inatteso" << f->format;
        return;
    }

    QVideoFrameFormat fmt(QSize(f->width, f->height), QVideoFrameFormat::Format_YUV420P);
    fmt.setColorRange(f->format == AV_PIX_FMT_YUVJ420P || f->color_range == AVCOL_RANGE_JPEG
                      ? QVideoFrameFormat::ColorRange_Full : QVideoFrameFormat::ColorRange_Video);
    fmt.setColorSpace(QVideoFrameFormat::ColorSpace_BT709);
    QVideoFrame frame(fmt);
    if (!frame.map(QVideoFrame::WriteOnly)) return;
    for (int p = 0; p < 3; ++p) {
        const int h = p == 0 ? f->height : (f->height + 1) / 2;
        const int w = p == 0 ? f->width  : (f->width + 1) / 2;
        uint8_t *dst = frame.bits(p);
        const int dstStride = frame.bytesPerLine(p);
        const uint8_t *src = f->data[p];
        for (int y = 0; y < h; ++y)
            std::memcpy(dst + y * dstStride, src + y * f->linesize[p], size_t(w));
    }
    frame.unmap();
    static const QString dumpPath = qEnvironmentVariable("VOLTA_CARLINK_DUMP");
    if (!dumpPath.isEmpty() && m_frames == 90) frame.toImage().save(dumpPath);
    QMetaObject::invokeMethod(sink, [sink, frame]() {
        if (sink) sink->setVideoFrame(frame);
    }, Qt::QueuedConnection);
}
