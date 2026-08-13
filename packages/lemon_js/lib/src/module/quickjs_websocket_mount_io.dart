import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../diagnostics/quickjs_exception.dart';
import '../runtime/quickjs_runtime_options.dart';

const _webSocketProviderName = 'websocket.dispatch';

final class WebSocketFeatures extends JsFeatures {
  factory WebSocketFeatures({
    Set<String>? allowedOrigins,
    Duration connectTimeout = const Duration(seconds: 15),
    int maxMessageBytes = 1024 * 1024,
    int maxConnections = 16,
    Map<String, String> defaultHeaders = const <String, String>{},
  }) {
    if (connectTimeout <= Duration.zero) {
      throw ArgumentError.value(
        connectTimeout,
        'connectTimeout',
        'must be positive',
      );
    }
    if (maxMessageBytes < 0) {
      throw ArgumentError.value(
        maxMessageBytes,
        'maxMessageBytes',
        'must not be negative',
      );
    }
    if (maxConnections <= 0) {
      throw ArgumentError.value(
        maxConnections,
        'maxConnections',
        'must be positive',
      );
    }

    final origins = allowedOrigins == null || allowedOrigins.isEmpty
        ? null
        : Set<String>.unmodifiable(allowedOrigins.map(_normalizeAllowedOrigin));
    final state = _WebSocketFeaturesState(
      allowedOrigins: origins,
      connectTimeout: connectTimeout,
      maxMessageBytes: maxMessageBytes,
      maxConnections: maxConnections,
      defaultHeaders: Map<String, String>.unmodifiable(defaultHeaders),
    );
    return WebSocketFeatures._(
      allowedOrigins: origins,
      connectTimeout: connectTimeout,
      maxMessageBytes: maxMessageBytes,
      maxConnections: maxConnections,
      defaultHeaders: Map<String, String>.unmodifiable(defaultHeaders),
      provider: JsProvider.dart(
        name: _webSocketProviderName,
        debugName: 'host:websocket.dispatch',
        implementation: JsProviderImplementation.platform,
        callback: state.dispatch,
      ),
    );
  }

  WebSocketFeatures._({
    required this.allowedOrigins,
    required this.connectTimeout,
    required this.maxMessageBytes,
    required this.maxConnections,
    required this.defaultHeaders,
    required JsProvider provider,
  }) : super(
         name: 'websocket',
         scripts: <JsScript>[
           JsScript.js(
             name: 'host:websocket.js',
             globals: const <String>['WebSocket'],
             source: _webSocketHostScript(_webSocketProviderName),
           ),
         ],
         providers: <JsProvider>[provider],
       );

  final Set<String>? allowedOrigins;
  final Duration connectTimeout;
  final int maxMessageBytes;
  final int maxConnections;
  final Map<String, String> defaultHeaders;
}

final class _WebSocketFeaturesState {
  _WebSocketFeaturesState({
    required this.allowedOrigins,
    required this.connectTimeout,
    required this.maxMessageBytes,
    required this.maxConnections,
    required this.defaultHeaders,
  });

  final Set<String>? allowedOrigins;
  final Duration connectTimeout;
  final int maxMessageBytes;
  final int maxConnections;
  final Map<String, String> defaultHeaders;
  final Map<int, _WebSocketConnection> _connections =
      <int, _WebSocketConnection>{};
  int _nextId = 1;

  Future<Object?> dispatch(
    List<Object?> args,
    JsProviderContext context,
  ) async {
    if (args.length != 1 || args.single is! Map) {
      throw const JsValueConversionException(
        'QuickJS WebSocket provider expects one command object',
      );
    }
    final command = Map<Object?, Object?>.from(args.single! as Map);
    switch ('${command['op'] ?? ''}') {
      case 'connect':
        return _connect(command, context);
      case 'next':
        return _connectionFor(command).next(context);
      case 'send':
        _connectionFor(command).send(command['data'], maxMessageBytes);
        return null;
      case 'close':
        await _connectionFor(command).close(
          code: _optionalInt(command['code']),
          reason: command['reason'] == null ? null : '${command['reason']}',
        );
        return null;
      case 'release':
        final id = _requiredId(command);
        await _connections.remove(id)?.close();
        return null;
      default:
        throw JsValueConversionException(
          'QuickJS WebSocket command is invalid: ${command['op']}',
        );
    }
  }

