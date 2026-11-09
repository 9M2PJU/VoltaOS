#pragma once
// Phone audio (output) and microphone (input) for CarPlay / Android Auto.
// Header-only: small classes, used only by CarlinkDongle in the main thread.

#include <QAudioFormat>
#include <QAudioSink>
#include <QAudioSource>
#include <QByteArray>
#include <QMediaDevices>
#include <QObject>
#include <QTimer>
#include <functional>

// Output: accumulates the PCM and passes it to the sound card in small chunks, never
// accumulating more than half a second (if the phone is faster, the old data is dropped).
class CarAudioOut : public QObject {
public:
    CarAudioOut(int rate, int channels, QObject *parent = nullptr) : QObject(parent)
    {
        m_fmt.setSampleRate(rate);
        m_fmt.setChannelCount(channels);
        m_fmt.setSampleFormat(QAudioFormat::Int16);
        m_pump.setInterval(10);
        connect(&m_pump, &QTimer::timeout, this, [this] { pump(); });
    }
    int rate() const { return m_fmt.sampleRate(); }
    int channels() const { return m_fmt.channelCount(); }
    void setVolume(float v) { m_volume = v; if (m_sink) m_sink->setVolume(v); }

    void push(const QByteArray &pcm)
    {
        if (!m_sink) {
            m_sink = new QAudioSink(QMediaDevices::defaultAudioOutput(), m_fmt, this);
            m_sink->setBufferSize(m_fmt.bytesForDuration(150000));
            m_sink->setVolume(m_volume);
            m_io = m_sink->start();
            m_pump.start();
        }
        m_pending.append(pcm);
        const int maxBytes = m_fmt.bytesForDuration(500000);
        if (m_pending.size() > maxBytes) m_pending.remove(0, m_pending.size() - maxBytes);
        pump();
    }
    void stop()
    {
        m_pump.stop();
        m_pending.clear();
        if (m_sink) { m_sink->stop(); delete m_sink; m_sink = nullptr; m_io = nullptr; }
    }

private:
    void pump()
    {
        if (!m_io || m_pending.isEmpty()) return;
        const qint64 n = m_io->write(m_pending.constData(), qMin<qint64>(m_pending.size(), m_sink->bytesFree()));
        if (n > 0) m_pending.remove(0, n);
    }
    QAudioFormat m_fmt;
    QAudioSink *m_sink = nullptr;
    QIODevice *m_io = nullptr;
    QByteArray m_pending;
    QTimer m_pump;
    float m_volume = 1.0f;
};

// Microphone (16 kHz mono): for Siri / Google Assistant
class CarMic : public QObject {
public:
    explicit CarMic(QObject *parent = nullptr) : QObject(parent) {}
    std::function<void(const QByteArray &)> onPcm;
    void start()
    {
        if (m_src) return;
        QAudioFormat f;
        f.setSampleRate(16000);
        f.setChannelCount(1);
        f.setSampleFormat(QAudioFormat::Int16);
        m_src = new QAudioSource(QMediaDevices::defaultAudioInput(), f, this);
        m_io = m_src->start();
        if (!m_io) return;
        connect(m_io, &QIODevice::readyRead, this, [this] {
            const QByteArray pcm = m_io->readAll();
            if (!pcm.isEmpty() && onPcm) onPcm(pcm);
        });
    }
    void stop()
    {
        if (!m_src) return;
        m_src->stop();
        delete m_src;
        m_src = nullptr;
        m_io = nullptr;
    }
private:
    QAudioSource *m_src = nullptr;
    QIODevice *m_io = nullptr;
};
