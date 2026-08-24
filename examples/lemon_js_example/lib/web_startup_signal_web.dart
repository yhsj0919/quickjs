import 'package:web/web.dart' as web;

/// Exposes a deterministic first-frame signal to browser smoke tests.
void markWebStartupReady() {
  web.document.documentElement?.setAttribute('data-flutter-ready', 'true');
}
