import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

class ZipPluginPage extends StatefulWidget {
  const ZipPluginPage({super.key});

  @override
  State<ZipPluginPage> createState() => _ZipPluginPageState();
}

class _ZipPluginPageState extends State<ZipPluginPage> {
  Quickjs? _quickjs;
  QuickjsPlugin? _plugin;
  QuickjsPluginClient? _client;
  bool _disposed = false;
  bool _busy = false;
  String _status = 'Creating runtime...';
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _status = 'Loading zip plugin asset...';
      _log.clear();
    });

    try {
      final previous = _quickjs;
      _quickjs = null;
      _plugin = null;
      _client = null;
      await previous?.dispose();

      final plugin = await QuickjsZipPlugin.asset(
        assetKey: 'assets/plugins/zip_demo.zip',
      );
      final quickjs = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[plugin.asMount()],
        ),
        onConsole: (event) {
          if (!mounted || _disposed) {
            return;
          }
          setState(() {
            _log.insert(0, 'console.${event.level.name}: ${event.text}');
          });
        },
      );
      final client = QuickjsPluginClient(quickjs, plugin);
      await client.validate();
      final initResult = await client.init(<String, Object?>{
        'locale': 'zh-CN',
      });

      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }

      setState(() {
        _quickjs = quickjs;
        _plugin = plugin;
        _client = client;
        _busy = false;
        _status =
            'Zip plugin ready: ${plugin.manifest.id}@${plugin.manifest.version}';
        _log.insert(0, 'init() => $initResult');
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'Failed: ${_describeError(error)}';
      });
    }
  }

  Future<void> _callHello() async {
    await _capture('Call hello()', () async {
      final result = await _requireClient().call('hello', const <Object?>[
        'QuickJS',
      ]);
      _log.insert(0, 'zipDemo.hello() => $result');
      _status = 'hello() returned from zip plugin';
    });
  }

  Future<void> _callProfile() async {
    await _capture('Call profile()', () async {
      final result = await _requireClient().call('profile', const <Object?>[
        'Ada',
        98,
      ]);
      _log.insert(0, 'zipDemo.profile() => $result');
      _status = 'profile() returned structured data';
    });
  }

  Future<void> _showManifest() async {
    await _capture('Show manifest', () async {
      final plugin = _requirePlugin();
      _log.insert(
        0,
        'manifest => id=${plugin.manifest.id}, entry=${plugin.manifest.entry}, '
        'exports=${plugin.manifest.exports.join(', ')}',
      );
      _log.insert(
        0,
        'modules => ${plugin.modules.map((module) => module.specifier).join(', ')}',
      );
      _status = 'Zip manifest and modules decoded';
    });
  }

  Future<void> _capture(String label, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = '$label...';
    });
    try {
      await action();
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '$label failed: ${_describeError(error)}';
        _log.insert(0, '$label => ${_describeError(error)}');
      });
    }
  }

  QuickjsPluginClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw JsRuntimeClosedException('Zip plugin client is not ready');
    }
    return client;
  }

  QuickjsPlugin _requirePlugin() {
    final plugin = _plugin;
    if (plugin == null) {
      throw JsRuntimeClosedException('Zip plugin is not ready');
    }
    return plugin;
  }

  String _describeError(Object error) {
    if (error is QuickjsException) {
      return '${error.runtimeType}: ${error.message}';
    }
    return '${error.runtimeType}: $error';
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_client?.dispose() ?? Future<Object?>.value());
    _client = null;
    unawaited(_quickjs?.dispose() ?? Future<void>.value());
    _quickjs = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _quickjs != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Zip Plugin')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              'Loads assets/plugins/zip_demo.zip with QuickjsZipPlugin.asset().',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _callHello,
                  child: const Text('hello'),
                ),
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _callProfile,
                  child: const Text('profile'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _showManifest,
                  child: const Text('manifest'),
                ),
                TextButton(
                  onPressed: _busy ? null : _createRuntime,
                  child: const Text('reload'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _log.isEmpty
                  ? const Center(child: Text('Run a zip plugin action'))
                  : ListView.separated(
                      itemCount: _log.length,
                      separatorBuilder: (_, _) => const Divider(height: 16),
                      itemBuilder: (context, index) {
                        return SelectableText(_log[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
