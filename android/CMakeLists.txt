cmake_minimum_required(VERSION 3.4.1)
project(lc0)

add_library(
  lc0
  SHARED
  ../src/ffi.cpp
  ../lc0/src/benchmark/backendbench.cc
  ../lc0/src/benchmark/benchmark.cc
  ../lc0/src/chess/bitboard.cc
  ../lc0/src/chess/board.cc
  ../lc0/src/chess/position.cc
  ../lc0/src/chess/uciloop.cc
  ../lc0/src/main.cc
  ../lc0/src/mcts/node.cc
  ../lc0/src/mcts/params.cc
  ../lc0/src/mcts/stoppers/alphazero.cc
  ../lc0/src/mcts/stoppers/legacy.cc
  ../lc0/src/mcts/stoppers/simple.cc
  ../lc0/src/mcts/stoppers/smooth.cc
  ../lc0/src/mcts/stoppers/stoppers.cc
  ../lc0/src/mcts/stoppers/timemgr.cc
  ../lc0/src/mcts/stoppers/common.cc
  ../lc0/src/mcts/search.cc
  ../lc0/src/neural/blas/convolution1.cc
  ../lc0/src/neural/blas/fully_connected_layer.cc
  ../lc0/src/neural/blas/network_blas.cc
  ../lc0/src/neural/blas/se_unit.cc
  ../lc0/src/neural/blas/winograd_convolution3.cc
  ../lc0/src/neural/cache.cc
  ../lc0/src/neural/decoder.cc
  ../lc0/src/neural/encoder.cc
  ../lc0/src/neural/network_legacy.cc
  ../lc0/src/neural/shared/activation.cc
  ../lc0/src/neural/shared/winograd_filter.cc
  ../lc0/src/neural/loader.cc
  ../lc0/src/neural/factory.cc
  ../lc0/src/syzygy/syzygy.cc
  ../lc0/src/utils/commandline.cc
  ../lc0/src/utils/configfile.cc
  ../lc0/src/utils/esc_codes.cc
  ../lc0/src/utils/files.cc
  ../lc0/src/utils/filesystem.posix.cc
  ../lc0/src/utils/fp16_utils.cc
  ../lc0/src/utils/histogram.cc
  ../lc0/src/utils/numa.cc
  ../lc0/src/utils/optionsdict.cc
  ../lc0/src/utils/protomessage.cc
  ../lc0/src/utils/random.cc
  ../lc0/src/utils/string.cc
  ../lc0/src/utils/logging.cc
  ../lc0/src/utils/optionsparser.cc
  ../lc0/src/utils/weights_adapter.cc
  ../lc0/src/version.cc
  ../lc0/src/engine.cc
)

include_directories(../eigen ../lc0/src ../lc0 ../src)

if(ANDROID_ABI STREQUAL arm64-v8a)
  target_compile_options(lc0 PRIVATE -DEIGEN_NO_CPUID -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DNO_PEXT -DUSE_POPCNT)
elseif(ANDROID_ABI STREQUAL armeabi-v7a)
  target_compile_options(lc0 PRIVATE -DEIGEN_NO_CPUID -DUSE_PTHREADS -DNDEBUG -O3 -DNO_PEXT)
else()
  target_compile_options(lc0 PRIVATE -DEIGEN_NO_CPUID -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DUSE_POPCNT -DUSE_SSE2 -DUSE_SSSE3 -DUSE_SSE41 -DNO_PEXT -DUSE_POPCNT)
endif()

target_link_libraries(lc0 libz.so)
