import 'dart:io';

/// Serves [example/assets/quickjs_ui] over HTTP for network UI page development.
///
/// Example:
/// ```bash
/// dart run tool/quickjs_ui_dev_server.dart
/// ```
Future<void> main() async {
  final root = Directory('example/assets/quickjs_ui');
  if (!root.existsSync()) {
    stderr.writeln('Missing directory: ${root.path}');
    exitCode = 1;
    return;
  }

  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8765);
  stdout.writeln('Serving ${root.path} at http://127.0.0.1:8765/');
  stdout.writeln(
    'Example: http://127.0.0.1:8765/bundle_counter/pages/main.mjs',
  );

  await for (final request in server) {
    await _handleRequest(root, request);
  }
}

Future<void> _handleRequest(Directory root, HttpRequest request) async {
  try {
    final requested = _requestedPath(request.uri);
    final rootPath = root.absolute.path;
    final file = File('$rootPath${Platform.pathSeparator}$requested');
    final resolvedPath = file.absolute.path;
    if (!resolvedPath.startsWith(rootPath) || !file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final stat = await file.stat();
    final etag = 'W/"${stat.modified.millisecondsSinceEpoch}-${stat.size}"';
    if (request.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
      request.response.statusCode = HttpStatus.notModified;
      await request.response.close();
      return;
    }

    request.response.headers.set(HttpHeaders.etagHeader, etag);
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    request.response.headers.set(
      HttpHeaders.accessControlAllowOriginHeader,
      '*',
    );
    request.response.headers.contentType = _contentType(file.path);
    await request.response.addStream(file.openRead());
    await request.response.close();
  } catch (error) {
    request.response.statusCode = HttpStatus.internalServerError;
    request.response.write('$error');
    await request.response.close();
  }
}

String _requestedPath(Uri uri) {
  final segments = uri.pathSegments.where((segment) {
    return segment.isNotEmpty && segment != '.' && segment != '..';
  }).toList();
  if (segments.isEmpty) {
    return 'index.mjs';
  }
  return segments.join(Platform.pathSeparator);
}

ContentType _contentType(String path) {
  final normalized = path.toLowerCase();
  if (normalized.endsWith('.mjs') || normalized.endsWith('.js')) {
    return ContentType('application', 'javascript', charset: 'utf-8');
  }
  if (normalized.endsWith('.json')) {
    return ContentType.json;
  }
  return ContentType.binary;
}
