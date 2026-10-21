// OrbitLink native media module.
//
// Windows Graphics Capture (WGC) grabs the primary monitor as a D3D11
// texture, which removes the ~25 ms GDI BitBlt bottleneck of the legacy
// capture path. Frames are encoded with libjpeg-turbo (4:4:4, no chroma
// subsampling) so text stays sharp on the controller side.
//
// The module never calls back into Dart: encoded frames are stored in a
// single-slot buffer that the Dart isolate polls.

#include "orbitlink_encoder.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <d3d11.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

#include <windows.graphics.capture.h>
#include <windows.graphics.directx.h>
#include <windows.graphics.directx.direct3d11.h>

#include <cstring>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

namespace wgc = ABI::Windows::Graphics::Capture;
namespace wgxd3d = ABI::Windows::Graphics::DirectX::Direct3D11;
namespace wgdx = ABI::Windows::Graphics::DirectX;
namespace wgx = ABI::Windows::Graphics;

// Interop interfaces are declared locally to avoid pulling in SDK headers
// that clash with the WinRT ABI headers.
struct __declspec(uuid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356"))
    IGraphicsCaptureItemInterop : public IUnknown {
  virtual HRESULT STDMETHODCALLTYPE CreateForWindow(HWND, REFIID,
                                                    void**) = 0;
  virtual HRESULT STDMETHODCALLTYPE CreateForMonitor(HMONITOR, REFIID,
                                                      void**) = 0;
};

struct __declspec(uuid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1"))
    IDirect3DDxgiInterfaceAccess : public IUnknown {
  virtual HRESULT STDMETHODCALLTYPE GetInterface(REFIID, void**) = 0;
};

extern "C" HRESULT WINAPI CreateDirect3D11DeviceFromDXGIDevice(
    IDXGIDevice* device,
    IInspectable** graphicsDevice);

// The Windows Runtime headers shipped with the SDK declare a different
// RoGetActivationFactory overload, so the classic one is resolved at runtime.
using RoGetActivationFactoryFn = HRESULT(WINAPI*)(REFIID, void**);

RoGetActivationFactoryFn resolveRoGetActivationFactory() {
  static RoGetActivationFactoryFn fn = []() -> RoGetActivationFactoryFn {
    HMODULE combase = GetModuleHandleW(L"combase.dll");
    if (combase == nullptr) return nullptr;
    return reinterpret_cast<RoGetActivationFactoryFn>(
        GetProcAddress(combase, "RoGetActivationFactory"));
  }();
  return fn;
}

// IActivationFactory (classic layout) with GetInterface as the fourth method.
struct __declspec(uuid("00000035-0000-0000-C000-000000000046"))
    IClassicActivationFactory : public IUnknown {
  virtual HRESULT STDMETHODCALLTYPE GetInterface(REFIID, void**) = 0;
};

// ---------------------------------------------------------------------------
// libjpeg-turbo, loaded at runtime so the module stays self contained.
// ---------------------------------------------------------------------------
class TurboJpeg {
 public:
  bool load() {
    if (loaded_) return ok_;
    loaded_ = true;
    HMODULE module = LoadLibraryExW(
        L"turbojpeg.dll", nullptr,
        LOAD_LIBRARY_SEARCH_DEFAULT_DIRS |
            LOAD_LIBRARY_SEARCH_APPLICATION_DIR);
    if (module == nullptr) module = LoadLibraryW(L"turbojpeg.dll");
    if (module == nullptr) {
      message_ = "turbojpeg.dll not found";
      return false;
    }
    init_ =
        reinterpret_cast<InitFn>(GetProcAddress(module, "tjInitCompress"));
    compress_ =
        reinterpret_cast<CompressFn>(GetProcAddress(module, "tjCompress2"));
    bufSize_ =
        reinterpret_cast<BufSizeFn>(GetProcAddress(module, "tjBufSize"));
    alloc_ = reinterpret_cast<AllocFn>(GetProcAddress(module, "tjAlloc"));
    free_ = reinterpret_cast<FreeFn>(GetProcAddress(module, "tjFree"));
    destroy_ =
        reinterpret_cast<DestroyFn>(GetProcAddress(module, "tjDestroy"));
    ok_ = init_ && compress_ && bufSize_ && alloc_ && free_ && destroy_;
    if (!ok_) message_ = "turbojpeg.dll is missing symbols";
    return ok_;
  }

  bool compress(const uint8_t* bgra,
                int width,
                int height,
                int quality,
                std::vector<uint8_t>& out) {
    if (!load() || handle_ == nullptr) return false;
    if (capacity_ == 0) {
      capacity_ = bufSize_(width, height, 0 /* 4:4:4 */);
      if (capacity_ == 0) return false;
      buffer_ = reinterpret_cast<uint8_t*>(alloc_(capacity_));
      if (buffer_ == nullptr) {
        capacity_ = 0;
        return false;
      }
    }
    outPtr_ = buffer_;
    size_ = capacity_;
    const int flags = 2048 /* TJFLAG_FASTDCT */ | 1024 /* TJFLAG_NOREALLOC */;
    const int subsampling = quality >= 80 ? 0 : (quality >= 60 ? 1 : 2);
    if (compress_(handle_, const_cast<uint8_t*>(bgra), width, width * 4, height,
                  8 /* TJPF_BGRA */, &outPtr_, &size_, subsampling, quality,
                  flags) != 0) {
      return false;
    }
    out.assign(outPtr_, outPtr_ + size_);
    return true;
  }

  const std::string& message() const { return message_; }

  ~TurboJpeg() {
    if (handle_ != nullptr) destroy_(handle_);
    if (buffer_ != nullptr) free_(buffer_);
  }

 private:
  using InitFn = void* (*)();
  using CompressFn = int (*)(void*, const uint8_t*, int, int, int, int,
                             uint8_t**, unsigned long*, int, int, int);
  using BufSizeFn = unsigned long (*)(int, int, int);
  using AllocFn = uint8_t* (*)(int);
  using FreeFn = void (*)(uint8_t*);
  using DestroyFn = int (*)(void*);

  bool loaded_ = false;
  bool ok_ = false;
  std::string message_;
  void* handle_ = nullptr;
  InitFn init_ = nullptr;
  CompressFn compress_ = nullptr;
  BufSizeFn bufSize_ = nullptr;
  AllocFn alloc_ = nullptr;
  FreeFn free_ = nullptr;
  DestroyFn destroy_ = nullptr;
  uint8_t* buffer_ = nullptr;
  unsigned long capacity_ = 0;
  uint8_t* outPtr_ = nullptr;
  unsigned long size_ = 0;
};

// ---------------------------------------------------------------------------
// Windows Graphics Capture session.
// ---------------------------------------------------------------------------
class WgcSession;

// Defined after WgcSession, which needs the handler type.
void orbitInvokeFrameHandler(WgcSession* owner);

struct FrameHandler;

struct FrameHandlerVtbl {
  HRESULT(STDMETHODCALLTYPE* QueryInterface)(FrameHandler*, REFIID, void**);
  ULONG(STDMETHODCALLTYPE* AddRef)(FrameHandler*);
  ULONG(STDMETHODCALLTYPE* Release)(FrameHandler*);
  HRESULT(STDMETHODCALLTYPE* Invoke)(FrameHandler*, void*, IInspectable*);
};

struct FrameHandler {
  const FrameHandlerVtbl* lpVtbl;
  volatile LONG ref;
  WgcSession* owner;
};

HRESULT STDMETHODCALLTYPE HandlerQueryInterface(FrameHandler* self,
                                                REFIID riid,
                                                void** out) {
  if (out == nullptr) return E_POINTER;
  if (riid == __uuidof(IUnknown)) {
    *out = reinterpret_cast<IUnknown*>(self);
    self->lpVtbl->AddRef(self);
    return S_OK;
  }
  *out = nullptr;
  return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE HandlerAddRef(FrameHandler* self) {
  return static_cast<ULONG>(InterlockedIncrement(&self->ref));
}

ULONG STDMETHODCALLTYPE HandlerRelease(FrameHandler* self) {
  return static_cast<ULONG>(InterlockedDecrement(&self->ref));
}

HRESULT STDMETHODCALLTYPE HandlerInvoke(FrameHandler* self,
                                        void* sender,
                                        IInspectable* args) {
  if (self->owner != nullptr) orbitInvokeFrameHandler(self->owner);
  return S_OK;
}

const FrameHandlerVtbl kHandlerVtbl = {HandlerQueryInterface, HandlerAddRef,
                                       HandlerRelease, HandlerInvoke};

class WgcSession {
 public:
  bool start(int width, int height, int fps) {
    width_ = width;
    height_ = height;
    fps_ = fps > 0 ? fps : 30;
    D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1,
                                  D3D_FEATURE_LEVEL_11_0,
                                  D3D_FEATURE_LEVEL_10_1};
    D3D_FEATURE_LEVEL achieved{};
    ID3D11Device* rawDevice = nullptr;
    ID3D11DeviceContext* rawContext = nullptr;
    HRESULT hr = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, levels, ARRAYSIZE(levels),
        D3D11_SDK_VERSION, &rawDevice, &achieved, &rawContext);
    device_.Attach(rawDevice);
    context_.Attach(rawContext);
    if (FAILED(hr)) {
      message_ = "D3D11CreateDevice failed";
      return false;
    }
    IDXGIDevice* rawDxgi = nullptr;
    const HRESULT asResult =
        device_.Get()->QueryInterface(IID_PPV_ARGS(&rawDxgi));
    if (FAILED(asResult) || rawDxgi == nullptr) {
      message_ = "IDXGIDevice query failed";
      return false;
    }
    ComPtr<IDXGIDevice> dxgiDevice;
    dxgiDevice.Attach(rawDxgi);
    ComPtr<wgxd3d::IDirect3DDevice> winrtDevice;
    {
      IInspectable* rawInspectable = nullptr;
      hr = CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.Get(),
                                                &rawInspectable);
      if (SUCCEEDED(hr) && rawInspectable != nullptr) {
        wgxd3d::IDirect3DDevice* rawWinrtDevice = nullptr;
        hr = rawInspectable->QueryInterface(IID_PPV_ARGS(&rawWinrtDevice));
        rawInspectable->Release();
        winrtDevice.Attach(rawWinrtDevice);
      }
    }
    if (FAILED(hr)) {
      message_ = "CreateDirect3D11DeviceFromDXGIDevice failed";
      return false;
    }
    HMONITOR monitor = PrimaryMonitor();
    if (monitor == nullptr) {
      message_ = "no primary monitor";
      return false;
    }
    ComPtr<IGraphicsCaptureItemInterop> interop;
    IGraphicsCaptureItemInterop* rawInterop = nullptr;
    hr = CoCreateInstance(__uuidof(IGraphicsCaptureItemInterop), nullptr,
                           CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&rawInterop));
    interop.Attach(rawInterop);
    if (FAILED(hr)) {
      const auto activate = resolveRoGetActivationFactory();
      if (activate != nullptr) {
        IGraphicsCaptureItemInterop* raw = nullptr;
        hr = activate(__uuidof(IGraphicsCaptureItemInterop),
                      reinterpret_cast<void**>(&raw));
        if (SUCCEEDED(hr)) interop.Attach(raw);
      } else {
      }
    }
    if (FAILED(hr)) {
      message_ = "IGraphicsCaptureItemInterop unavailable";
      return false;
    }
    ComPtr<wgc::IGraphicsCaptureItem> item;
    hr = interop->CreateForMonitor(
        monitor, __uuidof(wgc::IGraphicsCaptureItem),
        reinterpret_cast<void**>(item.GetAddressOf()));
    if (FAILED(hr)) {
      message_ = "CreateForMonitor failed";
      return false;
    }
    ComPtr<wgc::IDirect3D11CaptureFramePoolStatics2> statics;
    const auto activate = resolveRoGetActivationFactory();
    if (activate != nullptr) {
      hr = activate(__uuidof(wgc::IDirect3D11CaptureFramePoolStatics2),
                    reinterpret_cast<void**>(statics.GetAddressOf()));
    } else {
      hr = E_FAIL;
    }
    if (FAILED(hr)) {
      message_ = "frame pool activation failed";
      return false;
    }
    wgx::SizeInt32 size;
    size.Width = static_cast<int32_t>(width);
    size.Height = static_cast<int32_t>(height);
    ComPtr<wgc::IDirect3D11CaptureFramePool> pool;
    hr = statics->CreateFreeThreaded(
        winrtDevice.Get(),
        wgdx::DirectXPixelFormat::DirectXPixelFormat_B8G8R8A8UIntNormalized, 2,
        size, &pool);
    if (FAILED(hr)) {
      message_ = "CreateFreeThreaded failed";
      return false;
    }
    ComPtr<wgc::IGraphicsCaptureSession> session;
    hr = pool->CreateCaptureSession(item.Get(), &session);
    if (FAILED(hr)) {
      message_ = "CreateCaptureSession failed";
      return false;
    }
    handler_ = std::make_unique<FrameHandler>();
    handler_->lpVtbl = &kHandlerVtbl;
    handler_->ref = 1;
    handler_->owner = this;
    hr = pool->add_FrameArrived(
        reinterpret_cast<
            __FITypedEventHandler_2_Windows__CGraphics__CCapture__CDirect3D11CaptureFramePool_IInspectable*>(
            handler_.get()),
        &token_);
    if (FAILED(hr)) {
      message_ = "add_FrameArrived failed";
      return false;
    }
    has_token_ = true;
    pool_ = pool;
    session_ = session;
    session_->StartCapture();
    return true;
  }

  void stop() {
    if (session_) {
      session_.Reset();
    }
    if (pool_) {
      if (has_token_) {
        pool_->remove_FrameArrived(token_);
        has_token_ = false;
      }
      pool_.Reset();
    }
    if (handler_) {
      handler_->owner = nullptr;
      handler_.reset();
    }
  }

  // Runs on the capture thread.
  void OnFrameArrived() {
    if (!pool_) return;
    ComPtr<wgc::IDirect3D11CaptureFrame> frame;
    if (FAILED(pool_->TryGetNextFrame(&frame))) return;
    ComPtr<wgxd3d::IDirect3DSurface> surface;
    if (FAILED(frame->get_Surface(&surface))) return;
    ComPtr<IDirect3DDxgiInterfaceAccess> access;
    if (FAILED(surface.As(&access))) return;
    ComPtr<ID3D11Texture2D> texture;
    if (FAILED(access->GetInterface(
            __uuidof(ID3D11Texture2D),
            reinterpret_cast<void**>(texture.GetAddressOf())))) {
      return;
    }
    D3D11_TEXTURE2D_DESC desc{};
    texture->GetDesc(&desc);
    if (desc.Width == 0 || desc.Height == 0) return;
    EnsureStaging(desc.Width, desc.Height);
    if (!staging_) return;
    context_->CopyResource(staging_.Get(), texture.Get());
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context_->Map(staging_.Get(), 0, D3D11_MAP_READ, 0, &mapped))) {
      return;
    }
    const size_t rowBytes = static_cast<size_t>(desc.Width) * 4;
    bgra_.resize(rowBytes * desc.Height);
    for (UINT row = 0; row < desc.Height; row++) {
      std::memcpy(bgra_.data() + row * rowBytes,
                  static_cast<const uint8_t*>(mapped.pData) +
                      static_cast<size_t>(row) * mapped.RowPitch,
                  rowBytes);
    }
    context_->Unmap(staging_.Get(), 0);
    if (on_frame_) {
      on_frame_(bgra_.data(), static_cast<int>(desc.Width),
                static_cast<int>(desc.Height), GetTickCount64());
    }
  }

  void set_frame_callback(
      std::function<void(const uint8_t*, int, int, int64_t)> callback) {
    on_frame_ = std::move(callback);
  }

  const std::string& message() const { return message_; }

 private:
  static HMONITOR PrimaryMonitor() {
    struct Context {
      HMONITOR monitor = nullptr;
    } context;
    EnumDisplayMonitors(
        nullptr, nullptr,
        [](HMONITOR monitor, HDC, RECT*, LPARAM param) -> BOOL {
          auto* ctx = reinterpret_cast<Context*>(param);
          MONITORINFOEXW info{};
          info.cbSize = sizeof(info);
          if (GetMonitorInfoW(monitor, &info) &&
              (info.dwFlags & MONITORINFOF_PRIMARY)) {
            ctx->monitor = monitor;
            return FALSE;
          }
          return TRUE;
        },
        reinterpret_cast<LPARAM>(&context));
    if (context.monitor == nullptr) {
      EnumDisplayMonitors(
          nullptr, nullptr,
          [](HMONITOR monitor, HDC, RECT*, LPARAM param) -> BOOL {
            auto* ctx = reinterpret_cast<Context*>(param);
            ctx->monitor = monitor;
            return FALSE;
          },
          reinterpret_cast<LPARAM>(&context));
    }
    return context.monitor;
  }

  void EnsureStaging(UINT width, UINT height) {
    if (staging_ && desc_.Width == width && desc_.Height == height) return;
    D3D11_TEXTURE2D_DESC desc{};
    desc.Width = width;
    desc.Height = height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    staging_.Reset();
    device_->CreateTexture2D(&desc, nullptr, &staging_);
    desc_ = desc;
  }

  ComPtr<ID3D11Device> device_;
  ComPtr<ID3D11DeviceContext> context_;
  ComPtr<ID3D11Texture2D> staging_;
  D3D11_TEXTURE2D_DESC desc_{};
  ComPtr<wgc::IDirect3D11CaptureFramePool> pool_;
  ComPtr<wgc::IGraphicsCaptureSession> session_;
  std::unique_ptr<FrameHandler> handler_;
  EventRegistrationToken token_;
  bool has_token_ = false;
  std::vector<uint8_t> bgra_;
  std::function<void(const uint8_t*, int, int, int64_t)> on_frame_;
  int width_ = 0;
  int height_ = 0;
  int fps_ = 30;
  std::string message_;
};

