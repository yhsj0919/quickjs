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
        if (request.uri.path == '/redirect') {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, '/echo');
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
            'defaultHeader': request.headers.value('x-default-test'),
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
              defaultHeaders: const <String, String>{
                'x-default-test': 'from-mount',
              },
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
  payload.defaultHeader,
  cloneBytes.length > 0,
  response.bodyUsed
].join('/');
'''),
        '200/true/quickjs/POST/hello/from-js/from-mount/true/true',
      );

      expect(
        await engine.evalAsync('''
const request = new Request('$origin/redirect', { redirect: 'follow' });
const response = await fetch(request);
const payload = await response.json();
return [response.status, response.redirected, response.url, payload.defaultHeader].join('/');
'''),
        '200/true/$origin/echo/from-mount',
      );

      expect(
        await engine.evalAsync('''
const headers = new Headers({ accept: 'application/json' });
headers.append('x-request-test', 'page-scenario');
const request = new Request('$origin/echo', { method: 'GET', headers });
const response = await fetch(request);
const jsonClone = response.clone();
const bytesClone = response.clone();
const payload = await jsonClone.json();
const bytes = new Uint8Array(await bytesClone.arrayBuffer());
return [response.status, response.ok, payload.method, bytes.length > 0].join('/');
'''),
        '200/true/GET/true',
      );

      await expectLater(
        engine.evalAsync('''
return await fetch('$origin/redirect', { redirect: 'error' });
'''),
        throwsA(
          isA<JsException>().having(
            (error) => error.message,
            'message',
            contains('redirect:error'),
          ),
        ),
      );

      expect(
        await engine.evalAsync('''
return await new Promise((resolve, reject) => {
  const xhr = new XMLHttpRequest();
  const states = [];
  xhr.onreadystatechange = () => states.push(xhr.readyState);
  xhr.open('POST', '$origin/echo');
  xhr.responseType = 'json';
  xhr.setRequestHeader('x-request-test', 'axios-style');
  xhr.onload = () => resolve([
    xhr.status,
    xhr.response.method,
    xhr.response.body,
    xhr.response.requestHeader,
    xhr.getResponseHeader('x-fetch-test'),
    states.join(',')
  ].join('/'));
  xhr.onerror = () => reject(new Error('XHR failed'));
  xhr.send('xhr-body');
});
'''),
        '200/POST/xhr-body/axios-style/quickjs/1,2,3,4',
      );

      expect(
        await engine.evalAsync('''
return await new Promise((resolve, reject) => {
  const xhr = new XMLHttpRequest();
  const events = [];
  xhr.open('GET', '$origin/echo');
  xhr.onabort = () => events.push('abort');
  xhr.onloadend = () => resolve([
    events.join(','), xhr.readyState, XMLHttpRequest.DONE
  ].join('/'));
  xhr.onerror = () => reject(new Error('XHR failed'));
  xhr.send();
  xhr.abort();
});
'''),
        'abort/4/4',
      );

      expect(
        await engine.evalAsync('''
return await new Promise((resolve, reject) => {
  const controller = new AbortController();
  const xhr = new XMLHttpRequest();
  xhr.open('GET', '$origin/echo');
  controller.signal.addEventListener('abort', () => xhr.abort());
  xhr.onabort = () => resolve([
    controller.signal.aborted,
    xhr.readyState,
    XMLHttpRequest.DONE
  ].join('/'));
  xhr.onerror = () => reject(new Error('XHR failed'));
  xhr.send();
  controller.abort('axios-cancel');
});
'''),
        'true/4/4',
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
