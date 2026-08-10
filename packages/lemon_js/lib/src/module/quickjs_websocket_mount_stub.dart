import '../runtime/quickjs_runtime_options.dart';

final class QuickjsWebSocketMount extends QuickjsHostMount {
  QuickjsWebSocketMount({
    Set<String>? allowedOrigins,
    Duration connectTimeout = const Duration(seconds: 15),
    int maxMessageBytes = 1024 * 1024,
    int maxConnections = 16,
    Map<String, String> defaultHeaders = const <String, String>{},
  }) : super(name: 'websocket') {
    throw UnsupportedError(
      'QuickjsWebSocketMount is not supported on this platform',
    );
  }
}
