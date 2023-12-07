#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint stockfish.podspec' to validate before publishing.
#
#
require 'yaml'

root = __dir__
pubspec = YAML.load(File.read(File.join(__dir__, 'pubspec.yaml')))

Pod::Spec.new do |s|
  s.name             = pubspec['name']
  s.version          = pubspec['version']
  s.summary          = pubspec['description']
  s.homepage         = pubspec['homepage']
  s.license          = { :file => 'LICENSE', :type => 'GPL' }
  s.author           = 'T-Bone Duplexus'
  s.source = { :git => pubspec['repository'], :tag => s.version.to_s }
  s.source_files = [
    'ios/Classes/Lc0Plugin.mm',
    'ios/Classes/Lc0Plugin.h',
    'src/ffi.cpp',
    'lc0/src/benchmark/backendbench.cc',
    'lc0/src/benchmark/benchmark.cc',
    'lc0/src/chess/bitboard.cc',
    'lc0/src/chess/board.cc',
    'lc0/src/chess/position.cc',
    'lc0/src/chess/uciloop.cc',
    'lc0/src/main.cc',
    'lc0/src/mcts/node.cc',
    'lc0/src/mcts/params.cc',
    'lc0/src/mcts/stoppers/alphazero.cc',
    'lc0/src/mcts/stoppers/legacy.cc',
    'lc0/src/mcts/stoppers/simple.cc',
    'lc0/src/mcts/stoppers/smooth.cc',
    'lc0/src/mcts/stoppers/stoppers.cc',
    'lc0/src/mcts/stoppers/timemgr.cc',
    'lc0/src/mcts/stoppers/common.cc',
    'lc0/src/mcts/search.cc',
    'lc0/src/neural/blas/convolution1.cc',
    'lc0/src/neural/blas/fully_connected_layer.cc',
    'lc0/src/neural/blas/network_blas.cc',
    'lc0/src/neural/blas/se_unit.cc',
    'lc0/src/neural/blas/winograd_convolution3.cc',
    'lc0/src/neural/cache.cc',
    'lc0/src/neural/decoder.cc',
    'lc0/src/neural/encoder.cc',
    'lc0/src/neural/network_legacy.cc',
    'lc0/src/neural/shared/activation.cc',
    'lc0/src/neural/shared/winograd_filter.cc',
    'lc0/src/neural/loader.cc',
    'lc0/src/neural/factory.cc',
    'lc0/src/syzygy/syzygy.cc',
    'lc0/src/utils/commandline.cc',
    'lc0/src/utils/configfile.cc',
    'lc0/src/utils/esc_codes.cc',
    'lc0/src/utils/files.cc',
    'lc0/src/utils/filesystem.posix.cc',
    'lc0/src/utils/fp16_utils.cc',
    'lc0/src/utils/histogram.cc',
    'lc0/src/utils/numa.cc',
    'lc0/src/utils/optionsdict.cc',
    'lc0/src/utils/protomessage.cc',
    'lc0/src/utils/random.cc',
    'lc0/src/utils/string.cc',
    'lc0/src/utils/logging.cc',
    'lc0/src/utils/optionsparser.cc',
    'lc0/src/utils/weights_adapter.cc',
    'lc0/src/version.cc',
    'lc0/src/engine.cc'
  ]
  s.public_header_files = 'ios/Classes/Lc0Plugin.h'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  # s.ios.deployment_target  = '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.library = 'z'
  # s.script_phase = {
  #   :execution_position => :before_compile,
  #   :name => 'Fetch sources',
  #   :script => '../../fetchSources.sh'
  # }
  s.xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => "$(inherited) \"#{__dir__}/src\" \"#{__dir__}/lc0\" \"#{__dir__}/lc0/src\" \"#{__dir__}/eigen\"",
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -w -std=c++17 -DUSE_PTHREADS -DEIGEN_NO_CPUID -DNDEBUG -O3 -DIS_64BIT -DNO_PEXT',# -flto=thin',
    'OTHER_LDFLAGS' => '$(inherited) -w -std=c++17 -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DNO_PEXT'# -flto=thin'
  }
  s.prepare_command = <<-CMD
    bash fetchSources.sh
  CMD

end