  Future<Object?> _connect(
    Map<Object?, Object?> command,
    JsProviderContext context,
  ) async {
    if (_connections.length >= maxConnections) {
      throw StateError(
        'QuickJS WebSocket exceeded $maxConnections open connections',
      );
    }
    final uri = _parseWebSocketUri(command['url']);
    if (!_isAllowedOrigin(allowedOrigins, uri)) {
      throw JsValueConversionException(
        'QuickJS WebSocket origin is not allowed: ${_webSocketOrigin(uri)}',
      );
    }
    final protocols = _normalizeProtocols(command['protocols']);
    context.throwIfCancelled();

    WebSocket socket;
    try {
      socket = await WebSocket.connect(
        uri.toString(),
        protocols: protocols,
        headers: defaultHeaders.isEmpty ? null : defaultHeaders,
      ).timeout(connectTimeout);
    } on TimeoutException {
      throw StateError('QuickJS WebSocket timed out after $connectTimeout');
    } on WebSocketException catch (error) {
      throw StateError('QuickJS WebSocket connection error: ${error.message}');
    } on SocketException catch (error) {
      throw StateError('QuickJS WebSocket network error: ${error.message}');
    }
    if (socket.readyState == WebSocket.closed) {
      throw StateError('QuickJS WebSocket closed during connection');
    }
    context.throwIfCancelled();

    final id = _nextId++;
    final connection = _WebSocketConnection(id, socket, () {
      _connections.remove(id);
    });
    _connections[id] = connection;
    connection.start(maxMessageBytes);
    unawaited(
      context.cancelled.then((_) async {
        await _connections.remove(id)?.close();
      }),
    );
    return <String, Object?>{
      'id': id,
      'url': uri.toString(),
      'protocol': socket.protocol ?? '',
      'extensions': '',
    };
  }

  _WebSocketConnection _connectionFor(Map<Object?, Object?> command) {
    final id = _requiredId(command);
    final connection = _connections[id];
    if (connection == null) {
      throw JsValueConversionException(
        'QuickJS WebSocket connection is not open: $id',
      );
    }
    return connection;
  }
}

final class _WebSocketConnection {
  _WebSocketConnection(this.id, this.socket, this.onDone);

  final int id;
  final WebSocket socket;
  final void Function() onDone;
  final Queue<Map<String, Object?>> _events = Queue<Map<String, Object?>>();
  final Queue<Completer<Map<String, Object?>>> _waiters =
      Queue<Completer<Map<String, Object?>>>();
  StreamSubscription<Object?>? _subscription;
  bool _done = false;

  void start(int maxMessageBytes) {
    _subscription = socket.listen(
      (message) {
        if (message is String) {
          if (utf8.encode(message).length > maxMessageBytes) {
            _addError(
              'QuickJS WebSocket message exceeds $maxMessageBytes bytes',
            );
            unawaited(close(code: WebSocketStatus.messageTooBig));
            return;
          }
          _addEvent(<String, Object?>{'type': 'message', 'data': message});
          return;
        }
        if (message is List<int>) {
          if (message.length > maxMessageBytes) {
            _addError(
              'QuickJS WebSocket message exceeds $maxMessageBytes bytes',
            );
            unawaited(close(code: WebSocketStatus.messageTooBig));
            return;
          }
          _addEvent(<String, Object?>{
            'type': 'message',
            'data': Uint8List.fromList(message),
          });
          return;
        }
        _addError('QuickJS WebSocket received unsupported message');
      },
      onError: (Object error) {
        _addError('QuickJS WebSocket error: $error');
      },
      onDone: () {
        _finish(
          code: socket.closeCode ?? WebSocketStatus.noStatusReceived,
          reason: socket.closeReason ?? '',
        );
      },
      cancelOnError: false,
    );
  }

  Future<Map<String, Object?>> next(JsProviderContext context) {
    if (_events.isNotEmpty) {
      return Future<Map<String, Object?>>.value(_events.removeFirst());
    }
    final completer = Completer<Map<String, Object?>>();
    _waiters.add(completer);
    unawaited(
      context.cancelled.then((_) {
        if (_waiters.remove(completer) && !completer.isCompleted) {
          completer.completeError(
            context.cancellationReason ??
                StateError('QuickJS WebSocket wait was cancelled'),
          );
        }
        unawaited(close());
      }),
    );
    return completer.future;
  }