void orbitInvokeFrameHandler(WgcSession* owner) { owner->OnFrameArrived(); }

// ---------------------------------------------------------------------------
// Shared frame slot: the Dart isolate polls the newest frame.
// ---------------------------------------------------------------------------
struct FrameSlot {
  std::mutex mutex;
  std::vector<uint8_t> data;
  int width = 0;
  int height = 0;
  int keyframe = 0;
  int64_t timestamp = 0;
  bool pending = false;

  void store(std::vector<uint8_t> bytes,
            int w,
            int h,
            int key,
            int64_t ts) {
    std::lock_guard<std::mutex> guard(mutex);
    data = std::move(bytes);
    width = w;
    height = h;
    keyframe = key;
    timestamp = ts;
    pending = true;
  }
};

class EncoderRuntime {
 public:
  int create(int width, int height, int fps, int quality) {
    stop();
    width_ = width;
    height_ = height;
    fps_ = fps > 0 ? fps : 30;
    quality_ = quality > 0 ? quality : 85;
    if (!turbo_.load()) {
      message_ = turbo_.message();
      return -1;
    }
    if (!capture_.start(width_, height_, fps_)) {
      message_ = capture_.message();
      return -2;
    }
    capture_.set_frame_callback(
        [this](const uint8_t* bgra, int w, int h, int64_t ts) {
          OnFrame(bgra, w, h, ts);
        });
    return 0;
  }

