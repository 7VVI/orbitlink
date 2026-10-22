// Media Foundation H.264 codec: CPU NV12 encoding and decoding.
//
// The Microsoft H.264 encoder MFT accepts system-memory NV12 and is fast
// enough for 1080p30 (a few ms per frame), which avoids the async D3D11
// device-manager path the Intel QSV MFT would require.

#define INITGUID
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#include <codecapi.h>
#include <icodecapi.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfobjects.h>
#include <mftransform.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include "h264_codec.h"

namespace orbitlink {
namespace {

// Declared locally: wmcodecdsp.h drags in strmif.h, whose CodecAPIEventData
// clashes with icodecapi.h.
const CLSID kEncoderClsid = {
    0x6ca50344, 0x051a, 0x4ded, {0x97, 0x79, 0xa4, 0x33, 0x05, 0x16, 0x5e, 0x35}};
const CLSID kDecoderClsid = {
    0x62ce7e72, 0x4c71, 0x4d20, {0xb1, 0x5d, 0x45, 0x28, 0x31, 0xa8, 0x7d, 0x9d}};

constexpr int64_t kTicksPerMs = 10000;

bool EnsureMediaFoundation() {
  static std::once_flag once;
  static HRESULT result = E_FAIL;
  std::call_once(once, []() { result = MFStartup(MF_VERSION); });
  return SUCCEEDED(result);
}

// Media Foundation and the WGC module share the capture worker thread, so the
// apartment stays initialized for the lifetime of the thread. Calling
// CoUninitialize here would break later COM use on the same thread.
bool EnsureApartment() {
  static thread_local bool initialized = []() {
    const HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    return SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE;
  }();
  return initialized;
}

template <typename T>
void Release(T*& value) {
  if (value != nullptr) {
    value->Release();
    value = nullptr;
  }
}

IMFTransform* AsTransform(void* value) {
  return static_cast<IMFTransform*>(value);
}

std::string HResultText(const char* what, HRESULT hr) {
  char buffer[128];
  std::snprintf(buffer, sizeof(buffer), "%s (0x%08lX)", what,
                static_cast<unsigned long>(hr));
  return buffer;
}

void SetCodecU32(IMFTransform* mft, const GUID& api, UINT32 value) {
  ICodecAPI* codec = nullptr;
  if (FAILED(mft->QueryInterface(IID_PPV_ARGS(&codec))) || codec == nullptr) {
    return;
  }
  VARIANT var;
  VariantInit(&var);
  var.vt = VT_UI4;
  var.ulVal = value;
  codec->SetValue(&api, &var);
  codec->Release();
}

void SetCodecBool(IMFTransform* mft, const GUID& api, bool value) {
  ICodecAPI* codec = nullptr;
  if (FAILED(mft->QueryInterface(IID_PPV_ARGS(&codec))) || codec == nullptr) {
    return;
  }
  VARIANT var;
  VariantInit(&var);
  var.vt = VT_BOOL;
  var.boolVal = value ? VARIANT_TRUE : VARIANT_FALSE;
  codec->SetValue(&api, &var);
  codec->Release();
}

bool HasIdr(const uint8_t* data, size_t size) {
  for (size_t i = 0; i + 4 <= size; i++) {
    if (data[i] == 0 && data[i + 1] == 0) {
      size_t offset = 0;
      if (data[i + 2] == 1) {
        offset = 3;
      } else if (i + 5 <= size && data[i + 2] == 0 && data[i + 3] == 1) {
        offset = 4;
      }
      if (offset != 0 && (data[i + offset] & 0x1F) == 5) return true;
    }
  }
  return false;
}

// Copies SPS (7) and PPS (8) NAL units out of an Annex-B keyframe so the
// decoder can advertise them as MF_MT_MPEG_SEQUENCE_HEADER.
void ExtractParameterSets(const uint8_t* data,
                          size_t size,
                          std::vector<uint8_t>& output) {
  output.clear();
  static const uint8_t kStart[4] = {0, 0, 0, 1};
  size_t i = 0;
  while (i + 3 < size) {
    size_t startLen = 0;
    if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1) {
      startLen = 3;
    } else if (i + 4 < size && data[i] == 0 && data[i + 1] == 0 &&
               data[i + 2] == 0 && data[i + 3] == 1) {
      startLen = 4;
    }
    if (startLen == 0) {
      i++;
      continue;
    }
    const size_t nalStart = i + startLen;
    size_t nalEnd = size;
    for (size_t j = nalStart; j + 3 <= size; j++) {
      if (data[j] == 0 && data[j + 1] == 0 &&
          (data[j + 2] == 1 ||
           (data[j + 2] == 0 && j + 4 <= size && data[j + 3] == 1))) {
        nalEnd = j;
        break;
      }
    }
    const uint8_t type = data[nalStart] & 0x1F;
    if (type == 7 || type == 8) {
      output.insert(output.end(), kStart, kStart + 4);
      output.insert(output.end(), data + nalStart, data + nalEnd);
    }
    i = nalEnd > i ? nalEnd : i + startLen;
  }
}

inline uint8_t Clip8(int value) {
  if (value < 0) return 0;
  if (value > 255) return 255;
  return static_cast<uint8_t>(value);
}

inline uint8_t ClipRange(int value, int low, int high) {
  if (value < low) return static_cast<uint8_t>(low);
  if (value > high) return static_cast<uint8_t>(high);
  return static_cast<uint8_t>(value);
}

// BGRA -> NV12, BT.709 limited range, both dimensions must be even.
void BgraToNv12(const uint8_t* bgra,
                int width,
                int height,
                std::vector<uint8_t>& output) {
  output.resize(static_cast<size_t>(width) * height * 3 / 2);
  uint8_t* yPlane = output.data();
  uint8_t* uvPlane = yPlane + static_cast<size_t>(width) * height;
  const size_t srcStride = static_cast<size_t>(width) * 4;
  for (int row = 0; row < height; row += 2) {
    const uint8_t* s0 = bgra + static_cast<size_t>(row) * srcStride;
    const uint8_t* s1 = s0 + srcStride;
    uint8_t* y0 = yPlane + static_cast<size_t>(row) * width;
    uint8_t* y1 = y0 + width;
    uint8_t* uv = uvPlane + static_cast<size_t>(row / 2) * width;
    for (int col = 0; col < width; col += 2) {
      const uint8_t* p0 = s0 + static_cast<size_t>(col) * 4;
      const uint8_t* p1 = p0 + 4;
      const uint8_t* p2 = s1 + static_cast<size_t>(col) * 4;
      const uint8_t* p3 = p2 + 4;
      const int b0 = p0[0], g0 = p0[1], r0 = p0[2];
      const int b1 = p1[0], g1 = p1[1], r1 = p1[2];
      const int b2 = p2[0], g2 = p2[1], r2 = p2[2];
      const int b3 = p3[0], g3 = p3[1], r3 = p3[2];

      y0[col + 0] = ClipRange(
          16 + ((47 * r0 + 157 * g0 + 16 * b0 + 128) >> 8), 16, 235);
      y0[col + 1] = ClipRange(
          16 + ((47 * r1 + 157 * g1 + 16 * b1 + 128) >> 8), 16, 235);
      y1[col + 0] = ClipRange(
          16 + ((47 * r2 + 157 * g2 + 16 * b2 + 128) >> 8), 16, 235);
      y1[col + 1] = ClipRange(
          16 + ((47 * r3 + 157 * g3 + 16 * b3 + 128) >> 8), 16, 235);

      const int rSum = r0 + r1 + r2 + r3;
      const int gSum = g0 + g1 + g2 + g3;
      const int bSum = b0 + b1 + b2 + b3;
      uv[col + 0] = ClipRange(
          128 + ((-26 * rSum - 86 * gSum + 112 * bSum + 512) >> 10), 16, 240);
      uv[col + 1] = ClipRange(
          128 + ((112 * rSum - 102 * gSum - 10 * bSum + 512) >> 10), 16, 240);
    }
  }
}

// NV12 -> BGRA, BT.709 limited range. |stride| is the Y row pitch and
// |sourceHeight| the padded allocation height (the UV plane follows it).
void Nv12ToBgra(const uint8_t* src,
                int width,
                int height,
                int sourceHeight,
                int stride,
                uint8_t* dst) {
  const int pitch = stride >= width ? stride : width;
  const uint8_t* yPlane = src;
  const uint8_t* uvPlane = src + static_cast<size_t>(pitch) * sourceHeight;
  for (int row = 0; row < height; row++) {
    const uint8_t* yRow = yPlane + static_cast<size_t>(row) * pitch;
    const uint8_t* uvRow = uvPlane + static_cast<size_t>(row / 2) * pitch;
    uint8_t* out = dst + static_cast<size_t>(row) * width * 4;
    for (int col = 0; col < width; col++) {
      const int y = (static_cast<int>(yRow[col]) - 16) * 298;
      const int u = static_cast<int>(uvRow[(col & ~1) + 0]) - 128;
      const int v = static_cast<int>(uvRow[(col & ~1) + 1]) - 128;
      const int r = (y + 459 * v + 128) >> 8;
      const int g = (y - 55 * u - 136 * v + 128) >> 8;
      const int b = (y + 541 * u + 128) >> 8;
      out[col * 4 + 0] = Clip8(b);
      out[col * 4 + 1] = Clip8(g);
      out[col * 4 + 2] = Clip8(r);
      out[col * 4 + 3] = 255;
    }
  }
}

}  // namespace

