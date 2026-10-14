import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_ui_video_player/lemon_js_ui_video_player.dart';
import 'package:web/web.dart' as web;

@JS('quickjsPreviewHost')
external _PreviewHost get _host;

extension type _PreviewHost(JSObject _) implements JSObject {
  external void register(JSFunction callback);
  external void emit(JSString message);
}

/// Web-only entry point for the Vue iframe preview component.
void main() => runApp(
  const MaterialApp(debugShowCheckedModeBanner: false, home: _PluginPreview()),
);

class _PluginPreview extends StatefulWidget {
  const _PluginPreview();

  @override
  State<_PluginPreview> createState() => _PluginPreviewState();
}

class _PluginPreviewState extends State<_PluginPreview> {
  JsUiController? _controller;
  Uri? _url;
  Map<String, Object?> _props = const {};
  Completer<void>? _loaded;
  Future<void> _commands = Future.value();
  final _features = <JsFeatures>[AxiosFeatures()];
  final _plugins = <JsUiPlugin>[JsUiVideoPlayerPlugin.plugin];

  void _emit(Map<String, Object?> message) =>
      _host.emit(jsonEncode(message).toJS);

  @override
  void initState() {
    super.initState();
    _host.register(
      ((JSString message) {
        _commands = _commands.then((_) => _handle(message.toDart));
      }).toJS,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      web.document.getElementById('startup-status')?.remove();
      _emit({'type': 'ready'});
    });
  }

  Future<void> _release() async {
    final previous = _controller;
    if (mounted) {
      setState(() {
        _controller = null;
        _url = null;
      });
      await WidgetsBinding.instance.endOfFrame;
    }
    await previous?.close();
  }

  Future<void> _handle(String json) async {
    Object? requestId;
    try {
      final message = Map<String, Object?>.from(jsonDecode(json) as Map);
      requestId = message['requestId'];
      if (!mounted) return;
      final command = message['command'];
      if (command == 'load') {
        final url = Uri.base.resolve(message['src']! as String);
        if (url.scheme != 'http' && url.scheme != 'https') {
          throw const FormatException('Plugin src must be an HTTP(S) URL');
        }
        final props = Map<String, Object?>.from(
          (message['pageProps'] ?? {}) as Map,
        );
        await _release();
        if (!mounted) return;
        final loaded = Completer<void>();
        _loaded = loaded;
        setState(() {
          _url = url;
          _props = props;
          _controller = JsUiController();
        });
        await loaded.future.timeout(const Duration(seconds: 60));
        _emit({'type': 'loaded', 'src': url.toString()});
      } else if (command == 'unload') {
        await _release();
      } else {
        final controller = _controller;
        if (controller == null || _loaded?.isCompleted != true) {
          throw StateError('Load a plugin before sending $command');
        }
        switch (command) {
          case 'play':
            await controller.lifecycle(JsUiLifecycle.resume);
            await controller.setState({'playing': true});
            await controller.dispatch({'method': 'onPageWillActive'});
          case 'pause':
            await controller.setState({'playing': false});
            await controller.lifecycle(JsUiLifecycle.pause);
          case 'dispatch':
            await controller.dispatch(
              Map<String, Object?>.from(message['event']! as Map),
            );
          case 'setState':
            await controller.setState(
              Map<String, Object?>.from(message['patch']! as Map),
            );
          default:
            throw FormatException('Unknown preview command: $command');
        }
        if (controller.error != null) throw StateError('${controller.error}');
      }
      _emit({'type': 'result', 'requestId': requestId, 'ok': true});
    } catch (error) {
      _emit({
        'type': 'result',
        'requestId': requestId,
        'ok': false,
        'error': '$error',
      });
      _emit({'type': 'error', 'error': '$error'});
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: Text('等待 Vue 加载 MJS 插件')));
    }
    return Scaffold(
      body: JsUiView.network(
        key: ObjectKey(controller),
        url: _url!,
        initialProps: _props,
        controller: controller,
        features: _features,
        uiPlugins: _plugins,
        cacheEnabled: false,
        onFirstRender: () {
          final loaded = _loaded;
          if (loaded != null && !loaded.isCompleted) loaded.complete();
        },
        errorBuilder: (_, error) {
          final loaded = _loaded;
          if (loaded != null && !loaded.isCompleted) {
            loaded.completeError(error);
          }
          return Center(child: SelectableText('$error'));
        },
      ),
    );
  }
}
