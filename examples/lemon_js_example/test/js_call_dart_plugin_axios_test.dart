@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js.dart';

final class _FileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    return ByteData.sublistView(await File(key).readAsBytes());
  }
}

void main() {
  test('js-call-dart plugin axiosGet reads webpage content', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html><body>QuickJS Axios Page</body></html>');
      await request.response.close();
    });
    final origin = 'http://${server.address.address}:${server.port}';
    final pluginSource = await File(
      'assets/js/js_call_dart_plugin.mjs',
    ).readAsString();
    final plugin = QuickjsPlugin.singleFile(
      id: 'assetApi',
      version: '1.0.0',
      source: pluginSource,
      exports: const <String>['axiosGet'],
    );
    final engine = await Quickjs.create(
      options: QuickjsRuntimeOptions(
        mounts: <QuickjsHostMount>[
          QuickjsAxiosMount(
            assetKey: 'assets/js/axios.js',
            bundle: _FileAssetBundle(),
            allowedOrigins: <String>{origin},
            scriptName: 'example:axios.js',
          ),
          plugin.asMount(),
        ],
      ),
    );
    addTearDown(engine.dispose);

    final result = await engine.invokePlugin('axiosGet', <Object?>[
      '$origin/page',
    ]);

    expect(
      result,
      isA<Map<String, Object?>>()
          .having((value) => value['status'], 'status', 200)
          .having(
            (value) => value['preview'],
            'preview',
            contains('QuickJS Axios Page'),
          ),
    );
  });
}