  void send(Object? data, int maxMessageBytes) {
    if (socket.readyState != WebSocket.open) {
      throw StateError('QuickJS WebSocket is not open');
    }
    if (data is String) {
      if (utf8.encode(data).length > maxMessageBytes) {
        throw JsValueConversionException(
          'QuickJS WebSocket send exceeds $maxMessageBytes bytes',
        );
      }
      socket.add(data);
      return;
    }
    if (data is Uint8List) {
      if (data.length > maxMessageBytes) {
        throw JsValueConversionException(
          'QuickJS WebSocket send exceeds $maxMessageBytes bytes',
        );
      }
      socket.add(data);
      return;
    }
    throw const JsValueConversionException(
      'QuickJS WebSocket send data must be a string, ArrayBuffer, or Uint8Array',
    );
  }

  Future<void> close({int? code, String? reason}) async {
    await socket.close(code, reason);
    await _subscription?.cancel();
    _finish(
      code: code ?? socket.closeCode ?? WebSocketStatus.normalClosure,
      reason: reason ?? socket.closeReason ?? '',
    );
  }

  void _addError(String message) {
    _addEvent(<String, Object?>{'type': 'error', 'message': message});
  }

  void _finish({required int code, required String reason}) {
    if (_done) {
      return;
    }
    _done = true;
    _addEvent(<String, Object?>{
      'type': 'close',
      'code': code,
      'reason': reason,
      'wasClean': code == WebSocketStatus.normalClosure,
    });
    onDone();
  }

  void _addEvent(Map<String, Object?> event) {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(event);
      return;
    }
    _events.add(event);
  }
}

Uri _parseWebSocketUri(Object? value) {
  final uri = Uri.tryParse('${value ?? ''}');
  if (uri == null ||
      (uri.scheme != 'ws' && uri.scheme != 'wss') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw JsValueConversionException(
      'QuickJS WebSocket URL must be an absolute WS(S) URL',
    );
  }
  return uri;
}

bool _isAllowedOrigin(Set<String>? allowedOrigins, Uri uri) {
  return allowedOrigins == null ||
      allowedOrigins.contains(_webSocketOrigin(uri));
}

String _normalizeAllowedOrigin(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'ws' && uri.scheme != 'wss') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError.value(
      value,
      'allowedOrigins',
      'must contain exact WS(S) origins such as wss://api.example.com',
    );
  }
  return _webSocketOrigin(uri);
}

String _webSocketOrigin(Uri uri) {
  final defaultPort = uri.scheme == 'ws' ? 80 : 443;
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}

List<String>? _normalizeProtocols(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value.isEmpty ? null : <String>[value];
  }
  if (value is List) {
    final protocols = <String>[];
    for (final item in value) {
      final protocol = '$item';
      if (protocol.isEmpty || protocols.contains(protocol)) {
        throw const JsValueConversionException(
          'QuickJS WebSocket protocols must be non-empty and unique',
        );
      }
      protocols.add(protocol);
    }
    return protocols.isEmpty ? null : protocols;
  }
  throw const JsValueConversionException(
    'QuickJS WebSocket protocols must be a string or array',
  );
}

int _requiredId(Map<Object?, Object?> command) {
  final value = command['id'];
  if (value is num) {
    return value.toInt();
  }
  throw const JsValueConversionException(
    'QuickJS WebSocket command requires a connection id',
  );
}

int? _optionalInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toInt();
  }
  throw const JsValueConversionException(
    'QuickJS WebSocket close code must be a number',
  );
}