H264Encoder::H264Encoder(int width, int height, int fps, int bitrateKbps)
    : width_(std::max(16, width & ~1)),
      height_(std::max(16, height & ~1)),
      fps_(std::clamp(fps, 1, 60)),
      bitrateKbps_(std::clamp(bitrateKbps, 500, 40000)) {
  if (!EnsureApartment()) {
    message_ = "COM initialization failed";
    return;
  }
  if (!EnsureMediaFoundation()) {
    message_ = "Media Foundation startup failed";
    return;
  }
  ok_ = Configure();
}

H264Encoder::~H264Encoder() {
  if (mft_ != nullptr) {
    if (streaming_) {
      AsTransform(mft_)->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
      AsTransform(mft_)->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
    }
    if (outputSample_ != nullptr) {
      static_cast<IMFSample*>(outputSample_)->Release();
      outputSample_ = nullptr;
    }
    if (outputType_ != nullptr) {
      static_cast<IMFMediaType*>(outputType_)->Release();
      outputType_ = nullptr;
    }
    AsTransform(mft_)->Release();
    mft_ = nullptr;
  }
}

bool H264Encoder::Configure() {
  IMFTransform* mft = nullptr;
  HRESULT hr = CoCreateInstance(kEncoderClsid, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&mft));
  if (FAILED(hr) || mft == nullptr) {
    message_ = HResultText("H.264 encoder unavailable", hr);
    return false;
  }
  mft_ = mft;

  IMFAttributes* attributes = nullptr;
  if (SUCCEEDED(mft->GetAttributes(&attributes)) && attributes != nullptr) {
    UINT32 async = 0;
    attributes->GetUINT32(MF_TRANSFORM_ASYNC, &async);
    if (async) {
      const UINT32 unlock = 1;
      attributes->SetUINT32(MF_TRANSFORM_ASYNC_UNLOCK, unlock);
    }
    attributes->SetUINT32(MF_LOW_LATENCY, TRUE);
    attributes->Release();
  }

  IMFMediaType* output = nullptr;
  MFCreateMediaType(&output);
  output->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  output->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  output->SetUINT32(MF_MT_AVG_BITRATE, static_cast<UINT32>(bitrateKbps_) * 1000);
  output->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  output->SetUINT32(MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_Main);
  output->SetUINT32(MF_MT_VIDEO_PRIMARIES, MFVideoPrimaries_BT709);
  output->SetUINT32(MF_MT_TRANSFER_FUNCTION, MFVideoTransFunc_709);
  output->SetUINT32(MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT709);
  MFSetAttributeSize(output, MF_MT_FRAME_SIZE, width_, height_);
  MFSetAttributeRatio(output, MF_MT_FRAME_RATE, fps_, 1);

  hr = mft->SetOutputType(0, output, 0);
  if (FAILED(hr)) {
    // Some encoders reject explicit color metadata; retry without it.
    output->DeleteItem(MF_MT_VIDEO_PRIMARIES);
    output->DeleteItem(MF_MT_TRANSFER_FUNCTION);
    output->DeleteItem(MF_MT_YUV_MATRIX);
    hr = mft->SetOutputType(0, output, 0);
  }
  if (FAILED(hr)) {
    message_ = HResultText("SetOutputType failed", hr);
    output->Release();
    return false;
  }
  outputType_ = output;

  IMFMediaType* input = nullptr;
  MFCreateMediaType(&input);
  input->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  input->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
  input->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  MFSetAttributeSize(input, MF_MT_FRAME_SIZE, width_, height_);
  MFSetAttributeRatio(input, MF_MT_FRAME_RATE, fps_, 1);
  hr = mft->SetInputType(0, input, 0);
  input->Release();
  if (FAILED(hr)) {
    message_ = HResultText("SetInputType failed", hr);
    return false;
  }

  SetCodecU32(mft, CODECAPI_AVEncCommonRateControlMode,
              eAVEncCommonRateControlMode_CBR);
  SetCodecU32(mft, CODECAPI_AVEncCommonMeanBitRate,
              static_cast<UINT32>(bitrateKbps_) * 1000);
  SetCodecU32(mft, CODECAPI_AVEncCommonLowLatency, 1);
  SetCodecU32(mft, CODECAPI_AVEncMPVGOPSize, static_cast<UINT32>(fps_ * 2));
  SetCodecU32(mft, CODECAPI_AVEncMPVDefaultBPictureCount, 0);
  SetCodecU32(mft, CODECAPI_AVEncH264CABACEnable, 1);

  MFT_OUTPUT_STREAM_INFO info{};
  if (SUCCEEDED(mft->GetOutputStreamInfo(0, &info))) {
    outputBufferSize_ = std::max<UINT32>(info.cbSize, 512 * 1024);
  } else {
    outputBufferSize_ = 4 * 1024 * 1024;
  }

  mft->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
  mft->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
  mft->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
  streaming_ = true;
  return true;
}

