// OrbitLink native media module: Windows Graphics Capture (WGC) screen
// acquisition with libjpeg-turbo encoding.
//
// The module exposes a small C ABI so the Dart side can drive it over FFI.
// Frames are stored in a single-slot buffer that the Dart isolate polls,
// which keeps the native capture thread isolated from the Flutter isolate.

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Creates an encoder that captures the primary monitor.
// Returns 0 on success, negative on failure.
__declspec(dllexport) int orbit_encoder_create(int width,
                                               int height,
                                               int fps,
                                               int quality);

__declspec(dllexport) int orbit_encoder_start(void);
__declspec(dllexport) void orbit_encoder_stop(void);
__declspec(dllexport) void orbit_encoder_destroy(void);

// Copies the newest encoded frame into |dst|. Returns 1 when a frame was
// copied, 0 when no new frame is available.
__declspec(dllexport) int orbit_encoder_take_frame(uint8_t* dst,
                                                   int capacity,
                                                   int* outSize,
                                                   int* outKeyframe,
                                                   int64_t* outTimestamp,
                                                   int* outWidth,
                                                   int* outHeight);

__declspec(dllexport) const char* orbit_encoder_last_message(void);

// Statistics for the running encoder.
__declspec(dllexport) unsigned long long orbit_encoder_frame_count(void);
__declspec(dllexport) unsigned long long orbit_encoder_byte_count(void);

#ifdef __cplusplus
}
#endif
