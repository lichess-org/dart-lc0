// swift-tools-version: 5.9

import PackageDescription

// The engine's own flags, mirroring the podspec's OTHER_CPLUSPLUSFLAGS and the
// Android build's target_compile_options. `-w` is deliberate: these are vendored
// third-party sources and their warnings are not this project's to fix.
let engineFlags = [
    "-w",
    "-DUSE_PTHREADS",
    "-DEIGEN_NO_CPUID",
    "-DNDEBUG",
    "-DIS_64BIT",
    "-DNO_PEXT",
]

// Only for non-debug builds. SPM distinguishes debug from release, and Xcode
// treats a Flutter "Profile" configuration as non-debug, so `.release` covers
// both of the configurations an app actually ships.
let releaseFlags = ["-O3"]

let package = Package(
    name: "lc0",
    platforms: [
        .iOS("13.0"),
    ],
    products: [
        .library(name: "lc0", targets: ["lc0"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "lc0",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            // Listed rather than excluded. The vendored engine ships 112 .cc
            // files and this build wants 56 of them: the rest are other
            // backends (CUDA, Metal, ONNX, SYCL), the training tools and the
            // rescorer, none of which build on iOS. Excluding them all would be
            // a longer list that has to grow every time upstream adds a file.
            //
            // Keep this in step with android/CMakeLists.txt, which compiles the
            // same set.
            sources: [
                "ffi.cpp",
                "lc0io.cpp",

                "engine/src/engine_main.cc",
                "engine/src/engine.cc",
                "engine/src/engine_loop.cc",
                "engine/src/version.cc",
                "engine/src/chess/board.cc",
                "engine/src/chess/gamestate.cc",
                "engine/src/chess/position.cc",
                "engine/src/chess/uciloop.cc",
                "engine/src/neural/backend.cc",
                "engine/src/neural/batchsplit.cc",
                "engine/src/neural/decoder.cc",
                "engine/src/neural/encoder.cc",
                "engine/src/neural/factory.cc",
                "engine/src/neural/loader.cc",
                "engine/src/neural/memcache.cc",
                "engine/src/neural/network_legacy.cc",
                "engine/src/neural/register.cc",
                "engine/src/neural/shared_params.cc",
                "engine/src/neural/wrapper.cc",
                "engine/src/neural/backends/blas/convolution1.cc",
                "engine/src/neural/backends/blas/fully_connected_layer.cc",
                "engine/src/neural/backends/blas/network_blas.cc",
                "engine/src/neural/backends/blas/se_unit.cc",
                "engine/src/neural/backends/blas/winograd_convolution3.cc",
                "engine/src/neural/backends/shared/activation.cc",
                "engine/src/neural/backends/shared/winograd_filter.cc",
                "engine/src/search/register.cc",
                "engine/src/search/classic/node.cc",
                "engine/src/search/classic/params.cc",
                "engine/src/search/classic/search.cc",
                "engine/src/search/classic/wrapper.cc",
                "engine/src/search/classic/stoppers/alphazero.cc",
                "engine/src/search/classic/stoppers/common.cc",
                "engine/src/search/classic/stoppers/factory.cc",
                "engine/src/search/classic/stoppers/legacy.cc",
                "engine/src/search/classic/stoppers/simple.cc",
                "engine/src/search/classic/stoppers/smooth.cc",
                "engine/src/search/classic/stoppers/stoppers.cc",
                "engine/src/search/classic/stoppers/timemgr.cc",
                "engine/src/syzygy/syzygy.cc",
                "engine/src/tools/backendbench.cc",
                "engine/src/tools/benchmark.cc",
                "engine/src/utils/commandline.cc",
                "engine/src/utils/configfile.cc",
                "engine/src/utils/esc_codes.cc",
                "engine/src/utils/files.cc",
                "engine/src/utils/filesystem.posix.cc",
                "engine/src/utils/histogram.cc",
                "engine/src/utils/logging.cc",
                "engine/src/utils/numa.cc",
                "engine/src/utils/optionsdict.cc",
                "engine/src/utils/optionsparser.cc",
                "engine/src/utils/protomessage.cc",
                "engine/src/utils/random.cc",
                "engine/src/utils/string.cc",
                "engine/src/utils/weights_adapter.cc",
            ],
            cxxSettings: [
                // Some engine sources include "src/…", i.e. paths relative to the lc0
                // repository root, which is `engine/` here.
                .headerSearchPath("."),
                // Also SwiftPM's public headers directory for this target, which it
                // insists on having.
                .headerSearchPath("include/lc0"),
                .headerSearchPath("engine"),
                .headerSearchPath("engine/src"),
                .headerSearchPath("eigen"),
                .unsafeFlags(engineFlags),
                .unsafeFlags(releaseFlags, .when(configuration: .release)),
            ],
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        )
    ],
    cxxLanguageStandard: .cxx20
)