void H264Encoder::RequestKeyframe() {
  if (mft_ == nullptr) return;
  SetCodecU32(AsTransform(mft_), CODECAPI_AVEncVideoForceKeyFrame, 1);
}

bool H264Encoder::EnsureOutputSample(uint32_t size) {
  if (outputSample_ != nullptr && outputBufferSize_ >= size) return true;
  IMFTransform* mft = AsTransform(mft_);
  if (mft == nullptr) return false;
  if (outputSample_ != nullptr) {
    static_cast<IMFSample*>(outputSample_)->Release();
    outputSample_ = nullptr;
  }
  IMFSample* sample = nullptr;
  IMFMediaBuffer* buffer = nullptr;
  if (FAILED(MFCreateSample(&sample))) return false;
  if (FAILED(MFCreateMemoryBuffer(std::max<uint32_t>(size, 256 * 1024),
                                  &buffer))) {
    sample->Release();
    return false;
  }
  sample->AddBuffer(buffer);
  buffer->Release();
  outputSample_ = sample;
  outputBufferSize_ = std::max<uint32_t>(size, 256 * 1024);
  return true;
}

bool H264Encoder::Drain(std::vector<uint8_t>& output, bool* keyframe) {
  IMFTransform* mft = AsTransform(mft_);
  if (mft == nullptr) return false;
  MFT_OUTPUT_STREAM_INFO info{};
  if (FAILED(mft->GetOutputStreamInfo(0, &info))) {
    message_ = "GetOutputStreamInfo failed";
    return false;
  }
  const bool providesSamples =
      (info.dwFlags & MFT_OUTPUT_STREAM_PROVIDES_SAMPLES) != 0;

  for (int round = 0; round < 4; round++) {
    if (!providesSamples && !EnsureOutputSample(info.cbSize)) {
      message_ = "output sample allocation failed";
      return false;
    }
    MFT_OUTPUT_DATA_BUFFER buffer{};
    if (!providesSamples) buffer.pSample =
        *reinterpret_cast<IMFSample**>(&outputSample_);
    DWORD status = 0;
    const HRESULT hr = mft->ProcessOutput(0, 1, &buffer, &status);
    if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) {
      if (buffer.pEvents != nullptr) buffer.pEvents->Release();
      return true;
    }
    if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
      if (buffer.pEvents != nullptr) buffer.pEvents->Release();
      continue;
    }
    if (FAILED(hr)) {
      if (buffer.pEvents != nullptr) buffer.pEvents->Release();
      message_ = HResultText("ProcessOutput failed", hr);
      return false;
    }
    IMFMediaBuffer* contiguous = nullptr;
    if (SUCCEEDED(buffer.pSample->ConvertToContiguousBuffer(&contiguous)) &&
        contiguous != nullptr) {
      BYTE* data = nullptr;
      DWORD length = 0;
      if (SUCCEEDED(contiguous->Lock(&data, nullptr, &length)) &&
          data != nullptr) {
        if (length > 0) output.insert(output.end(), data, data + length);
        contiguous->Unlock();
      }
      contiguous->Release();
    }
    if (providesSamples && buffer.pSample != nullptr) {
      buffer.pSample->Release();
    }
    if (buffer.pEvents != nullptr) buffer.pEvents->Release();
  }
  if (HasIdr(output.data(), output.size())) *keyframe = true;
  return true;
}

