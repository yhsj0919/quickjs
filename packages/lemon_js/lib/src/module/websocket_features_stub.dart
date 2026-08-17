import '../runtime/runtime_options.dart';

/// 不支持 WebSocket 宿主后端的平台占位能力。
final class WebSocketFeatures extends JsFeatures {
  /// 报告当前平台不支持 WebSocket 宿主能力。
  WebSocketFeatures({
    Set<String>? allowedOrigins,
    Duration connectTimeout = const Duration(seconds: 15),
    int maxMessageBytes = 1024 * 1024,
    int maxConnections = 16,
    Map<String, String> defaultHeaders = const <String, String>{},
  }) : super(name: 'websocket') {
    throw UnsupportedError(
      'WebSocketFeatures is not supported on this platform',
    );
  }
}
