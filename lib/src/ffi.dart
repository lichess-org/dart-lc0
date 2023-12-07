import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final _nativeLib = Platform.isAndroid
    ? DynamicLibrary.open('liblc0.so')
    : DynamicLibrary.process();

final int Function() nativeMain = _nativeLib
    .lookup<NativeFunction<Int32 Function()>>('lc0_main')
    .asFunction();

final int Function(Pointer<Utf8>) nativeStdinWrite = _nativeLib
    .lookup<NativeFunction<IntPtr Function(Pointer<Utf8>)>>('lc0_stdin_write')
    .asFunction();

final Pointer<Utf8> Function() nativeStdoutRead = _nativeLib
    .lookup<NativeFunction<Pointer<Utf8> Function()>>('lc0_stdout_read')
    .asFunction();
