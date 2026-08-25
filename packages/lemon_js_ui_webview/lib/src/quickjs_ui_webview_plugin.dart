import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:webview_all/webview_all.dart' as native;

/// JavaScript 导入 WebView 组件和桥接 DSL 时使用的稳定模块名称。
const String jsUiWebViewModuleSpecifier = 'quickjs_ui/webview';

/// `lemon_js_ui` 的跨平台 WebView 插件入口。
final class JsUiWebViewPlugin {
  /// 创建一个作用域独立的 WebView 插件实例。
  ///
  /// 宿主应为需要隔离的 `JsUiView` 显式创建实例；插件包不会在全局保存 WebView
  /// controller 或 bridge 引用。
  JsUiWebViewPlugin() : _broker = _WebViewBroker() {
    _features = JsFeatures(
      name: 'quickjs_ui:plugin:webview',
      modules: const <JsModule>[
        JsModule.asset(
          name: jsUiWebViewModuleSpecifier,
          path: 'packages/lemon_js_ui_webview/js/quickjs_ui_webview.js',
        ),
      ],
      methods: <JsHostMethod>[
        JsHostMethod(
          name: 'quickjs_ui.webview.command',
          implementation: JsHostMethodImplementation.platform,
          callback: (arguments, context) => _broker.command(arguments, context),
        ),
        JsHostMethod(
          name: 'quickjs_ui.webview.nextCall',
          implementation: JsHostMethodImplementation.platform,
          callback: (arguments, context) =>
              _broker.nextCall(arguments, context),
        ),
        JsHostMethod(
          name: 'quickjs_ui.webview.respond',
          implementation: JsHostMethodImplementation.platform,
          callback: (arguments, context) => _broker.respond(arguments, context),
        ),
      ],
    );
    plugin = JsUiPlugin(
      name: 'quickjs_ui:plugin:webview',
      features: <JsFeatures>[_features],
      configure: _configure,
    );
  }

  final _WebViewBroker _broker;
  late final JsFeatures _features;

  /// 可直接传给 `JsUiView.uiPlugins` 的作用域插件描述。
  late final JsUiPlugin plugin;

  void _configure(JsUiComponentRegistry registry) {
    registry.register('WebView', _build);
  }

  Widget _build(JsUiRenderContext context, JsUiNode node) {
    return _JsUiWebViewHost(context: context, node: node, broker: _broker);
  }
}

final class _JsUiWebViewHost extends StatefulWidget {
  const _JsUiWebViewHost({
    required this.context,
    required this.node,
    required this.broker,
  });

  final JsUiRenderContext context;
  final JsUiNode node;
  final _WebViewBroker broker;

  @override
  State<_JsUiWebViewHost> createState() => _JsUiWebViewHostState();
}