  void OnFrame(const uint8_t* bgra, int w, int h, int64_t ts) {
    frames_++;
    std::vector<uint8_t> encoded;
    if (turbo_.compress(bgra, w, h, quality_, encoded)) {
      bytes_ += encoded.size();
      slot_.store(std::move(encoded), w, h, 1, ts);
    }
  }

  void start() { running_ = true; }

  void stop() {
    running_ = false;
    capture_.stop();
  }

  void destroy() { stop(); }

  int take(uint8_t* dst,
           int capacity,
           int* outSize,
           int* outKeyframe,
           int64_t* outTimestamp,
           int* outWidth,
           int* outHeight) {
    std::lock_guard<std::mutex> guard(slot_.mutex);
    if (!slot_.pending) return 0;
    slot_.pending = false;
    const int size = static_cast<int>(slot_.data.size());
    if (size > capacity) {
      *outSize = 0;
      return 0;
    }
    std::memcpy(dst, slot_.data.data(), size);
    *outSize = size;
    *outKeyframe = slot_.keyframe;
    *outTimestamp = slot_.timestamp;
    *outWidth = slot_.width;
    *outHeight = slot_.height;
    return 1;
  }

  uint64_t frame_count() const { return frames_; }
  uint64_t byte_count() const { return bytes_; }
  const std::string& message() const { return message_; }

