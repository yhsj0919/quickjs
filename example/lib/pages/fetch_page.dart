import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quickjs/quickjs.dart';

class FetchPage extends StatefulWidget {
  const FetchPage({super.key});

  @override
  State<FetchPage> createState() => _FetchPageState();
}

class _FetchPageState extends State<FetchPage> {
  static const _jsonPlaceholderOrigin = 'https://jsonplaceholder.typicode.com';
  static const _httpBingoOrigin = 'https://httpbingo.org';

  static const List<_FetchScenario> _scenarios = <_FetchScenario>[
    _FetchScenario(
      name: 'Fetch 对象协议',
      description: 'Headers、Request、Response、clone、json、arrayBuffer',
      source: r'''
const headers = new Headers({ accept: 'application/json' });
headers.append('x-example', 'fetch');
const request = new Request('https://jsonplaceholder.typicode.com/todos/1', {
  method: 'GET', headers
});
const response = await fetch(request);
const jsonClone = response.clone();
const bytesClone = response.clone();
const todo = await jsonClone.json();
const bytes = new Uint8Array(await bytesClone.arrayBuffer());
return `PASS status=${response.status}, ok=${response.ok}, id=${todo.id}, bytes=${bytes.length}, content-type=${response.headers.get('content-type')}`;
''',
    ),
    _FetchScenario(
      name: 'HTTP 方法与请求体',
      description: 'POST、PUT、PATCH、DELETE 与自定义 header/body',
      source: r'''
const results = [];
for (const method of ['POST', 'PUT', 'PATCH', 'DELETE']) {
  const url = method === 'POST'
    ? 'https://jsonplaceholder.typicode.com/posts'
    : 'https://jsonplaceholder.typicode.com/posts/1';
  const response = await fetch(url, {
    method,
    headers: { 'content-type': 'application/json', 'x-example': method },
    body: method === 'DELETE' ? null : JSON.stringify({ method, value: 42 })
  });
  if (!response.ok) throw new Error(`${method} returned HTTP ${response.status}`);
  results.push(`${method}:${response.status}`);
}
return `PASS ${results.join(', ')}`;
''',
    ),
    _FetchScenario(
      name: '重定向协议',
      description: 'redirect: follow、manual、error 与 redirected/url',
      source: r'''
const url = 'https://httpbingo.org/redirect-to?url=%2Fget';
const followed = await fetch(url, { redirect: 'follow' });
const manual = await fetch(url, { redirect: 'manual' });
let errorMode = false;
try {
  await fetch(url, { redirect: 'error' });
} catch (_) {
  errorMode = true;
}
const manualOk = (manual.status >= 300 && manual.status < 400) ||
  (manual.status === 0 && manual.type === 'opaqueredirect');
if (!followed.redirected || !manualOk || !errorMode) {
  throw new Error(`Unexpected redirect result: follow=${followed.redirected}, manual=${manual.status}/${manual.type}, error=${errorMode}`);
}
return `PASS follow=${followed.status}/${followed.redirected}, manual=${manual.status}/${manual.type}, error=${errorMode}, url=${followed.url}`;
''',
    ),
    _FetchScenario(
      name: 'Mount 自定义配置',
      description: 'defaultHeaders、请求覆盖、origin allowlist',
      source: r'''
const response = await fetch('https://httpbingo.org/anything', {
  headers: { 'x-request-value': 'from-javascript' }
});
const contentType = response.headers.get('content-type') || '';
if (!response.ok || !contentType.includes('application/json')) {
  const body = await response.text();
  throw new Error(`HTTP ${response.status} ${contentType}: ${body.slice(0, 120)}`);
}
const payload = await response.json();
const headers = payload.headers || {};
return `PASS default=${headers['X-Quickjs-Example'] || headers['x-quickjs-example']}, request=${headers['X-Request-Value'] || headers['x-request-value']}`;
''',
    ),
    _FetchScenario(
      name: 'XHR / Axios 响应协议',
      description: 'readyState、事件、header、responseType=json',
      source: r'''
return await new Promise((resolve, reject) => {
  const xhr = new XMLHttpRequest();
  const states = [];
  xhr.onreadystatechange = () => states.push(xhr.readyState);
  xhr.open('POST', 'https://jsonplaceholder.typicode.com/posts');
  xhr.responseType = 'json';
  xhr.timeout = 10000;
  xhr.setRequestHeader('content-type', 'application/json');
  xhr.onload = () => resolve(`PASS status=${xhr.status}, id=${xhr.response.id}, states=${states.join(',')}, content-type=${xhr.getResponseHeader('content-type')}`);
  xhr.onerror = () => reject(new Error('XHR network error'));
  xhr.ontimeout = () => reject(new Error('XHR timeout'));
  xhr.send(JSON.stringify({ title: 'QuickJS', axios: true }));
});
''',
    ),
    _FetchScenario(
      name: 'XHR 控制协议',
      description: 'abort、loadend 与常量状态',
      source: r'''
return await new Promise((resolve, reject) => {
  const xhr = new XMLHttpRequest();
  const events = [];
  xhr.open('GET', 'https://httpbingo.org/delay/1');
  xhr.onabort = () => events.push('abort');
  xhr.onloadend = () => resolve(`PASS events=${events.join(',')}, state=${xhr.readyState}, DONE=${XMLHttpRequest.DONE}`);
  xhr.onerror = () => reject(new Error('XHR network error'));
  xhr.send();
  xhr.abort();
});
''',
    ),
    _FetchScenario(
      name: '真实 Axios 1.6.2',
      description: 'UMD asset、GET、POST、404、timeout、AbortController cancel',
      source: r'''
const get = await axios.get('https://jsonplaceholder.typicode.com/todos/1');
const post = await axios.post('https://jsonplaceholder.typicode.com/posts', {
  title: 'QuickJS', value: 42
});
let statusError = false;
try {
  await axios.get('https://jsonplaceholder.typicode.com/not-found');
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
const cancelResult = await cancelled;
if (!statusError || !timeoutError || !cancelResult) {
  throw new Error(`Axios compatibility failed: status=${statusError}, timeout=${timeoutError}, cancel=${cancelResult}`);
}
return `PASS Axios ${axios.VERSION}, GET=${get.status}/${get.data.id}, POST=${post.status}/${post.data.id}, 404=${statusError}, timeout=${timeoutError}, cancel=${cancelResult}`;
''',
    ),
  ];

