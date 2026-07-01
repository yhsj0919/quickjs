import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiHostCapabilitiesPage extends StatefulWidget {
  const QuickjsUiHostCapabilitiesPage({super.key});

  static const String path = 'assets/quickjs_ui/host_capabilities_page.mjs';

  @override
  State<QuickjsUiHostCapabilitiesPage> createState() =>
      _QuickjsUiHostCapabilitiesPageState();
}

class _QuickjsUiHostCapabilitiesPageState
    extends State<QuickjsUiHostCapabilitiesPage> {
  late final QuickjsUiController _controller;
  late final QuickjsUiHostCapabilities _capabilities;
  late final List<QuickjsHostMount> _mounts;
  late final Map<String, Object?> _initialProps;
  String _status = '等待 JS 页面加载';

  @override
  void initState() {
    super.initState();
    _controller = QuickjsUiController(
      onConsole: (event) {
        debugPrint('quickjs_ui console.${event.level.name}: ${event.text}');
      },
    )..addListener(_handleControllerChanged);
    _capabilities = QuickjsUiHostCapabilities(
      groups: <QuickjsUiCapabilityGroup>[
        QuickjsUiCapabilityGroup.system(
          options: const QuickjsUiHostCapabilityOptions(
            enabled: <QuickjsUiHostCapability>{
              QuickjsUiHostCapability.toast,
              QuickjsUiHostCapability.confirm,
              QuickjsUiHostCapability.dialog,
              QuickjsUiHostCapability.snackbar,
              QuickjsUiHostCapability.bottomSheet,
              QuickjsUiHostCapability.navigation,
              QuickjsUiHostCapability.storage,
              QuickjsUiHostCapability.nativeCall,
            },
          ),
          handlers: QuickjsUiHostApiHandlers(
            onToast: (message, options) {
              _setStatus('toast: $message');
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(message)));
              }
              return <String, Object?>{
                'shown': true,
                'message': message,
                'source': options['source'],
              };
            },
            onConfirm: (message, options) {
              _setStatus('confirm: $message');
              return true;
            },
            onDialog: _handleDialog,
            onSnackbar: _handleSnackbar,
            onBottomSheet: _handleBottomSheet,
            onNavigationIntent: _handleNavigationIntent,
            onNativeCall: _handleNativeCall,
          ),
          storage: const <String, Object?>{'boot': 'ready'},
        ),
        _customEchoGroup(),
      ],
    );
    _mounts = _capabilities.mounts;
    _initialProps = <String, Object?>{
      'methods': _capabilities.methods.map((method) => method.name).toList()
        ..sort(),
    };
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    unawaited(
      _controller
          .lifecycle('dispose', render: false)
          .whenComplete(_controller.dispose),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI 宿主能力')),
      body: Column(
        children: <Widget>[
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_status),
              ),
            ),
          ),
          Expanded(
            child: QuickjsUiView.asset(
              path: QuickjsUiHostCapabilitiesPage.path,
              controller: _controller,
              mounts: _mounts,
              initialProps: _initialProps,
              loadingBuilder: (_) =>
                  const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, error) => Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  'QuickJS UI host capabilities error: $error',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<Object?> _handleNavigationIntent(Map<String, Object?> intent) async {
    final route = intent['route'];
    if (route is! String) {
      throw ArgumentError('navigation intent route must be a string');
    }
    final params = intent['params'] is Map
        ? (intent['params']! as Map).map(
            (key, value) => MapEntry<String, Object?>('$key', value),
          )
        : const <String, Object?>{};
    final builder = _hostCapabilityRouteRegistry[route];
    if (builder == null) {
      throw StateError('navigation route "$route" is not registered');
    }

    _setStatus('navigationIntent: $route');
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (context) => builder(context, params),
        settings: RouteSettings(name: route, arguments: params),
      ),
    );
    return <String, Object?>{'route': route, 'result': result};
  }

  Future<Object?> _handleNativeCall(String method, Object? payload) async {
    _setStatus('nativeCall: $method');
    return <String, Object?>{'method': method, 'payload': payload, 'ok': true};
  }

  Future<Object?> _handleDialog(Map<String, Object?> data) async {
    _setStatus('dialog');
    final result = await showDialog<Object?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${data['title'] ?? '宿主 Dialog'}'),
          content: _buildHostContent(
            context,
            data,
            fallback: '${data['message'] ?? data['text'] ?? ''}',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    return <String, Object?>{'accepted': result == true};
  }

  Future<Object?> _handleSnackbar(Map<String, Object?> data) async {
    final message = '${data['message'] ?? '来自 snackbar 的消息'}';
    _setStatus('snackbar: $message');
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
    return <String, Object?>{'shown': true, 'message': message};
  }

  Future<Object?> _handleBottomSheet(Map<String, Object?> data) async {
    _setStatus('bottomSheet');
    final result = await showModalBottomSheet<Object?>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '${data['title'] ?? '宿主 BottomSheet'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _buildHostContent(
                context,
                data,
                fallback: '${data['message'] ?? data['text'] ?? ''}',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop('closed'),
                child: const Text('关闭 bottom sheet'),
              ),
            ],
          ),
        );
      },
    );
    return <String, Object?>{'result': result};
  }

  Widget _buildHostContent(
    BuildContext context,
    Map<String, Object?> data, {
    required String fallback,
  }) {
    final content = data['content'];
    if (content is Map) {
      final node = QuickjsUiNode.fromMap(
        content.map((key, value) => MapEntry<String, Object?>('$key', value)),
      );
      return QuickjsUiRenderer(
        onEvent: (_) {},
      ).build(node, buildContext: context);
    }
    return Text(fallback);
  }

  void _setStatus(String status) {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
    });
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

typedef _QuickjsUiHostRouteBuilder =
    Widget Function(BuildContext context, Map<String, Object?> params);

final Map<String, _QuickjsUiHostRouteBuilder> _hostCapabilityRouteRegistry =
    <String, _QuickjsUiHostRouteBuilder>{
      'quickjs-ui.host-capabilities.detail': (context, params) =>
          _HostCapabilityNavigationTargetPage(params: params),
    };

class _HostCapabilityNavigationTargetPage extends StatelessWidget {
  const _HostCapabilityNavigationTargetPage({required this.params});

  final Map<String, Object?> params;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('宿主导航目标页')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('navigationIntent 已通过 route registry 进入此页面。'),
            const SizedBox(height: 12),
            SelectableText('params: $params'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(<String, Object?>{
                  'accepted': true,
                  'source': params['source'],
                });
              },
              child: const Text('返回 structured result'),
            ),
          ],
        ),
      ),
    );
  }
}

QuickjsUiCapabilityGroup _customEchoGroup() {
  return QuickjsUiCapabilityGroup.functions(
    name: 'app-custom',
    namespace: 'app',
    globalName: 'quickjsUiApp',
    functions: <String, Function>{
      'customEcho': (Object? value) => 'echo:$value',
      'add': (num a, num b) => a + b,
    },
  );
}