bool H264Encoder::Encode(const uint8_t* bgra,
                         int64_t timestampMs,
                         std::vector<uint8_t>& output,
                         bool* keyframe) {
  output.clear();
  if (keyframe != nullptr) *keyframe = false;
  if (!ok_ || mft_ == nullptr || bgra == nullptr) return false;
  IMFTransform* mft = AsTransform(mft_);

  BgraToNv12(bgra, width_, height_, nv12_);

  IMFSample* sample = nullptr;
  IMFMediaBuffer* buffer = nullptr;
  if (FAILED(MFCreateSample(&sample))) return false;
  if (FAILED(MFCreateMemoryBuffer(static_cast<DWORD>(nv12_.size()), &buffer))) {
    sample->Release();
    return false;
  }
  BYTE* target = nullptr;
  if (FAILED(buffer->Lock(&target, nullptr, nullptr)) || target == nullptr) {
    buffer->Release();
    sample->Release();
    return false;
  }
  std::memcpy(target, nv12_.data(), nv12_.size());
  buffer->Unlock();
  buffer->SetCurrentLength(static_cast<DWORD>(nv12_.size()));
  sample->AddBuffer(buffer);
  buffer->Release();
  sample->SetSampleTime(timestampMs * kTicksPerMs);
  sample->SetSampleDuration(10000000LL / fps_);

  HRESULT hr = mft->ProcessInput(0, sample, 0);
  if (hr == MF_E_NOTACCEPTING) {
    if (!Drain(output, keyframe)) {
      sample->Release();
      return false;
    }
    hr = mft->ProcessInput(0, sample, 0);
  }
  sample->Release();
  if (FAILED(hr)) {
    message_ = HResultText("ProcessInput failed", hr);
    return false;
  }
  if (!Drain(output, keyframe)) return false;
  if (keyframe != nullptr && !*keyframe &&
      HasIdr(output.data(), output.size())) {
    *keyframe = true;
  }
  return true;
}

