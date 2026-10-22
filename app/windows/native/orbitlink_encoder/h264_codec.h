// Media Foundation H.264 codec used by the OrbitLink capture/controller path.
//
// Encoder: BGRA (GDI or WGC staging) -> NV12 -> Microsoft H.264 MFT, Annex-B
// output. Decoder: Annex-B access unit -> NV12 -> BGRA for Flutter.
//
// Every instance owns its COM apartment state and must be created, used and
// destroyed on the same thread (the Dart workers satisfy that).

#pragma once

#include <stdint.h>

#include <string>
#include <vector>

namespace orbitlink {

class H264Encoder {
 public:
  H264Encoder(int width, int height, int fps, int bitrateKbps);
  ~H264Encoder();

  H264Encoder(const H264Encoder&) = delete;
  H264Encoder& operator=(const H264Encoder&) = delete;

  bool ok() const { return ok_; }
  int width() const { return width_; }
  int height() const { return height_; }
  const std::string& message() const { return message_; }

  void RequestKeyframe();
  bool Encode(const uint8_t* bgra,
              int64_t timestampMs,
              std::vector<uint8_t>& output,
              bool* keyframe);

 private:
  bool Configure();
  bool Drain(std::vector<uint8_t>& output, bool* keyframe);
  bool EnsureOutputSample(uint32_t size);

  int width_ = 0;
  int height_ = 0;
  int fps_ = 30;
  int bitrateKbps_ = 6000;
  bool ok_ = false;
  bool streaming_ = false;
  void* mft_ = nullptr;          // IMFTransform
  void* outputType_ = nullptr;   // IMFMediaType
  void* outputSample_ = nullptr; // IMFSample
  uint32_t outputBufferSize_ = 0;
  std::vector<uint8_t> nv12_;
  std::string message_;
};

class H264Decoder {
 public:
  H264Decoder();
  ~H264Decoder();

  H264Decoder(const H264Decoder&) = delete;
  H264Decoder& operator=(const H264Decoder&) = delete;

  bool ok() const { return ok_; }
  const std::string& message() const { return message_; }

  // Returns 1 when a frame was produced, 0 when more input is needed,
  // 2 when |dst| is too small (required size in |outSize|), negative on error.
  int Decode(const uint8_t* data,
             int size,
             int width,
             int height,
             int64_t timestampMs,
             uint8_t* dst,
             int capacity,
             int* outSize,
             int* outWidth,
             int* outHeight);

  void Reset();

 private:
  bool CreateTransform();
  bool ConfigureInput(const uint8_t* data, int size, int width, int height);
  bool ConfigureOutput();
  int Drain(uint8_t* dst,
            int capacity,
            int* outSize,
            int* outWidth,
            int* outHeight,
            bool* produced);
  void ReleaseTransform();

  void* mft_ = nullptr;        // IMFTransform
  void* outputType_ = nullptr; // IMFMediaType
  bool ok_ = false;
  bool streaming_ = false;
  bool inputConfigured_ = false;
  bool outputConfigured_ = false;
  int width_ = 0;
  int height_ = 0;
  int stride_ = 0;
  int inputWidth_ = 0;
  int inputHeight_ = 0;
  int64_t nextTimestamp_ = 0;
  std::string message_;
};

}  // namespace orbitlink
