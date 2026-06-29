import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

class JsCallDartPluginPage extends StatefulWidget {
  const JsCallDartPluginPage({
    super.key,
    this.axiosUrl = 'https://example.com/',
  });

  final String axiosUrl;

  @override
  State<JsCallDartPluginPage> createState() => _JsCallDartPluginPageState();
}

class _JsCallDartPluginPageState extends State<JsCallDartPluginPage> {
  static const _runtimeMaxAge = Duration(minutes: 30);

  Quickjs? _quickjs;
  DateTime? _runtimeCreatedAt;
  bool _busy = true;
  String _result = '';
  final List<String> _logs = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    try {
      _appendLog('创建 QuickJS runtime');
      final previous = _quickjs;
      _quickjs = null;
      _runtimeCreatedAt = null;
      await previous?.dispose();
      final plugin = await QuickjsPlugin.singleFileAsset(
        id: 'assetApi',
        version: '1.0.0',
        assetKey: 'assets/js/js_call_dart_plugin.mjs',
        exports: const <String>['test2', 'axiosGet'],
      );
      final quickjs = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsFetchMount(
              allowedOrigins: <String>{_originOf(widget.axiosUrl)},
              maxResponseBytes: 1024 * 1024,
              timeout: const Duration(seconds: 15),
            ),
            plugin.asMount(),
          ],
          providers: <QuickjsHostProvider>[
            QuickjsHostProvider.global(
              name: 'alert',
              callback: (args, _) {
                final output = args.join(' ');
                _appendLog('alert <= $output');
                return showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('JS Alert'),
                      content: SingleChildScrollView(child: Text(output)),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            QuickjsHostProvider.global(
              name: 'getDataAsync',
              callback: (args, _) {
                _appendLog('getDataAsync <= $args');
                return '来自Dart的消息';
              },
            ),
            QuickjsHostProvider.global(
              name: 'dartMethod',
              callback: (args, _) {
                _appendLog('dartMethod <= $args');
                return '这是静态消息';
              },
            ),
            QuickjsHostProvider.global(
              name: 'asyncWithError',
              callback: (_, _) async {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                throw StateError('Some error');
              },
            ),
          ],
          environmentPatches: <QuickjsHostScript>[
            await QuickjsHostScript.asset(
              name: 'example:axios.js',
              assetKey: 'assets/js/axios.js',
              globals: const <String>['axios'],
            ),
          ],
        ),
        onConsole: (event) {
          _appendLog('console.${event.level.name}: ${event.text}');
        },
      );
      _quickjs = quickjs;
      _runtimeCreatedAt = DateTime.now();
      if (!mounted) {
        await quickjs.dispose();
        return;
      }
      setState(() {
        _busy = false;
      });
      _appendLog('插件已加载，Dart 方法已注册');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _result = '$error';
      });
      _appendLog('创建失败 => $error');
    }
  }

  String _originOf(String url) {
    final uri = Uri.parse(url);
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }

  Future<Quickjs> _runtimeForRun() async {
    final quickjs = _quickjs;
    final createdAt = _runtimeCreatedAt;
    if (quickjs != null &&
        createdAt != null &&
        DateTime.now().difference(createdAt) < _runtimeMaxAge) {
      return quickjs;
    }

    _appendLog('runtime 闲置超过 ${_runtimeMaxAge.inMinutes} 分钟，运行前自动重建');
    await _createRuntime();
    final rebuilt = _quickjs;
    if (rebuilt == null) {
      throw StateError('QuickJS runtime rebuild failed');
    }
    return rebuilt;
  }

  Future<void> _runPlugin() async {
    setState(() {
      _busy = true;
      _result = '';
    });
    try {
      final quickjs = await _runtimeForRun();
      final result = await quickjs.invokePlugin('test2', <Object?>[
        'ss\'·\$`"dd"}{s',
        99,
        {'aa': 'vv""`\'v'},
        ['sss', 'dd]dd'],
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _result = '$result';
      });
      _appendLog('返回 => $result');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _result = '$error';
      });
      _appendLog('运行 test2 失败 => $error');
    }
  }

  Future<void> _runAxios() async {
    setState(() {
      _busy = true;
      _result = '';
    });
    try {
      final quickjs = await _runtimeForRun();
      final result = await quickjs.invokePlugin('axiosGet', <Object?>[
        widget.axiosUrl,
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _result = '$result';
      });
      _appendLog('axiosGet => $result');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _result = '$error';
      });
      _appendLog('axiosGet 失败 => $error');
    }
  }

  void _appendLog(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _logs.insert(0, message);
    });
  }

  @override
  void dispose() {
    final quickjs = _quickjs;
    _quickjs = null;
    _runtimeCreatedAt = null;
    unawaited(quickjs?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('JsCallDart 插件')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _busy ? null : _runPlugin,
              child: const Text('运行 test2'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _runAxios,
              child: const Text('Axios 请求网页'),
            ),
            const SizedBox(height: 16),
            SelectableText('result: $_result'),
            const SizedBox(height: 16),
            Expanded(
              child: _logs.isEmpty
                  ? const Center(child: Text('暂无日志'))
                  : ListView.separated(
                      itemCount: _logs.length,
                      separatorBuilder: (_, _) => const Divider(height: 16),
                      itemBuilder: (context, index) {
                        return SelectableText(_logs[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