H264Decoder::H264Decoder() {
  if (!EnsureApartment()) {
    message_ = "COM initialization failed";
    return;
  }
  if (!EnsureMediaFoundation()) {
    message_ = "Media Foundation startup failed";
    return;
  }
  ok_ = CreateTransform();
}

H264Decoder::~H264Decoder() { ReleaseTransform(); }

bool H264Decoder::CreateTransform() {
  ReleaseTransform();
  IMFTransform* mft = nullptr;
  HRESULT hr = CoCreateInstance(kDecoderClsid, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&mft));
  if (FAILED(hr) || mft == nullptr) {
    message_ = HResultText("H.264 decoder unavailable", hr);
    ok_ = false;
    return false;
  }
  mft_ = mft;
  IMFAttributes* attributes = nullptr;
  if (SUCCEEDED(mft->GetAttributes(&attributes)) && attributes != nullptr) {
    UINT32 async = 0;
    attributes->GetUINT32(MF_TRANSFORM_ASYNC, &async);
    if (async) {
      const UINT32 unlock = 1;
      attributes->SetUINT32(MF_TRANSFORM_ASYNC_UNLOCK, unlock);
    }
    attributes->SetUINT32(MF_LOW_LATENCY, TRUE);
    attributes->Release();
  }
  SetCodecBool(mft, CODECAPI_AVLowLatencyMode, true);
  streaming_ = false;
  inputConfigured_ = false;
  outputConfigured_ = false;
  ok_ = true;
  return true;
}

void H264Decoder::ReleaseTransform() {
  if (mft_ != nullptr) {
    if (streaming_) {
      AsTransform(mft_)->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
      AsTransform(mft_)->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
    }
    Release(*reinterpret_cast<IMFMediaType**>(&outputType_));
    AsTransform(mft_)->Release();
    mft_ = nullptr;
  }
  streaming_ = false;
  inputConfigured_ = false;
  outputConfigured_ = false;
  nextTimestamp_ = 0;
}

void H264Decoder::Reset() {
  const bool active = mft_ != nullptr;
  ReleaseTransform();
  if (active) {
    ok_ = CreateTransform();
  }
}

