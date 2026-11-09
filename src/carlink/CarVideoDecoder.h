#pragma once
// H.264 decoder for the Android Auto video (FFmpeg/libavcodec) that delivers
// frames to a QVideoSink, i.e. to a VideoOutput of the UI.

#include <QByteArray>
#include <QPointer>
#include <QVideoSink>
#include <QMutex>

struct AVCodecContext;
struct AVFrame;
struct AVPacket;

class CarVideoDecoder {
public:
    CarVideoDecoder();
    ~CarVideoDecoder();

    void setSink(QVideoSink *sink);
    // H.264 Annex-B data (with 00 00 01 start codes), possibly several units at once.
    void decode(const QByteArray &h264);
    void reset();
    int frames() const { return m_frames; }

private:
    bool open();
    void close();
    void deliver(AVFrame *f);

    AVCodecContext *m_ctx = nullptr;
    AVFrame *m_frame = nullptr;
    AVPacket *m_pkt = nullptr;
    QMutex m_sinkLock;
    QPointer<QVideoSink> m_sink;
    int m_frames = 0;
};
