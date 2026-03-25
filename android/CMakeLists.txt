cmake_minimum_required(VERSION 3.4.1)
project(lc0)

add_library(
  lc0
  SHARED
  ../ios/src/ffi.cpp
  ../ios/lc0/src/main.cc
  ../ios/lc0/src/engine.cc
  ../ios/lc0/src/engine_loop.cc
  ../ios/lc0/src/version.cc
  ../ios/lc0/src/chess/board.cc
  ../ios/lc0/src/chess/gamestate.cc
  ../ios/lc0/src/chess/position.cc
  ../ios/lc0/src/chess/uciloop.cc
  ../ios/lc0/src/neural/backend.cc
  ../ios/lc0/src/neural/batchsplit.cc
  ../ios/lc0/src/neural/decoder.cc
  ../ios/lc0/src/neural/encoder.cc
  ../ios/lc0/src/neural/factory.cc
  ../ios/lc0/src/neural/loader.cc
  ../ios/lc0/src/neural/memcache.cc
  ../ios/lc0/src/neural/network_legacy.cc
  ../ios/lc0/src/neural/register.cc
  ../ios/lc0/src/neural/shared_params.cc
  ../ios/lc0/src/neural/wrapper.cc
  ../ios/lc0/src/neural/backends/blas/convolution1.cc
  ../ios/lc0/src/neural/backends/blas/fully_connected_layer.cc
  ../ios/lc0/src/neural/backends/blas/network_blas.cc
  ../ios/lc0/src/neural/backends/blas/se_unit.cc
  ../ios/lc0/src/neural/backends/blas/winograd_convolution3.cc
  ../ios/lc0/src/neural/backends/shared/activation.cc
  ../ios/lc0/src/neural/backends/shared/winograd_filter.cc
  ../ios/lc0/src/search/register.cc
  ../ios/lc0/src/search/classic/node.cc
  ../ios/lc0/src/search/classic/params.cc
  ../ios/lc0/src/search/classic/search.cc
  ../ios/lc0/src/search/classic/wrapper.cc
  ../ios/lc0/src/search/classic/stoppers/alphazero.cc
  ../ios/lc0/src/search/classic/stoppers/common.cc
  ../ios/lc0/src/search/classic/stoppers/factory.cc
  ../ios/lc0/src/search/classic/stoppers/legacy.cc
  ../ios/lc0/src/search/classic/stoppers/simple.cc
  ../ios/lc0/src/search/classic/stoppers/smooth.cc
  ../ios/lc0/src/search/classic/stoppers/stoppers.cc
  ../ios/lc0/src/search/classic/stoppers/timemgr.cc
  ../ios/lc0/src/syzygy/syzygy.cc
  ../ios/lc0/src/tools/backendbench.cc
  ../ios/lc0/src/tools/benchmark.cc
  ../ios/lc0/src/utils/commandline.cc
  ../ios/lc0/src/utils/configfile.cc
  ../ios/lc0/src/utils/esc_codes.cc
  ../ios/lc0/src/utils/files.cc
  ../ios/lc0/src/utils/filesystem.posix.cc
  ../ios/lc0/src/utils/histogram.cc
  ../ios/lc0/src/utils/logging.cc
  ../ios/lc0/src/utils/numa.cc
  ../ios/lc0/src/utils/optionsdict.cc
  ../ios/lc0/src/utils/optionsparser.cc
  ../ios/lc0/src/utils/protomessage.cc
  ../ios/lc0/src/utils/random.cc
  ../ios/lc0/src/utils/string.cc
  ../ios/lc0/src/utils/weights_adapter.cc
)

include_directories(../ios/eigen ../ios/lc0/src ../ios/lc0 ../ios/src)

if(ANDROID_ABI STREQUAL arm64-v8a)
  target_compile_options(lc0 PRIVATE -std=c++20 -DEIGEN_NO_CPUID -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DNO_PEXT -DUSE_POPCNT)
elseif(ANDROID_ABI STREQUAL armeabi-v7a)
  target_compile_options(lc0 PRIVATE -std=c++20 -DEIGEN_NO_CPUID -DUSE_PTHREADS -DNDEBUG -O3 -DNO_PEXT)
else()
  target_compile_options(lc0 PRIVATE -std=c++20 -DEIGEN_NO_CPUID -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DUSE_POPCNT -DUSE_SSE2 -DUSE_SSSE3 -DUSE_SSE41 -DNO_PEXT -DUSE_POPCNT)
endif()

target_link_libraries(lc0 libz.so)