bool H264Decoder::ConfigureInput(const uint8_t* data,
                                 int size,
                                 int width,
                                 int height) {
  IMFTransform* mft = AsTransform(mft_);
  if (mft == nullptr) return false;
  IMFMediaType* type = nullptr;
  MFCreateMediaType(&type);
  type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  MFSetAttributeSize(type, MF_MT_FRAME_SIZE, std::max(16, width),
                     std::max(16, height));
  MFSetAttributeRatio(type, MF_MT_FRAME_RATE, 30, 1);

  std::vector<uint8_t> parameters;
  ExtractParameterSets(data, static_cast<size_t>(size), parameters);
  if (!parameters.empty()) {
    type->SetBlob(MF_MT_MPEG_SEQUENCE_HEADER, parameters.data(),
                  static_cast<UINT32>(parameters.size()));
  }
  const HRESULT hr = mft->SetInputType(0, type, 0);
  type->Release();
  if (FAILED(hr)) {
    message_ = HResultText("decoder SetInputType failed", hr);
    return false;
  }
  width_ = width;
  height_ = height;
  inputWidth_ = width;
  inputHeight_ = height;
  nextTimestamp_ = 0;
  inputConfigured_ = true;
  return true;
}

bool H264Decoder::ConfigureOutput() {
  IMFTransform* mft = AsTransform(mft_);
  if (mft == nullptr) return false;
  IMFMediaType* chosen = nullptr;
  for (DWORD index = 0; index < 12; index++) {
    IMFMediaType* type = nullptr;
    if (FAILED(mft->GetOutputAvailableType(0, index, &type)) ||
        type == nullptr) {
      break;
    }
    GUID subtype{};
    type->GetGUID(MF_MT_SUBTYPE, &subtype);
    if (subtype == MFVideoFormat_NV12) {
      chosen = type;
      break;
    }
    type->Release();
  }
  if (chosen == nullptr) {
    message_ = "decoder has no NV12 output";
    return false;
  }
  const HRESULT hr = mft->SetOutputType(0, chosen, 0);
  if (FAILED(hr)) {
    chosen->Release();
    message_ = HResultText("decoder SetOutputType failed", hr);
    return false;
  }
  UINT32 width = 0, height = 0;
  MFGetAttributeSize(chosen, MF_MT_FRAME_SIZE, &width, &height);
  UINT32 stride = 0;
  if (FAILED(chosen->GetUINT32(MF_MT_DEFAULT_STRIDE, &stride)) ||
      stride == 0) {
    stride = width;
  }
  width_ = static_cast<int>(width);
  height_ = static_cast<int>(height);
  stride_ = static_cast<int>(stride);
  outputType_ = chosen;
  outputConfigured_ = true;
  return true;
}

int H264Decoder::Drain(uint8_t* dst,
                       int capacity,
                       int* outSize,
                       int* outWidth,
                       int* outHeight,
                       bool* produced) {
  *produced = false;
  IMFTransform* mft = AsTransform(mft_);
  if (mft == nullptr) return -1;
  MFT_OUTPUT_STREAM_INFO info{};
  if (FAILED(mft->GetOutputStreamInfo(0, &info))) {
    message_ = "decoder GetOutputStreamInfo failed";
    return -1;
  }
  const bool providesSamples =
      (info.dwFlags & MFT_OUTPUT_STREAM_PROVIDES_SAMPLES) != 0;

  for (int round = 0; round < 6; round++) {
    MFT_OUTPUT_DATA_BUFFER buffer{};
    IMFSample* ownSample = nullptr;
    if (!providesSamples) {
      IMFMediaBuffer* memory = nullptr;
      if (FAILED(MFCreateSample(&ownSample)) ||
          FAILED(MFCreateMemoryBuffer(
              std::max<UINT32>(info.cbSize, 256 * 1024), &memory))) {
        if (ownSample) ownSample->Release();
        return -1;
      }
      ownSample->AddBuffer(memory);
      memory->Release();
      buffer.pSample = ownSample;
    }
    DWORD status = 0;
    const HRESULT hr = mft->ProcessOutput(0, 1, &buffer, &status);
    if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) {
      if (ownSample) ownSample->Release();
      if (buffer.pEvents != nullptr) buffer.pEvents->Release();
      return 0;
    }
    if (hr == MF_E_TRANSFORM_STREAM_CHANGE ||
        hr == MF_E_TRANSFORM_TYPE_NOT_SET) {
      if (ownSample) ownSample->Release();
      if (buffer.pEvents != nullptr) buffer.pEvents->Release();
      if (!ConfigureOutput()) return -1;
      continue;
    }
    if (FAILED(hr)) {
      if (ownSample) ownSample->Release();
      if (buffer.pEvents != nullptr) buffer.pEvents->Release();
      message_ = HResultText("decoder ProcessOutput failed", hr);
      return -1;
    }
    if (!outputConfigured_ && !ConfigureOutput()) {
      if (ownSample) ownSample->Release();
      if (buffer.pEvents != nullptr) buffer.pEvents->Release();
      return -1;
    }
    // The decoder pads the NV12 output to a macroblock multiple; show only
    // the frame size the host actually captured.
    const int displayWidth =
        inputWidth_ > 0 ? std::min(width_, inputWidth_) : width_;
    const int displayHeight =
        inputHeight_ > 0 ? std::min(height_, inputHeight_) : height_;
    const int required = displayWidth * displayHeight * 4;
    if (required <= 0) {
      if (ownSample) ownSample->Release();
      if (buffer.pEvents != nullptr) buffer.pEvents->Release();
      return -1;
    }
    if (required > capacity) {
      *outSize = required;
      *outWidth = displayWidth;
      *outHeight = displayHeight;
      if (ownSample) ownSample->Release();
      else if (buffer.pSample) buffer.pSample->Release();
      if (buffer.pEvents != nullptr) buffer.pEvents->Release();
      return 2;
    }
    IMFMediaBuffer* contiguous = nullptr;
    if (FAILED(buffer.pSample->ConvertToContiguousBuffer(&contiguous)) ||
        contiguous == nullptr) {
      if (ownSample) ownSample->Release();
      if (buffer.pEvents != nullptr) buffer.pEvents->Release();
      return -1;
    }
    BYTE* data = nullptr;
    DWORD length = 0;
    if (SUCCEEDED(contiguous->Lock(&data, nullptr, &length)) &&
        data != nullptr) {
      Nv12ToBgra(data, displayWidth, displayHeight, height_, stride_, dst);
      contiguous->Unlock();
    }
    contiguous->Release();
    if (providesSamples && buffer.pSample != nullptr) buffer.pSample->Release();
    if (ownSample) ownSample->Release();
    if (buffer.pEvents != nullptr) buffer.pEvents->Release();
    *outSize = required;
    *outWidth = displayWidth;
    *outHeight = displayHeight;
    *produced = true;
    return 1;
  }
  return 0;
}

