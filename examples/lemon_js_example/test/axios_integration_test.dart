@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js.dart';

final class _FileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final path = key.startsWith('packages/') ? '../../$key' : key;
    return ByteData.sublistView(await File(path).readAsBytes());
  }
}

void main() {
  test('runs bundled Axios through FetchFeatures XHR', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path == '/delay') {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (request.uri.path == '/status/404') {
        request.response.statusCode = HttpStatus.notFound;
      }
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'method': request.method,
          'body': body,
          'header': request.headers.value('x-axios-test'),
        }),
      );
      await request.response.close();
    });

    final origin = 'http://${server.address.address}:${server.port}';
    final engine = await JsEngine.create(
      features: <JsFeatures>[
        AxiosFeatures(
          bundle: _FileAssetBundle(),
          allowedOrigins: <String>{origin},
          scriptName: 'test:axios.js',
        ),
      ],
    );
    addTearDown(engine.dispose);

    expect(
      await engine.run('''
const get = await axios.get('$origin/echo', {
  headers: { 'x-axios-test': 'get' }
});
const post = await axios.post('$origin/echo', { value: 42 }, {
  headers: { 'x-axios-test': 'post' }
});
let statusError = false;
try { await axios.get('$origin/status/404'); }
catch (error) {
  statusError = error.isAxiosError && error.response.status === 404;
}
let timeoutError = false;
try { await axios.get('$origin/delay', { timeout: 20 }); }
catch (error) { timeoutError = error.code === 'ECONNABORTED'; }
const controller = new AbortController();
const cancelled = axios.get('$origin/delay', { signal: controller.signal })
  .then(() => false, (error) => axios.isCancel(error));
controller.abort();
return [
  axios.VERSION,
  get.status,
  get.data.method,
  get.data.header,
  post.status,
  post.data.method,
  post.data.header,
  JSON.parse(post.data.body).value,
  statusError,
  timeoutError,
  await cancelled
].join('/');
'''),
      '1.6.2/200/GET/get/200/POST/post/42/true/true/true',
    );
  });
}
