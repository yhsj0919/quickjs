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
      final origin = 'http://${server.address.address}:${server.port}';
      server.listen((request) async {
        if (request.uri.path == '/redirect') {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set('location', '$origin/echo');
          await request.response.close();
          return;
        }
        if (request.uri.path == '/redirect-external') {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set('location', 'https://example.com/');
          await request.response.close();
          return;
        }
        final requestBody = await utf8.decoder.bind(request).join();
        request.response.headers
          ..contentType = ContentType.json
          ..set('x-fetch-test', 'quickjs');
        request.response.write(
          jsonEncode(<String, Object?>{
            'method': request.method,
            'body': requestBody,
            'requestHeader': request.headers.value('x-request-test'),
            'contentType': request.headers.contentType?.mimeType,
          }),
        );
        await request.response.close();
      });

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

      expect(
        await engine.evalAsync('''
const response = await fetch('$origin/echo', {
  method: 'POST',
  body: 'hello',
});
const payload = await response.json();
return payload.contentType;
'''),
        'text/plain',
      );

      expect(
        await engine.evalAsync('''
const types = [
  typeof Request,
  typeof AbortController,
  typeof AbortSignal,
  typeof FormData,
  typeof URLSearchParams,
  typeof Blob,
  typeof ReadableStream,
].join('/');
const jsonResponse = Response.json({ ok: true });
const redirect = Response.redirect('$origin/redirect', 307);
const error = Response.error();
const params = new URLSearchParams({ a: '1', b: '2' });
const form = new FormData();
form.append('name', 'quickjs');
const request = new Request('$origin/form', {
  method: 'POST',
  body: params,
});
const formRequest = new Request('$origin/form', {
  method: 'POST',
  body: form,
});
const [paramsResponse, formResponse] = await Promise.all([
  fetch(request),
  fetch(formRequest),
]);
const paramsPayload = await paramsResponse.json();
const formPayload = await formResponse.json();
const blobResponse = await fetch('$origin/echo', {
  method: 'POST',
  body: 'blob-body',
});
const blob = await blobResponse.blob();
const bytes = await Response.json({ n: 42 }).bytes();
const controller = new AbortController();
controller.abort();
let aborted = 'false';
try {
  await fetch('$origin/echo', { signal: controller.signal });
} catch (error) {
  aborted = error.name;
}
return [
  types,
  jsonResponse.headers.get('content-type'),
  redirect.status,
  error.type,
  paramsPayload.body,
  formPayload.body.includes('quickjs') ? 'form-ok' : 'form-bad',
  blob.size,
  bytes.length,
  aborted,
].join('/');
'''),
        'function/function/function/function/function/function/function/'
        'application/json/307/error/a=1&b=2/form-ok/84/8/AbortError',
      );

      expect(
        await engine.evalAsync('''
const followed = await fetch('$origin/redirect');
const manual = await fetch('$origin/redirect', { redirect: 'manual' });
let errorName = '';
try {
  await fetch('$origin/redirect', { redirect: 'error' });
} catch (error) {
  errorName = error.name;
}
return [
  followed.status,
  followed.redirected,
  followed.url.endsWith('/echo'),
  manual.status,
  manual.redirected,
  manual.headers.get('location').endsWith('/echo'),
  errorName,
].join('/');
'''),
        '200/true/true/302/false/true/TypeError',
      );

      await expectLater(
        engine.evalAsync("return await fetch('$origin/redirect-external');"),
        throwsA(
          isA<JsException>().having(
            (error) => error.message,
            'message',
            contains('origin is not allowed'),
          ),
        ),
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

      expect(
        await engine.evalAsync('''
const xhr = new XMLHttpRequest();
const result = await new Promise((resolve, reject) => {
  xhr.open('POST', '$origin/echo');
  xhr.setRequestHeader('x-request-test', 'xhr');
  xhr.responseType = 'json';
  xhr.onload = () => {
    const response = xhr.toFetchResponse();
  resolve([
    xhr.status,
    xhr.response.method,
    xhr.response.body,
    xhr.response.requestHeader,
    response.ok,
    response.status,
    response.url.endsWith('/echo'),
  ].join('/'));
  };
  xhr.onerror = () => reject(new Error('xhr failed'));
  xhr.send('xhr-body');
});
return result;
'''),
        '200/POST/xhr-body/xhr/true/200/true',
      );
    },
  );
}