int H264Decoder::Decode(const uint8_t* data,
                        int size,
                        int width,
                        int height,
                        int64_t timestampMs,
                        uint8_t* dst,
                        int capacity,
                        int* outSize,
                        int* outWidth,
                        int* outHeight) {
  *outSize = 0;
  *outWidth = 0;
  *outHeight = 0;
  if (!ok_ || mft_ == nullptr || data == nullptr || size <= 0) return -1;
  IMFTransform* mft = AsTransform(mft_);
  if (inputConfigured_ &&
      (width != inputWidth_ || height != inputHeight_)) {
    Reset();
    mft = AsTransform(mft_);
    if (mft == nullptr) return -1;
  }
  if (!inputConfigured_) {
    if (!ConfigureInput(data, size, width, height)) return -1;
    // Advertise the output format right away: without it the decoder buffers
    // input instead of emitting samples.
    ConfigureOutput();
  }
  if (!streaming_) {
    mft->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
    mft->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
    mft->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
    streaming_ = true;
  }

  IMFSample* sample = nullptr;
  IMFMediaBuffer* buffer = nullptr;
  if (FAILED(MFCreateSample(&sample))) return -1;
  if (FAILED(MFCreateMemoryBuffer(static_cast<DWORD>(size), &buffer))) {
    sample->Release();
    return -1;
  }
  BYTE* target = nullptr;
  if (FAILED(buffer->Lock(&target, nullptr, nullptr)) || target == nullptr) {
    buffer->Release();
    sample->Release();
    return -1;
  }
  std::memcpy(target, data, static_cast<size_t>(size));
  buffer->Unlock();
  buffer->SetCurrentLength(static_cast<DWORD>(size));
  sample->AddBuffer(buffer);
  buffer->Release();
  sample->SetSampleTime(timestampMs * kTicksPerMs);
  sample->SetSampleDuration(10000000LL / 30);

  HRESULT hr = mft->ProcessInput(0, sample, 0);
  if (hr == MF_E_NOTACCEPTING) {
    int producedSize = 0;
    int producedWidth = 0;
    int producedHeight = 0;
    bool produced = false;
    Drain(dst, capacity, &producedSize, &producedWidth, &producedHeight,
          &produced);
    hr = mft->ProcessInput(0, sample, 0);
  }
  sample->Release();
  if (FAILED(hr)) {
    message_ = HResultText("decoder ProcessInput failed", hr);
    return -1;
  }

  bool produced = false;
  const int result =
      Drain(dst, capacity, outSize, outWidth, outHeight, &produced);
  if (result < 0) return result;
  return (result == 1 && produced) ? 1 : result;
}

}  // namespace orbitlink