  Quickjs? _quickjs;
  bool _disposed = false;
  bool _busy = false;
  String _status = '正在创建启用 Fetch/XHR 的 runtime...';
  final Map<String, String> _results = <String, String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _status = '正在创建启用 Fetch/XHR 的 runtime...';
      _results.clear();
    });
    try {
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();
      final axiosSource = await rootBundle.loadString('assets/js/axios.js');
      final quickjs = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsFetchMount(
              allowedOrigins: const <String>{
                _jsonPlaceholderOrigin,
                _httpBingoOrigin,
              },
              maxRedirects: 5,
              maxRequestBytes: 1024 * 1024,
              maxResponseBytes: 10 * 1024 * 1024,
              timeout: const Duration(seconds: 15),
              defaultHeaders: const <String, String>{
                'x-quickjs-example': 'from-mount',
              },
            ),
          ],
          environmentPatches: <QuickjsHostScript>[
            QuickjsHostScript(
              name: 'example:axios.js',
              source: axiosSource,
              globals: const <String>['axios'],
            ),
          ],
        ),
      );
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }
      setState(() {
        _quickjs = quickjs;
        _busy = false;
        _status = 'runtime 已就绪：Fetch/XHR + Axios 1.6.2';
      });
    } catch (error) {
      if (!mounted || _disposed) return;
      setState(() {
        _busy = false;
        _status = '创建失败：$error';
      });
    }
  }

  Future<void> _runScenario(_FetchScenario scenario) async {
    final quickjs = _quickjs;
    if (quickjs == null) return;
    setState(() {
      _busy = true;
      _status = '正在验证：${scenario.name}';
      _results[scenario.name] = 'RUNNING';
    });
    try {
      final result = await quickjs.evalAsync(
        scenario.source,
        name: 'example:fetch-${scenario.name}.js',
      );
      if (!mounted || _disposed) return;
      setState(() {
        _results[scenario.name] = result;
        _status = '${scenario.name} 已完成';
      });
    } catch (error) {
      if (!mounted || _disposed) return;
      setState(() {
        _results[scenario.name] = 'FAIL $error';
        _status = '${scenario.name} 执行失败';
      });
    } finally {
      if (mounted && !_disposed) setState(() => _busy = false);
    }
  }

  Future<void> _runAll() async {
    for (final scenario in _scenarios) {
      if (!mounted || _disposed) return;
      await _runScenario(scenario);
    }
    if (mounted && !_disposed) {
      setState(() => _status = '全部 Fetch/XHR 协议验证完成');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_quickjs?.dispose() ?? Future<void>.value());
    _quickjs = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _quickjs != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Fetch / XHR 协议测试')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(_status),
          const SizedBox(height: 8),
          const Text(
            'Native 与 Web 使用同一套 JS API；Web 请求仍受浏览器 CORS 限制。'
            '同步 XHR、cookie jar 和上传进度不在当前兼容范围。',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                onPressed: _busy || !hasRuntime ? null : _runAll,
                child: const Text('运行全部协议'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _createRuntime,
                child: const Text('重建 runtime'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final scenario in _scenarios)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      scenario.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(scenario.description),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonal(
                        onPressed: _busy || !hasRuntime
                            ? null
                            : () => _runScenario(scenario),
                        child: const Text('运行'),
                      ),
                    ),
                    if (_results[scenario.name] case final result?) ...<Widget>[
                      const SizedBox(height: 8),
                      SelectableText(result),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final class _FetchScenario {
  const _FetchScenario({
    required this.name,
    required this.description,
    required this.source,
  });

  final String name;
  final String description;
  final String source;
}
