# Native media module: Windows Graphics Capture, libjpeg-turbo encoding and
# Media Foundation H.264 codecs.
add_library(orbitlink_encoder SHARED
  "orbitlink_encoder/orbitlink_encoder.cpp"
  "orbitlink_encoder/h264_codec.cpp")

target_compile_features(orbitlink_encoder PRIVATE cxx_std_17)
target_compile_definitions(orbitlink_encoder PRIVATE
  WIN32_LEAN_AND_MEAN
  UNICODE
  _UNICODE)
target_link_libraries(orbitlink_encoder PRIVATE
  d3d11 dxgi windowsapp ole32 oleaut32 mfplat mf mfuuid)

# The WinRT ABI headers live in the "winrt" folder of the Windows SDK and
# clash with the desktop variants, so the include order matters.
if(DEFINED ENV{WindowsSdkDir} AND DEFINED ENV{WindowsSDKVersion})
  set(ORBIT_SDK_INCLUDE "$ENV{WindowsSdkDir}Include\\$ENV{WindowsSDKVersion}")
  target_include_directories(orbitlink_encoder PRIVATE
    "${ORBIT_SDK_INCLUDE}/um"
    "${ORBIT_SDK_INCLUDE}/shared"
    "${ORBIT_SDK_INCLUDE}/winrt")
endif()

# Keep the CRT private so the module has no extra runtime dependency.
set_property(TARGET orbitlink_encoder PROPERTY
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
