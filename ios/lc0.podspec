#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint stockfish.podspec' to validate before publishing.
#
#
require 'yaml'

root = __dir__
pubspec = YAML.load(File.read(File.join(__dir__, '../pubspec.yaml')))

Pod::Spec.new do |s|
  s.name             = pubspec['name']
  s.version          = pubspec['version']
  s.summary          = pubspec['description']
  s.homepage         = pubspec['homepage']
  s.license          = { :file => '../LICENSE', :type => 'GPL' }
  s.author           = 'T-Bone Duplexus'
  s.source = { :git => pubspec['repository'], :tag => s.version.to_s }
  s.source_files = [
    'Classes/Lc0Plugin.mm',
    'Classes/Lc0Plugin.h',
    'src/ffi.cpp',
    'src/lc0io.cpp',
    'lc0/src/main.cc',
    'lc0/src/engine.cc',
    'lc0/src/engine_loop.cc',
    'lc0/src/version.cc',
    'lc0/src/chess/board.cc',
    'lc0/src/chess/gamestate.cc',
    'lc0/src/chess/position.cc',
    'lc0/src/chess/uciloop.cc',
    'lc0/src/neural/backend.cc',
    'lc0/src/neural/batchsplit.cc',
    'lc0/src/neural/decoder.cc',
    'lc0/src/neural/encoder.cc',
    'lc0/src/neural/factory.cc',
    'lc0/src/neural/loader.cc',
    'lc0/src/neural/memcache.cc',
    'lc0/src/neural/network_legacy.cc',
    'lc0/src/neural/register.cc',
    'lc0/src/neural/shared_params.cc',
    'lc0/src/neural/wrapper.cc',
    'lc0/src/neural/backends/blas/convolution1.cc',
    'lc0/src/neural/backends/blas/fully_connected_layer.cc',
    'lc0/src/neural/backends/blas/network_blas.cc',
    'lc0/src/neural/backends/blas/se_unit.cc',
    'lc0/src/neural/backends/blas/winograd_convolution3.cc',
    'lc0/src/neural/backends/shared/activation.cc',
    'lc0/src/neural/backends/shared/winograd_filter.cc',
    'lc0/src/search/register.cc',
    'lc0/src/search/classic/node.cc',
    'lc0/src/search/classic/params.cc',
    'lc0/src/search/classic/search.cc',
    'lc0/src/search/classic/wrapper.cc',
    'lc0/src/search/classic/stoppers/alphazero.cc',
    'lc0/src/search/classic/stoppers/common.cc',
    'lc0/src/search/classic/stoppers/factory.cc',
    'lc0/src/search/classic/stoppers/legacy.cc',
    'lc0/src/search/classic/stoppers/simple.cc',
    'lc0/src/search/classic/stoppers/smooth.cc',
    'lc0/src/search/classic/stoppers/stoppers.cc',
    'lc0/src/search/classic/stoppers/timemgr.cc',
    'lc0/src/syzygy/syzygy.cc',
    'lc0/src/tools/backendbench.cc',
    'lc0/src/tools/benchmark.cc',
    'lc0/src/utils/commandline.cc',
    'lc0/src/utils/configfile.cc',
    'lc0/src/utils/esc_codes.cc',
    'lc0/src/utils/files.cc',
    'lc0/src/utils/filesystem.posix.cc',
    'lc0/src/utils/histogram.cc',
    'lc0/src/utils/logging.cc',
    'lc0/src/utils/numa.cc',
    'lc0/src/utils/optionsdict.cc',
    'lc0/src/utils/optionsparser.cc',
    'lc0/src/utils/protomessage.cc',
    'lc0/src/utils/random.cc',
    'lc0/src/utils/string.cc',
    'lc0/src/utils/weights_adapter.cc'
  ]
  s.public_header_files = 'ios/Classes/Lc0Plugin.h'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.library = 'z'
  s.xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => "$(inherited) \"#{__dir__}/src\" \"#{__dir__}/lc0\" \"#{__dir__}/lc0/src\" \"#{__dir__}/eigen\"",
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -w -std=c++20 -DUSE_PTHREADS -DEIGEN_NO_CPUID -DNDEBUG -O3 -DIS_64BIT -DNO_PEXT',# -flto=thin',
    'OTHER_LDFLAGS' => '$(inherited) -w -std=c++20 -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DNO_PEXT'# -flto=thin'
  }
  s.prepare_command = <<-CMD
    bash ../fetchSources.sh
  CMD

end
