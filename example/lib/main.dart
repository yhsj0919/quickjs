import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _quickjsVersion = '…';
  String _evalResult = '…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final engine = await Quickjs.create();
      final version = engine.quickjsVersion;
      final result = await engine.evaluate('1 + 2 * 3');
      if (!mounted) return;
      setState(() {
        _quickjsVersion = version;
        _evalResult = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quickjsVersion = 'error';
        _evalResult = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('quickjs example')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('QuickJS: $_quickjsVersion'),
              const SizedBox(height: 8),
              Text('eval("1 + 2 * 3") => $_evalResult'),
            ],
          ),
        ),
      ),
    );
  }
}
