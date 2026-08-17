@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js.dart';

void main() {
  test('WebSocketFeatures exposes browser-style WebSocket', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.transform(WebSocketTransformer()).listen((socket) {
      socket.listen((message) {
        if (message is String) {
          socket.add('echo:$message');
        } else if (message is List<int>) {
          socket.add(message.map((byte) => byte + 1).toList());
        }
      });
    });

    final origin = 'ws://${server.address.address}:${server.port}';
    final engine = await JsEngine.create(
      features: <JsFeatures>[
        WebSocketFeatures(allowedOrigins: <String>{origin}),
      ],
    );
    addTearDown(engine.dispose);

    expect(
      await engine.run('''
return await new Promise((resolve, reject) => {
  const ws = new WebSocket('$origin/ws');
  const events = [];
  ws.onopen = () => {
    events.push('open:' + ws.readyState + ':' + WebSocket.OPEN);
    ws.send('hello');
  };
  ws.onmessage = (event) => {
    events.push('message:' + event.data);
    ws.close(1000, 'done');
  };
  ws.onerror = (event) => reject(new Error(event.message || 'websocket error'));
  ws.onclose = (event) => resolve([
    events.join(','),
    event.code,
    event.reason,
    event.wasClean,
    ws.readyState,
    WebSocket.CLOSED
  ].join('/'));
});
'''),
      'open:1:1,message:echo:hello/1000/done/true/3/3',
    );

    expect(
      await engine.run('''
return await new Promise((resolve, reject) => {
  const ws = new WebSocket('$origin/binary');
  ws.binaryType = 'arraybuffer';
  ws.onopen = () => ws.send(new Uint8Array([1, 2, 3]));
  ws.onmessage = (event) => {
    const bytes = Array.from(new Uint8Array(event.data));
    ws.close();
    resolve(bytes.join(','));
  };
  ws.onerror = (event) => reject(new Error(event.message || 'websocket error'));
});
'''),
      '2,3,4',
    );

    await expectLater(
      engine.run('''
return await new Promise((resolve, reject) => {
  const ws = new WebSocket('wss://example.com/socket');
  ws.onopen = () => resolve('unexpected');
  ws.onerror = (event) => reject(new Error(event.message || 'websocket error'));
});
'''),
      throwsA(
        isA<JsThrownException>().having(
          (error) => error.message,
          'message',
          contains('origin is not allowed'),
        ),
      ),
    );
  });
}