String _webSocketHostScript(String providerName) {
  final encodedProviderName = jsonEncode(providerName);
  return '''
(() => {
  const provider = globalThis.__quickjsHostProviders[$encodedProviderName];
  const CONNECTING = 0;
  const OPEN = 1;
  const CLOSING = 2;
  const CLOSED = 3;

  const normalizeBinary = (data) => {
    if (data instanceof ArrayBuffer) return new Uint8Array(data);
    if (ArrayBuffer.isView(data)) {
      return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
    }
    return data;
  };

  class QuickjsMessageEvent {
    constructor(type, init = {}) {
      this.type = type;
      this.data = init.data;
      this.target = init.target || null;
      this.currentTarget = init.target || null;
    }
  }

  class QuickjsCloseEvent {
    constructor(type, init = {}) {
      this.type = type;
      this.code = init.code || 1005;
      this.reason = init.reason || '';
      this.wasClean = Boolean(init.wasClean);
      this.target = init.target || null;
      this.currentTarget = init.target || null;
    }
  }

  class QuickjsWebSocket {
    constructor(url, protocols = []) {
      this.url = String(url);
      this.protocol = '';
      this.extensions = '';
      this.binaryType = 'arraybuffer';
      this.bufferedAmount = 0;
      this.readyState = CONNECTING;
      this.onopen = null;
      this.onmessage = null;
      this.onerror = null;
      this.onclose = null;
      this._listeners = Object.create(null);
      this._id = null;
      this._released = false;
      this._connect(protocols);
    }

    addEventListener(type, callback, options) {
      if (typeof callback !== 'function') return;
      (this._listeners[type] || (this._listeners[type] = [])).push({
        callback,
        once: Boolean(options && options.once),
      });
    }

    removeEventListener(type, callback) {
      const listeners = this._listeners[type];
      if (listeners) {
        this._listeners[type] = listeners.filter((entry) => entry.callback !== callback);
      }
    }

    dispatchEvent(event) {
      event.target = this;
      event.currentTarget = this;
      const handler = this['on' + event.type];
      if (typeof handler === 'function') handler.call(this, event);
      const listeners = (this._listeners[event.type] || []).slice();
      this._listeners[event.type] = (this._listeners[event.type] || [])
        .filter((entry) => !entry.once);
      for (const entry of listeners) entry.callback.call(this, event);
      return true;
    }

    send(data) {
      if (this.readyState === CONNECTING) {
        throw new Error('InvalidStateError: WebSocket is still connecting');
      }
      if (this.readyState !== OPEN) {
        return;
      }
      provider({ op: 'send', id: this._id, data: normalizeBinary(data) })
        .catch((error) => this._fail(error));
    }

    close(code = 1000, reason = '') {
      if (this.readyState === CLOSING || this.readyState === CLOSED) return;
      this.readyState = CLOSING;
      if (this._id === null) {
        this.readyState = CLOSED;
        this.dispatchEvent(new QuickjsCloseEvent('close', {
          code,
          reason: String(reason),
          wasClean: true,
          target: this,
        }));
        return;
      }
      provider({ op: 'close', id: this._id, code, reason: String(reason) })
        .catch((error) => this._fail(error));
    }

    async _connect(protocols) {
      try {
        const payload = await provider({
          op: 'connect',
          url: this.url,
          protocols: Array.isArray(protocols) ? protocols.map(String) : protocols == null ? [] : [String(protocols)],
        });
        if (this.readyState !== CONNECTING) {
          await provider({ op: 'release', id: payload.id });
          return;
        }
        this._id = payload.id;
        this.url = payload.url || this.url;
        this.protocol = payload.protocol || '';
        this.extensions = payload.extensions || '';
        this.readyState = OPEN;
        this.dispatchEvent({ type: 'open', target: this, currentTarget: this });
        this._pump();
      } catch (error) {
        this._fail(error);
      }
    }

    async _pump() {
      while (this.readyState === OPEN || this.readyState === CLOSING) {
        let event;
        try {
          event = await provider({ op: 'next', id: this._id });
        } catch (error) {
          this._fail(error);
          return;
        }
        if (!event) continue;
        if (event.type === 'message') {
          let data = event.data;
          if (data instanceof Uint8Array) {
            const copy = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
            data = this.binaryType === 'arraybuffer' ? copy : new Uint8Array(copy);
          }
          this.dispatchEvent(new QuickjsMessageEvent('message', { data, target: this }));
        } else if (event.type === 'error') {
          this.dispatchEvent({ type: 'error', message: event.message || '', target: this, currentTarget: this });
        } else if (event.type === 'close') {
          this.readyState = CLOSED;
          this.dispatchEvent(new QuickjsCloseEvent('close', {
            code: event.code,
            reason: event.reason,
            wasClean: event.wasClean,
            target: this,
          }));
          this._release();
          return;
        }
      }
    }

    _fail(error) {
      if (this.readyState === CLOSED) return;
      this.readyState = CLOSED;
      this.dispatchEvent({ type: 'error', error, message: String(error), target: this, currentTarget: this });
      this.dispatchEvent(new QuickjsCloseEvent('close', {
        code: 1006,
        reason: '',
        wasClean: false,
        target: this,
      }));
      this._release();
    }

    _release() {
      if (this._released || this._id === null) return;
      this._released = true;
      provider({ op: 'release', id: this._id }).catch(() => {});
    }
  }

  Object.assign(QuickjsWebSocket, { CONNECTING, OPEN, CLOSING, CLOSED });
  Object.assign(QuickjsWebSocket.prototype, { CONNECTING, OPEN, CLOSING, CLOSED });

  Object.defineProperty(globalThis, 'WebSocket', {
    value: QuickjsWebSocket,
    configurable: true,
    enumerable: false,
    writable: true,
  });
})();
''';
}
