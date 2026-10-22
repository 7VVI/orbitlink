// Standalone H.264 encode/decode verification.
//
// Feeds synthetic 1600x900 BGRA frames through the Media Foundation encoder,
// decodes every access unit again and reports throughput plus round-trip PSNR.

#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <vector>

#include "h264_codec.h"

namespace {

void FillFrame(std::vector<uint8_t>& bgra, int width, int height, int frame) {
  bgra.resize(static_cast<size_t>(width) * height * 4);
  for (int row = 0; row < height; row++) {
    uint8_t* line = bgra.data() + static_cast<size_t>(row) * width * 4;
    for (int col = 0; col < width; col++) {
      const int block = ((col / 32) + (row / 32) + frame / 10) % 3;
      int r = (col * 255) / width;
      int g = (row * 255) / height;
      int b = block * 90 + 20;
      if (((col / 12) ^ (row / 12)) & 1) {
        // Thin one-pixel text-like strokes.
        r = 20;
        g = 240;
        b = 200;
      }
      line[col * 4 + 0] = static_cast<uint8_t>(b);
      line[col * 4 + 1] = static_cast<uint8_t>(g);
      line[col * 4 + 2] = static_cast<uint8_t>(r);
      line[col * 4 + 3] = 255;
    }
  }
}

double Psnr(const std::vector<uint8_t>& a, const std::vector<uint8_t>& b) {
  if (a.size() != b.size() || a.empty()) return 0;
  double sum = 0;
  size_t count = 0;
  for (size_t i = 0; i + 3 < a.size(); i += 4) {
    for (int c = 0; c < 3; c++) {
      const double diff = static_cast<double>(a[i + c]) - b[i + c];
      sum += diff * diff;
      count++;
    }
  }
  if (sum <= 0) return 99;
  const double mse = sum / count;
  return 10.0 * std::log10(255.0 * 255.0 / mse);
}

void SaveBgra(const char* path, const std::vector<uint8_t>& bytes) {
  FILE* file = nullptr;
  fopen_s(&file, path, "wb");
  if (file == nullptr) return;
  fwrite(bytes.data(), 1, bytes.size(), file);
  fclose(file);
}

}  // namespace

int main() {
  const int width = 1600;
  const int height = 900;
  const int fps = 30;
  // Matches the app's quality-first target for the 高清 preset.
  const int bitrateKbps = width * height * fps * 28 / 100000;
  const int frameCount = 90;

  orbitlink::H264Encoder encoder(width, height, fps, bitrateKbps);
  printf("encoder ok=%d %s %dx%d\n", encoder.ok() ? 1 : 0,
         encoder.message().c_str(), encoder.width(), encoder.height());
  if (!encoder.ok()) return 1;

  orbitlink::H264Decoder decoder;
  printf("decoder ok=%d %s\n", decoder.ok() ? 1 : 0, decoder.message().c_str());
  if (!decoder.ok()) return 2;

  std::vector<uint8_t> source;
  std::vector<uint8_t> decoded(width * height * 4);
  std::vector<uint8_t> encoded;
  std::vector<uint8_t> firstSource;
  std::vector<uint8_t> firstDecoded;

  size_t totalBytes = 0;
  int keyframes = 0;
  int decodeErrors = 0;
  int decodedFrames = 0;
  int firstOutputFrame = -1;
  std::vector<uint8_t> stream;
  double encodeMs = 0;
  double decodeMs = 0;

  for (int frame = 0; frame < frameCount; frame++) {
    FillFrame(source, width, height, frame);
    if (frame == 0) firstSource = source;

    const int64_t timestamp = static_cast<int64_t>(frame) * 1000 / fps;
    const auto encodeStart = std::chrono::high_resolution_clock::now();
    bool keyframe = false;
    if (!encoder.Encode(source.data(), timestamp, encoded, &keyframe)) {
      printf("encode failed: %s\n", encoder.message().c_str());
      return 3;
    }
    const auto encodeEnd = std::chrono::high_resolution_clock::now();
    encodeMs +=
        std::chrono::duration<double, std::milli>(encodeEnd - encodeStart)
            .count();
    totalBytes += encoded.size();
    if (keyframe) keyframes++;
    stream.insert(stream.end(), encoded.begin(), encoded.end());
    if (!encoded.empty() && firstOutputFrame < 0) firstOutputFrame = frame;
    if (frame < 12 || (!encoded.empty() && firstOutputFrame == frame)) {
      printf("frame %d: encoded %zu bytes, key=%d\n", frame, encoded.size(),
             keyframe ? 1 : 0);
    }
    if (encoded.empty()) continue;

    const auto decodeStart = std::chrono::high_resolution_clock::now();
    int size = 0;
    int outWidth = 0;
    int outHeight = 0;
    const int status = decoder.Decode(
        encoded.data(), static_cast<int>(encoded.size()), width, height,
        timestamp, decoded.data(), static_cast<int>(decoded.size()), &size,
        &outWidth, &outHeight);
    const auto decodeEnd = std::chrono::high_resolution_clock::now();
    decodeMs +=
        std::chrono::duration<double, std::milli>(decodeEnd - decodeStart)
            .count();
    if (status == 1) {
      decodedFrames++;
      if (frame == 0) {
        firstDecoded.assign(decoded.begin(), decoded.begin() + size);
      }
    } else if (status < 0) {
      decodeErrors++;
      printf("decode[%d] error: %s\n", frame, decoder.message().c_str());
    } else if (frame < 6) {
      printf("decode[%d] status 0 (no frame)\n", frame);
    }
  }

  const double seconds = static_cast<double>(frameCount) / fps;
  printf(
      "first output at input frame %d, encode %.1f ms/frame, decode %.1f "
      "ms/frame, %d/%d keyframes, %.0f KB/frame, %.1f Mbps, decoded %d, "
      "errors %d\n",
      firstOutputFrame, encodeMs / frameCount, decodeMs / frameCount, keyframes,
      frameCount, totalBytes / static_cast<double>(frameCount) / 1024.0,
      totalBytes * 8 / seconds / 1e6, decodedFrames, decodeErrors);

  {
    FILE* file = nullptr;
    fopen_s(&file, "codec_stream.h264", "wb");
    if (file != nullptr) {
      fwrite(stream.data(), 1, stream.size(), file);
      fclose(file);
    }
  }

  if (!firstSource.empty() && !firstDecoded.empty()) {
    printf("round-trip PSNR %.2f dB\n", Psnr(firstSource, firstDecoded));
    SaveBgra("codec_source.bgra", firstSource);
    SaveBgra("codec_decoded.bgra", firstDecoded);
  }
  return decodedFrames > 0 && decodeErrors == 0 ? 0 : 4;
}
