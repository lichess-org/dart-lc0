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

Future<void> loadWeights(Lc0 lc0) async {
  final path = await maiaWeightsPath();
  final exists = await File(path).exists();

  if (!exists) {
    final ByteData data =
        await rootBundle.load(p.url.join('assets', weightsFileName));
    final List<int> bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    await File(path).writeAsBytes(bytes, flush: true);
  }

  lc0.stdin = 'setoption name WeightsFile value $path';
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<StatefulWidget> createState() => _AppState();
}

class _AppState extends State<MyApp> {
  late Lc0 lc0;

  @override
  void initState() {
    super.initState();
    lc0 = Lc0();
    loadWeights(lc0);
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
              child: AnimatedBuilder(
                animation: lc0.state,
                builder: (_, __) => Text(
                  'lc0.state=${lc0.state.value}',
                  key: const ValueKey('lc0.state'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: AnimatedBuilder(
                animation: lc0.state,
                builder: (_, __) => ElevatedButton(
                  onPressed: lc0.state.value == Lc0State.disposed
                      ? () {
                          final newInstance = Lc0();
                          setState(() => lc0 = newInstance);
                        }
                      : null,
                  child: const Text('Reset Lc0 instance'),
                ),
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
                onSubmitted: (value) => lc0.stdin = value,
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
                        onPressed: () => lc0.stdin = command,
                        child: Text(command),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            Expanded(
              child: OutputWidget(lc0.stdout),
            ),
          ],
        ),
      ),
    );
  }
}