 private:
  WgcSession capture_;
  TurboJpeg turbo_;
  FrameSlot slot_;
  int width_ = 0;
  int height_ = 0;
  int fps_ = 30;
  int quality_ = 85;
  bool running_ = false;
  uint64_t frames_ = 0;
  uint64_t bytes_ = 0;
  std::string message_;
};

EncoderRuntime g_encoder;

}  // namespace

extern "C" {

__declspec(dllexport) int orbit_encoder_create(int width,
                                               int height,
                                               int fps,
                                               int quality) {
  return g_encoder.create(width, height, fps, quality);
}

__declspec(dllexport) int orbit_encoder_start(void) {
  g_encoder.start();
  return 0;
}

__declspec(dllexport) void orbit_encoder_stop(void) { g_encoder.stop(); }

__declspec(dllexport) void orbit_encoder_destroy(void) { g_encoder.destroy(); }

__declspec(dllexport) int orbit_encoder_take_frame(uint8_t* dst,
                                                   int capacity,
                                                   int* outSize,
                                                   int* outKeyframe,
                                                   int64_t* outTimestamp,
                                                   int* outWidth,
                                                   int* outHeight) {
  return g_encoder.take(dst, capacity, outSize, outKeyframe, outTimestamp,
                         outWidth, outHeight);
}

__declspec(dllexport) const char* orbit_encoder_last_message(void) {
  return g_encoder.message().c_str();
}

__declspec(dllexport) unsigned long long orbit_encoder_frame_count(void) {
  return g_encoder.frame_count();
}

__declspec(dllexport) unsigned long long orbit_encoder_byte_count(void) {
  return g_encoder.byte_count();
}

}  // extern "C"
