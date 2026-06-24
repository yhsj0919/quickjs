@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';

void main() {
  test(
    'QuickjsFetchMount enforces policy and exposes Fetch response APIs',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final requestBody = await utf8.decoder.bind(request).join();
        request.response.headers
          ..contentType = ContentType.json
          ..set('x-fetch-test', 'quickjs');
        request.response.write(
          jsonEncode(<String, Object?>{
            'method': request.method,
            'body': requestBody,
            'requestHeader': request.headers.value('x-request-test'),
          }),
        );
        await request.response.close();
      });

      final origin = 'http://${server.address.address}:${server.port}';
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsFetchMount(
              allowedOrigins: <String>{origin},
              maxResponseBytes: 4096,
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalAsync('''
const response = await fetch('$origin/echo', {
  method: 'POST',
  headers: { 'x-request-test': 'from-js' },
  body: 'hello'
});
const clone = response.clone();
const payload = await response.json();
const cloneBytes = new Uint8Array(await clone.arrayBuffer());
return [
  response.status,
  response.ok,
  response.headers.get('x-fetch-test'),
  payload.method,
  payload.body,
  payload.requestHeader,
  cloneBytes.length > 0,
  response.bodyUsed
].join('/');
'''),
        '200/true/quickjs/POST/hello/from-js/true/true',
      );

      await expectLater(
        engine.evalAsync("return await fetch('https://example.com/');"),
        throwsA(
          isA<JsException>().having(
            (error) => error.message,
            'message',
            contains('origin is not allowed'),
          ),
        ),
      );
    },
  );
}
