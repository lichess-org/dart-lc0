import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lc0/lc0.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'src/output_widget.dart';

const weightsFileName = 'maia1500.pb.gz';

void main() {
  runApp(const MyApp());
}

Future<String> maiaWeightsPath() async {
  final directory = await getApplicationDocumentsDirectory();
  return p.join(directory.path, weightsFileName);
}

/// Unpacks the bundled network next to the app's documents, and returns where
/// it landed.
Future<String> loadWeights() async {
  final path = await maiaWeightsPath();
  final exists = await File(path).exists();

  if (!exists) {
    final ByteData data =
        await rootBundle.load(p.url.join('assets', weightsFileName));
    final List<int> bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    await File(path).writeAsBytes(bytes, flush: true);
  }

  return path;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<StatefulWidget> createState() => _AppState();
}

class _AppState extends State<MyApp> {
  /// The engine, once it has started. There is at most one at a time: lc0 keeps
  /// its state in process globals.
  Lc0? lc0;

  /// The lines the engine has written, kept here rather than in the widget so
  /// that they survive an engine being disposed and another one created.
  final _output = StreamController<String>.broadcast();

  bool _starting = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    lc0?.dispose();
    _output.close();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting || lc0 != null) return;
    setState(() {
      _starting = true;
      _error = null;
    });

    try {
      final engine = await Lc0.create(onStdout: _output.add);
      final weights = await loadWeights();
      engine.stdin = 'setoption name WeightsFile value $weights';
      setState(() {
        lc0 = engine;
        _starting = false;
      });
    } catch (error) {
      setState(() {
        _error = error;
        _starting = false;
      });
    }
  }

  Future<void> _stop() async {
    final engine = lc0;
    if (engine == null) return;
    setState(() => lc0 = null);
    await engine.dispose();
  }

  void _send(String command) {
    final engine = lc0;
    if (engine == null || engine.state.value != Lc0State.ready) return;
    engine.stdin = command;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Lc0 example app'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _error != null
                    ? 'lc0 failed to start: $_error'
                    : _starting
                        ? 'lc0.state=starting'
                        : 'lc0.state=${lc0?.state.value.name ?? 'none'}'
                            '${lc0 == null ? '' : ' (${lc0!.diagnostics})'}',
                key: const ValueKey('lc0.state'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: lc0 == null && !_starting ? _start : null,
                    child: const Text('Start Lc0'),
                  ),
                  ElevatedButton(
                    onPressed: lc0 == null ? null : _stop,
                    child: const Text('Dispose'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Custom UCI command',
                  hintText: 'go infinite',
                ),
                onSubmitted: _send,
                textInputAction: TextInputAction.send,
              ),
            ),
            Wrap(
              children: [
                'd',
                'isready',
                'go infinite',
                'go movetime 3000',
                'stop',
                'quit',
              ]
                  .map(
                    (command) => Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ElevatedButton(
                        onPressed: () => _send(command),
                        child: Text(command),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            Expanded(
              child: OutputWidget(_output.stream),
            ),
          ],
        ),
      ),
    );
  }
}