namespace {
thread_local std::string g_lastCodecError;

void SetError(const std::string& message) { g_lastCodecError = message; }
}  // namespace

extern "C" {

__declspec(dllexport) void* orbit_h264_encoder_create(int width,
                                                      int height,
                                                      int fps,
                                                      int bitrate_kbps) {
  auto* encoder =
      new (std::nothrow) orbitlink::H264Encoder(width, height, fps, bitrate_kbps);
  if (encoder == nullptr) {
    SetError("out of memory");
    return nullptr;
  }
  if (!encoder->ok()) {
    SetError(encoder->message());
    delete encoder;
    return nullptr;
  }
  return encoder;
}

__declspec(dllexport) int orbit_h264_encoder_width(void* handle) {
  if (handle == nullptr) return 0;
  return static_cast<orbitlink::H264Encoder*>(handle)->width();
}

__declspec(dllexport) int orbit_h264_encoder_height(void* handle) {
  if (handle == nullptr) return 0;
  return static_cast<orbitlink::H264Encoder*>(handle)->height();
}

__declspec(dllexport) int orbit_h264_encode(void* handle,
                                            const uint8_t* bgra,
                                            int width,
                                            int height,
                                            long long timestamp_ms,
                                            uint8_t* dst,
                                            int capacity,
                                            int* out_size,
                                            int* out_keyframe) {
  if (out_size != nullptr) *out_size = 0;
  if (out_keyframe != nullptr) *out_keyframe = 0;
  if (handle == nullptr) return -1;
  auto* encoder = static_cast<orbitlink::H264Encoder*>(handle);
  if (width != encoder->width() || height != encoder->height()) {
    SetError("frame size does not match encoder");
    return -1;
  }
  std::vector<uint8_t> output;
  bool keyframe = false;
  if (!encoder->Encode(bgra, timestamp_ms, output, &keyframe)) {
    SetError(encoder->message());
    return -1;
  }
  if (output.empty()) return 0;
  if (static_cast<int>(output.size()) > capacity) {
    SetError("h264 output buffer too small");
    return -1;
  }
  std::memcpy(dst, output.data(), output.size());
  if (out_size != nullptr) *out_size = static_cast<int>(output.size());
  if (out_keyframe != nullptr) *out_keyframe = keyframe ? 1 : 0;
  return 1;
}

__declspec(dllexport) void orbit_h264_encoder_request_keyframe(void* handle) {
  if (handle == nullptr) return;
  static_cast<orbitlink::H264Encoder*>(handle)->RequestKeyframe();
}

__declspec(dllexport) void orbit_h264_encoder_destroy(void* handle) {
  delete static_cast<orbitlink::H264Encoder*>(handle);
}

__declspec(dllexport) void* orbit_h264_decoder_create(void) {
  auto* decoder = new (std::nothrow) orbitlink::H264Decoder();
  if (decoder == nullptr) {
    SetError("out of memory");
    return nullptr;
  }
  if (!decoder->ok()) {
    SetError(decoder->message());
    delete decoder;
    return nullptr;
  }
  return decoder;
}

__declspec(dllexport) int orbit_h264_decode(void* handle,
                                            const uint8_t* data,
                                            int size,
                                            int width,
                                            int height,
                                            long long timestamp_ms,
                                            uint8_t* dst,
                                            int capacity,
                                            int* out_size,
                                            int* out_width,
                                            int* out_height) {
  if (out_size != nullptr) *out_size = 0;
  if (out_width != nullptr) *out_width = 0;
  if (out_height != nullptr) *out_height = 0;
  if (handle == nullptr) return -1;
  auto* decoder = static_cast<orbitlink::H264Decoder*>(handle);
  const int result = decoder->Decode(data, size, width, height, timestamp_ms,
                                     dst, capacity, out_size, out_width,
                                     out_height);
  if (result < 0) SetError(decoder->message());
  return result;
}

__declspec(dllexport) void orbit_h264_decoder_reset(void* handle) {
  if (handle == nullptr) return;
  static_cast<orbitlink::H264Decoder*>(handle)->Reset();
}

__declspec(dllexport) void orbit_h264_decoder_destroy(void* handle) {
  delete static_cast<orbitlink::H264Decoder*>(handle);
}

__declspec(dllexport) const char* orbit_h264_last_error(void) {
  return g_lastCodecError.c_str();
}

}  // extern "C"
