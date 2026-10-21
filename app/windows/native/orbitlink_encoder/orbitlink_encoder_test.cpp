// Standalone verification for the OrbitLink native media module.
//
//   orbitlink_encoder_test.exe
//
// It captures the primary monitor for a few seconds and prints the achieved
// frame rate together with the average encoded frame size.

#include <windows.h>

#include <chrono>
#include <cstdio>
#include <vector>

#include "orbitlink_encoder.h"

int main() {
  const int width = 1600;
  const int height = 900;
  const int fps = 30;

  const int rc = orbit_encoder_create(width, height, fps, 85);
  printf("create rc=%d %s\n", rc, orbit_encoder_last_message());
  if (rc != 0) return 1;
  orbit_encoder_start();

  std::vector<uint8_t> buffer(16 * 1024 * 1024);
  int lastSize = 0;
  int lastWidth = 0;
  int lastHeight = 0;
  const auto start = std::chrono::high_resolution_clock::now();
  double seconds = 0;
  int polls = 0;
  while (seconds < 4.0) {
    const auto now = std::chrono::high_resolution_clock::now();
    seconds = std::chrono::duration<double>(now - start).count();
    int size = 0;
    int keyframe = 0;
    int w = 0;
    int h = 0;
    long long timestamp = 0;
    if (orbit_encoder_take_frame(buffer.data(),
                                 static_cast<int>(buffer.size()), &size,
                                 &keyframe, &timestamp, &w, &h) == 1) {
      lastSize = size;
      lastWidth = w;
      lastHeight = h;
    }
    polls++;
    Sleep(2);
  }
  const unsigned long long frames = orbit_encoder_frame_count();
  const unsigned long long bytes = orbit_encoder_byte_count();
  printf("%llu frames in %.1fs = %.1f fps, avg %.0f KB, last %d bytes %dx%d\n",
         frames, seconds, frames / seconds,
         frames ? static_cast<double>(bytes) / frames / 1024.0 : 0.0, lastSize,
         lastWidth, lastHeight);
  orbit_encoder_destroy();
  return 0;
}