final class _JsUiWebViewHostState extends State<_JsUiWebViewHost>
    implements _WebViewEndpoint {
  static const String _channelName = 'LemonJsUiWebView';

  late final native.WebViewController _controller;
  String? _bridgeId;
  String? _loadedSource;

  @override
  void initState() {
    super.initState();
    _controller = native.WebViewController();
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant _JsUiWebViewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _registerBridge();
    final source = _sourceIdentity(widget.node);
    if (source != _loadedSource) {
      unawaited(_load());
    }
    final rules = _rulesOf(widget.node);
    if (rules != _rulesOf(oldWidget.node) && rules != null) {
      unawaited(_applyRules(rules));
    }
  }

  @override
  void dispose() {
    final bridgeId = _bridgeId;
    if (bridgeId != null) {
      widget.broker.unregister(bridgeId, this);
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    await _controller.setJavaScriptMode(
      widget.node.props['javaScriptEnabled'] == false
          ? native.JavaScriptMode.disabled
          : native.JavaScriptMode.unrestricted,
    );
    await _controller.addJavaScriptChannel(
      _channelName,
      onMessageReceived: _onJavaScriptMessage,
    );
    final documentStartSupported = await _controller
        .isUserScriptInjectionSupported(
          native.WebViewUserScriptInjectionTime.documentStart,
        );
    if (documentStartSupported) {
      await _controller.addUserScript(
        native.WebViewUserScript(source: _pageBridgeSource(_channelName)),
      );
      final frameScripts = _frameScriptsOf(widget.node);
      for (final source in frameScripts) {
        await _controller.addUserScript(
          native.WebViewUserScript(source: source, forMainFrameOnly: false),
        );
      }
    }
    await _controller.setNavigationDelegate(
      native.NavigationDelegate(
        onProgress: (progress) => _dispatch('onProgress', <String, Object?>{
          'progress': progress,
        }, sample: true),
        onPageStarted: (url) =>
            _dispatch('onPageStarted', <String, Object?>{'url': url}),
        onPageFinished: (url) async {
          await _installBridge();
          final rules = _rulesOf(widget.node);
          if (rules != null) {
            await _applyRules(rules);
          }
          _dispatch('onPageFinished', <String, Object?>{'url': url});
        },
        onUrlChange: (change) {
          final url = change.url;
          if (url != null) {
            _dispatch('onUrlChanged', <String, Object?>{'url': url});
          }
        },
        onWebResourceError: (error) => _dispatch('onError', <String, Object?>{
          'code': error.errorCode,
          'message': error.description,
          'url': error.url,
        }),
      ),
    );
    final userAgent = widget.node.props['userAgent'];
    if (userAgent is String) {
      await _controller.setUserAgent(userAgent);
    }
    await _controller.enableZoom(widget.node.props['zoomEnabled'] != false);
    _registerBridge();
    await _restoreInitialCookies();
    await _load();
  }

  void _registerBridge() {
    final next = widget.node.props['bridgeId'];
    final bridgeId = next is String && next.isNotEmpty ? next : null;
    if (_bridgeId == bridgeId) {
      return;
    }
    final previous = _bridgeId;
    if (previous != null) {
      widget.broker.unregister(previous, this);
    }
    _bridgeId = bridgeId;
    if (bridgeId != null) {
      widget.broker.register(bridgeId, this);
    }
  }

  Future<void> _restoreInitialCookies() async {
    final cookies = widget.node.props['initialCookies'];
    if (cookies is! List) {
      return;
    }
    final manager = native.WebViewCookieManager();
    for (final value in cookies) {
      final cookie = _stringMap(value);
      if (cookie == null) {
        continue;
      }
      await manager.setCookie(_cookieFromMap(cookie));
    }
  }

  Future<void> _load() async {
    final html = widget.node.props['html'];
    if (html is String) {
      _loadedSource = _sourceIdentity(widget.node);
      await _controller.loadHtmlString(
        html,
        baseUrl: widget.node.props['baseUrl'] as String?,
      );
      return;
    }
    final url = widget.node.props['url'];
    if (url is! String || url.isEmpty) {
      return;
    }
    _loadedSource = _sourceIdentity(widget.node);
    await _controller.loadRequest(
      Uri.parse(url),
      headers: _stringStringMap(widget.node.props['headers']),
    );
  }

  Future<void> _installBridge() {
    return _controller.runJavaScript(_pageBridgeSource(_channelName));
  }

  Future<void> _applyRules(Object rules) async {
    await _installBridge();
    await _controller.runJavaScriptReturningResult(
      'window.__lemonWebView.applyRules(${jsonEncode(rules)})',
    );
  }

  void _onJavaScriptMessage(native.JavaScriptMessage message) {
    Object? decoded;
    try {
      decoded = jsonDecode(message.message);
    } on FormatException {
      _dispatch('onMessage', <String, Object?>{
        'name': 'message',
        'payload': message.message,
      });
      return;
    }
    final map = _stringMap(decoded);
    if (map == null) {
      return;
    }
    final type = map['type'];
    if (type == 'call') {
      final bridgeId = _bridgeId;
      if (bridgeId != null) {
        widget.broker.enqueueCall(bridgeId, map);
      }
      return;
    }
    _dispatch('onMessage', <String, Object?>{
      'name': map['name'] ?? 'message',
      'payload': map['payload'],
    });
  }

  void _dispatch(
    String prop,
    Map<String, Object?> payload, {
    bool sample = false,
  }) {
    final event = JsUiProps.event(widget.node.props[prop]);
    if (event == null) {
      return;
    }
    widget.context.dispatch(
      event,
      payload: payload,
      kind: sample ? JsUiEventKind.sample : JsUiEventKind.command,
      defaultCoalesceKey: sample ? 'WebView:$_bridgeId:$prop' : null,
    );
  }

  @override
  Future<Object?> execute(String method, Map<String, Object?> arguments) async {
    switch (method) {
      case 'reload':
        await _controller.reload();
        return null;
      case 'stop':
        await _controller.runJavaScript('window.stop()');
        return null;
      case 'goBack':
        await _controller.goBack();
        return null;
      case 'goForward':
        await _controller.goForward();
        return null;
      case 'canGoBack':
        return _controller.canGoBack();
      case 'canGoForward':
        return _controller.canGoForward();
      case 'getUrl':
        return _controller.currentUrl();
      case 'getTitle':
        return _controller.getTitle();
      case 'evaluate':
        return _evaluate(_requiredString(arguments, 'source'));
      case 'applyRules':
        return _controller.runJavaScriptReturningResult(
          'window.__lemonWebView.applyRules(${jsonEncode(arguments['rules'])})',
        );
      case 'callPage':
        return _controller.callAsyncJavaScript(
          'return await window.__lemonWebView.callExposed(method, args);',
          arguments: <String, Object?>{
            'method': _requiredString(arguments, 'method'),
            'args': arguments['arguments'],
          },
        );
      case 'getCookies':
        final url =
            arguments['url'] as String? ?? await _controller.currentUrl();
        if (url == null) {
          return const <Object?>[];
        }
        final cookies = await native.WebViewCookieManager().getCookies(
          domain: Uri.parse(url),
        );
        return <Object?>[
          for (final cookie in cookies)
            <String, Object?>{
              'name': cookie.name,
              'value': cookie.value,
              'domain': cookie.domain,
              'path': cookie.path,
            },
        ];
      case 'setCookies':
        final values = arguments['cookies'];
        if (values is! List) {
          throw const FormatException('cookies must be a list');
        }
        final manager = native.WebViewCookieManager();
        for (final value in values) {
          final map = _stringMap(value);
          if (map == null) {
            throw const FormatException('cookie must be an object');
          }
          await manager.setCookie(_cookieFromMap(map));
        }
        return null;
      case 'clearCookies':
        return native.WebViewCookieManager().clearCookies();
      case 'clearCache':
        await _controller.clearCache();
        return null;
      case 'clearLocalStorage':
        await _controller.clearLocalStorage();
        return null;
      case 'loadUrl':
        await _controller.loadRequest(
          Uri.parse(_requiredString(arguments, 'url')),
          headers: _stringStringMap(arguments['headers']),
        );
        return null;
      case 'loadHtml':
        await _controller.loadHtmlString(
          _requiredString(arguments, 'html'),
          baseUrl: arguments['baseUrl'] as String?,
        );
        return null;
    }
    throw UnsupportedError('Unknown WebView command: $method');
  }

  Future<Object?> _evaluate(String source) async {
    try {
      return await _controller.runJavaScriptReturningResult(source);
    } catch (error) {
      final message = error.toString();
      final emptyResult =
          message.contains('returned `null` or `undefined`') ||
          message.contains('returned null or undefined');
      if (emptyResult &&
          (error is ArgumentError || error is PlatformException)) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> respond(Map<String, Object?> response) async {
    await _controller.runJavaScript(
      'window.__lemonWebView.resolveHostCall(${jsonEncode(response)})',
    );
  }

  @override
  Widget build(BuildContext context) {
    return native.WebViewWidget(controller: _controller);
  }
}

abstract interface class _WebViewEndpoint {
  Future<Object?> execute(String method, Map<String, Object?> arguments);

  Future<void> respond(Map<String, Object?> response);
}

final class _WebViewBroker {
  final Map<String, _WebViewEndpoint> _endpoints = <String, _WebViewEndpoint>{};
  final Map<String, List<Map<String, Object?>>> _calls =
      <String, List<Map<String, Object?>>>{};
  final Map<String, Completer<Map<String, Object?>>> _waiters =
      <String, Completer<Map<String, Object?>>>{};

  void register(String id, _WebViewEndpoint endpoint) {
    _endpoints[id] = endpoint;
  }

  void unregister(String id, _WebViewEndpoint endpoint) {
    if (identical(_endpoints[id], endpoint)) {
      _endpoints.remove(id);
    }
    _waiters
        .remove(id)
        ?.completeError(StateError('WebView bridge "$id" was disposed'));
    _calls.remove(id);
  }

  Future<Object?> command(
    List<Object?> args,
    JsHostMethodContext context,
  ) async {
    final id = _argumentString(args, 0, 'bridgeId');
    final method = _argumentString(args, 1, 'method');
    final arguments = args.length > 2
        ? _stringMap(args[2]) ?? const <String, Object?>{}
        : const <String, Object?>{};
    final endpoint = _endpoints[id];
    if (endpoint == null) {
      throw StateError('WebView bridge "$id" is not mounted');
    }
    final result = await endpoint.execute(method, arguments);
    context.throwIfCancelled();
    return result;
  }

  void enqueueCall(String id, Map<String, Object?> call) {
    final waiter = _waiters.remove(id);
    if (waiter != null) {
      waiter.complete(call);
      return;
    }
    _calls.putIfAbsent(id, () => <Map<String, Object?>>[]).add(call);
  }

  Future<Object?> nextCall(
    List<Object?> args,
    JsHostMethodContext context,
  ) async {
    final id = _argumentString(args, 0, 'bridgeId');
    final queued = _calls[id];
    if (queued != null && queued.isNotEmpty) {
      return queued.removeAt(0);
    }
    if (_waiters.containsKey(id)) {
      throw StateError('WebView bridge "$id" already has a listener');
    }
    final completer = Completer<Map<String, Object?>>();
    _waiters[id] = completer;
    final result = await Future.any<Object?>(<Future<Object?>>[
      completer.future,
      context.cancelled.then<Object?>((_) {
        context.throwIfCancelled();
        return null;
      }),
    ]);
    if (identical(_waiters[id], completer)) {
      _waiters.remove(id);
    }
    return result;
  }

  Future<Object?> respond(
    List<Object?> args,
    JsHostMethodContext context,
  ) async {
    final id = _argumentString(args, 0, 'bridgeId');
    final response = args.length > 1 ? _stringMap(args[1]) : null;
    if (response == null) {
      throw const FormatException('WebView response must be an object');
    }
    final endpoint = _endpoints[id];
    if (endpoint == null) {
      throw StateError('WebView bridge "$id" is not mounted');
    }
    await endpoint.respond(response);
    context.throwIfCancelled();
    return null;
  }
}

native.WebViewCookie _cookieFromMap(Map<String, Object?> map) {
  return native.WebViewCookie(
    name: _requiredString(map, 'name'),
    value: _requiredString(map, 'value'),
    domain: _requiredString(map, 'domain'),
    path: map['path'] as String? ?? '/',
  );
}

String _argumentString(List<Object?> args, int index, String name) {
  if (index >= args.length || args[index] is! String) {
    throw FormatException('$name must be a string');
  }
  return args[index]! as String;
}

String _requiredString(Map<String, Object?> map, String name) {
  final value = map[name];
  if (value is! String || value.isEmpty) {
    throw FormatException('$name must be a non-empty string');
  }
  return value;
}

Map<String, Object?>? _stringMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

Map<String, String> _stringStringMap(Object? value) {
  final map = _stringMap(value);
  if (map == null) {
    return const <String, String>{};
  }
  return <String, String>{
    for (final entry in map.entries)
      if (entry.value is String) entry.key: entry.value! as String,
  };
}

String? _sourceIdentity(JsUiNode node) {
  final html = node.props['html'];
  if (html is String) {
    return 'html:${node.props['baseUrl']}:$html';
  }
  final url = node.props['url'];
  return url is String ? 'url:$url' : null;
}

Object? _rulesOf(JsUiNode node) {
  final rules = node.props['rules'];
  return rules == null || rules is JsUndefined ? null : rules;
}

List<String> _frameScriptsOf(JsUiNode node) {
  final value = node.props['frameScripts'];
  if (value is! List) return const <String>[];
  return value
      .whereType<String>()
      .where((source) => source.isNotEmpty)
      .toList();
}

String _pageBridgeSource(String channelName) =>
    '''
(() => {
  if (window.__lemonWebView) return;
  const exposed = new Map();
  const pending = new Map();
  const observedRules = new Map();
  let nextId = 1;
  let observer;
  let observerScheduled = false;
  const channel = window[${jsonEncode(channelName)}];
  const send = value => channel.postMessage(JSON.stringify(value));
  const matches = (root, step) => {
    let values = Array.from(root.querySelectorAll(step.selector));
    if (step.relation === 'child') {
      values = values.filter(value => value.parentElement === root);
    }
    if (Number.isInteger(step.index)) {
      const index = step.index < 0 ? values.length + step.index : step.index;
      values = index >= 0 && index < values.length ? [values[index]] : [];
    }
    return values;
  };
  const select = rule => {
    let roots = [document];
    for (const step of rule.path || []) {
      roots = roots.flatMap(root => matches(root, step));
    }
    return roots;
  };
  const applyOperation = (elements, operation) => {
    for (const element of elements) {
      switch (operation.action) {
        case 'setText': element.textContent = operation.value ?? ''; break;
        case 'setHtml': element.innerHTML = operation.value ?? ''; break;
        case 'replaceText': {
          const find = String(operation.find ?? '');
          const replacement = String(operation.replace ?? '');
          element.textContent = operation.all
            ? element.textContent.split(find).join(replacement)
            : element.textContent.replace(find, replacement);
          break;
        }
        case 'setAttribute':
          if (operation.value == null) element.removeAttribute(operation.name);
          else element.setAttribute(operation.name, String(operation.value));
          break;
        case 'setAttributes':
          for (const [name, value] of Object.entries(operation.attributes || {})) {
            if (value == null) element.removeAttribute(name);
            else element.setAttribute(name, String(value));
          }
          break;
        case 'removeAttribute': element.removeAttribute(operation.name); break;
        case 'setStyle': Object.assign(element.style, operation.styles || {}); break;
        case 'addClass': element.classList.add(operation.value); break;
        case 'removeClass': element.classList.remove(operation.value); break;
        case 'hide': element.style.setProperty('display', 'none', 'important'); break;
        case 'show': element.style.removeProperty('display'); break;
        case 'remove': element.remove(); break;
        case 'replaceElement': element.outerHTML = operation.html ?? ''; break;
        case 'isolate': {
          let current = element;
          while (current && current !== document.body) {
            const parent = current.parentElement;
            if (!parent) break;
            for (const sibling of Array.from(parent.children)) {
              if (sibling === current) continue;
              if (operation.options?.removeOthers) sibling.remove();
              else sibling.style.setProperty('display', 'none', 'important');
            }
            current = parent;
          }
          document.documentElement.style.margin = '0';
          document.body.style.margin = '0';
          if (operation.options?.fillViewport) {
            element.style.width = '100%';
            element.style.maxWidth = 'none';
          }
          if (operation.options?.styles) Object.assign(element.style, operation.options.styles);
          break;
        }
        case 'click': element.click(); break;
        case 'focus': element.focus(); break;
        case 'setValue':
          element.value = operation.value ?? '';
          element.dispatchEvent(new Event('input', { bubbles: true }));
          element.dispatchEvent(new Event('change', { bubbles: true }));
          break;
      }
    }
  };
  const applyRule = rule => {
    const elements = select(rule);
    for (const operation of rule.operations || []) applyOperation(elements, operation);
    return { matched: elements.length, modified: elements.length };
  };
  window.__lemonWebView = {
    applyRules(rules) {
      const list = Array.isArray(rules) ? rules : [rules];
      for (const rule of list) {
        if (rule?.observe) observedRules.set(JSON.stringify(rule), rule);
      }
      if (observedRules.size > 0 && !observer) {
        observer = new MutationObserver(() => {
          if (observerScheduled) return;
          observerScheduled = true;
          setTimeout(() => {
            observerScheduled = false;
            for (const rule of observedRules.values()) applyRule(rule);
          }, 0);
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });
      }
      const results = list.filter(Boolean).map(applyRule);
      return JSON.stringify({ applied: results.length, results });
    },
    expose(name, callback) { exposed.set(name, callback); },
    unexpose(name) { exposed.delete(name); },
    async callExposed(name, args) {
      const callback = exposed.get(name);
      if (!callback) throw new Error(`Page method "\${name}" is not exposed`);
      return await callback(args);
    },
    callHost(method, args) {
      const id = `page-\${nextId++}`;
      send({ type: 'call', id, method, arguments: args });
      return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
    },
    notifyHost(name, payload) { send({ type: 'notify', name, payload }); },
    resolveHostCall(response) {
      const item = pending.get(response.id);
      if (!item) return;
      pending.delete(response.id);
      if (response.error) item.reject(Object.assign(new Error(response.error.message), response.error));
      else item.resolve(response.result);
    }
  };
  window.quickjsHost = {
    call: window.__lemonWebView.callHost,
    notify: window.__lemonWebView.notifyHost,
    expose: window.__lemonWebView.expose,
    unexpose: window.__lemonWebView.unexpose
  };
})();
''';
