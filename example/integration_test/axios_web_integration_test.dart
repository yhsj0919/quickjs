import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quickjs/quickjs.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('runs bundled Axios through QuickjsFetchMount on Web', (
    tester,
  ) async {
    expect(kIsWeb, isTrue, reason: 'Run this test with -d chrome');
    final axiosSource = await rootBundle.loadString('assets/js/axios.js');
    final engine = await Quickjs.create(
      options: QuickjsRuntimeOptions(
        mounts: <QuickjsHostMount>[
          QuickjsFetchMount(
            allowedOrigins: const <String>{'https://httpbingo.org'},
            timeout: const Duration(seconds: 15),
          ),
        ],
        environmentPatches: <QuickjsHostScript>[
          QuickjsHostScript.js(
            name: 'test:axios.js',
            source: axiosSource,
            globals: const <String>['axios'],
          ),
        ],
      ),
    );
    addTearDown(engine.dispose);

    expect(
      await engine.evalAsync(r'''
const get = await axios.get('https://httpbingo.org/get');
const post = await axios.post('https://httpbingo.org/post', {
  source: 'quickjs', value: 42
});
let statusError = false;
try {
  await axios.get('https://httpbingo.org/status/404');
} catch (error) {
  statusError = error.isAxiosError && error.response && error.response.status === 404;
}
let timeoutError = false;
try {
  await axios.get('https://httpbingo.org/delay/1', { timeout: 20 });
} catch (error) {
  timeoutError = error.code === 'ECONNABORTED';
}
const controller = new AbortController();
const cancelled = axios.get('https://httpbingo.org/delay/1', {
  signal: controller.signal
}).then(() => false, (error) => axios.isCancel(error));
controller.abort();
const redirect = await axios.get(
  'https://httpbingo.org/redirect-to?url=%2Fget'
);
return [
  axios.VERSION,
  get.status,
  post.status,
  post.data.json.source,
  post.data.json.value,
  statusError,
  timeoutError,
  await cancelled,
  redirect.status,
  redirect.request.responseURL.endsWith('/get')
].join('/');
'''),
      '1.6.2/200/200/quickjs/42/true/true/true/200/true',
    );
  });
}
