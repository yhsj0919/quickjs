import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

/// Fetch API 全量演示：覆盖 QuickjsFetchMount 暴露的请求、响应与重定向语义。
class FetchPage extends StatefulWidget {
  const FetchPage({super.key});

  @override
  State<FetchPage> createState() => _FetchPageState();
}

class _FetchPageState extends State<FetchPage> {
  /// httpbin 兼容镜像；httpbin.org 常 503，示例改用 httpbingo.org。
  static const String _httpbin = 'https://httpbingo.org';
  static const String _jsonPlaceholder = 'https://jsonplaceholder.typicode.com';

  Quickjs? _quickjs;
  bool _disposed = false;
  bool _busy = false;
  String _status = '正在创建启用 Fetch 的 runtime...';
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _status = '正在创建启用 Fetch 的 runtime...';
      _log.clear();
    });
    try {
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();
      final quickjs = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsFetchMount(
              allowedOrigins: const <String>{
                _httpbin,
                _jsonPlaceholder,
              },
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
        _status = 'runtime 已就绪：允许 httpbingo.org / jsonplaceholder.typicode.com';
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '创建失败：$error';
      });
    }
  }

  Quickjs _requireRuntime() {
    final quickjs = _quickjs;
    if (quickjs == null) {
      throw JsRuntimeClosedException('QuickJS runtime is not ready');
    }
    return quickjs;
  }

  Future<void> _runAllTests() async {
    for (final testCase in _testCases) {
      await _runCase(testCase);
      if (!mounted || _disposed) {
        return;
      }
    }
  }

  static const String _fetchDebugReaderScript = '''
const debug = globalThis.__lastFetchDebug;
return debug == null ? '' : JSON.stringify(debug, null, 2);
''';

  Future<void> _runCase(_FetchTestCase testCase) async {
    setState(() {
      _busy = true;
      _status = '正在运行：${testCase.label}';
    });
    try {
      final result = await _requireRuntime().evalAsync(
        _instrumentedScript(testCase.script),
      );
      if (!mounted || _disposed) {
        return;
      }
      final passed = testCase.matches(result);
      if (!passed) {
        await _printFailureDetails(
          testCase,
          actual: result,
        );
      }
      setState(() {
        _busy = false;
        _status = passed ? '${testCase.label} 通过' : '${testCase.label} 失败';
        _log.insert(
          0,
          passed
              ? '✓ ${testCase.label}\n  $result'
              : '✗ ${testCase.label}\n  期望：${testCase.expectedLabel}\n  实际：$result',
        );
      });
    } catch (error, stackTrace) {
      if (!mounted || _disposed) {
        return;
      }
      final passed = testCase.expectError &&
          testCase.errorMatches(error.toString());
      if (!passed) {
        await _printFailureDetails(
          testCase,
          error: error,
          stackTrace: stackTrace,
        );
      }
      setState(() {
        _busy = false;
        _status = passed ? '${testCase.label} 通过' : '${testCase.label} 失败';
        _log.insert(
          0,
          passed
              ? '✓ ${testCase.label}\n  $error'
              : '✗ ${testCase.label}\n  期望错误：${testCase.expectedErrorContains}\n  实际：$error',
        );
      });
    }
  }

  String _instrumentedScript(String script) {
    return '''
(() => {
  globalThis.__lastFetchDebug = null;
  const recordFetchDebug = (entry) => {
    globalThis.__lastFetchDebug = entry;
  };
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input, init = {}) => {
    const response = await originalFetch(input, init);
    const headers = Object.create(null);
    response.headers.forEach((value, key) => {
      headers[key] = value;
    });
    const text = await response.text();
    recordFetchDebug({
      kind: 'fetch',
      input: typeof input === 'string' ? input : String(input?.url || input),
      init: init ?? {},
      url: response.url,
      status: response.status,
      statusText: response.statusText,
      ok: response.ok,
      redirected: response.redirected,
      headers,
      body: text,
    });
    return new Response(text, {
      status: response.status,
      statusText: response.statusText,
      headers: response.headers,
      url: response.url,
      redirected: response.redirected,
    });
  };
  if (typeof XMLHttpRequest === 'function') {
    const originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function(body) {
      const xhr = this;
      const previousOnload = xhr.onload;
      xhr.onload = function(event) {
        let responseValue = xhr.response;
        if (typeof responseValue === 'object' && responseValue != null) {
          try {
            responseValue = JSON.stringify(responseValue);
          } catch (_) {
            responseValue = String(responseValue);
          }
        }
        recordFetchDebug({
          kind: 'xhr',
          method: xhr._quickjsDebugMethod ?? 'GET',
          url: xhr.responseURL || xhr._quickjsDebugUrl || '',
          status: xhr.status,
          statusText: xhr.statusText,
          responseType: xhr.responseType,
          responseText: xhr.responseText,
          response: responseValue,
          requestBody: body == null ? null : String(body),
        });
        if (typeof previousOnload === 'function') {
          return previousOnload.call(xhr, event);
        }
      };
      return originalSend.call(xhr, body);
    };
    const originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url, ...rest) {
      this._quickjsDebugMethod = String(method);
      this._quickjsDebugUrl = String(url);
      return originalOpen.call(this, method, url, ...rest);
    };
  }
})();

$script
''';
  }

  Future<void> _printFailureDetails(
    _FetchTestCase testCase, {
    String? actual,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final buffer = StringBuffer()
      ..writeln('[FetchTest] ${testCase.label} 失败')
      ..writeln('期望：${testCase.expectedLabel}');
    if (actual != null) {
      buffer.writeln('实际返回值：$actual');
    }
    if (error != null) {
      buffer.writeln('异常：${_describeError(error)}');
      if (stackTrace != null) {
        buffer.writeln('Dart stackTrace：$stackTrace');
      }
    }
    try {
      final captured = await _requireRuntime().evalAsync(_fetchDebugReaderScript);
      if (captured.isNotEmpty) {
        buffer
          ..writeln('最近 HTTP 响应：')
          ..writeln(captured);
      }
    } catch (debugError) {
      buffer.writeln('读取 HTTP 调试信息失败：$debugError');
    }
    debugPrint(buffer.toString());
  }

  String _describeError(Object error) {
    if (error is JsException) {
      return [
        '${error.runtimeType}',
        'name: ${error.name ?? '<null>'}',
        'message: ${error.message}',
        if (error.stack != null) 'stack: ${error.stack}',
        if (error.fileName != null) 'fileName: ${error.fileName}',
        if (error.line != null) 'line: ${error.line}',
        if (error.column != null) 'column: ${error.column}',
      ].join('\n');
    }
    if (error is QuickjsException) {
      return '${error.runtimeType}: ${error.message}';
    }
    return error.toString();
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
      appBar: AppBar(title: const Text('Fetch')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              'Native: HttpClient · Web: browser fetch · '
              'Web 仍受浏览器 CORS 限制',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _runAllTests,
                  child: const Text('运行全部'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _createRuntime,
                  child: const Text('重建 runtime'),
                ),
                for (final testCase in _testCases)
                  OutlinedButton(
                    onPressed: _busy || !hasRuntime
                        ? null
                        : () => unawaited(_runCase(testCase)),
                    child: Text(testCase.label),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _log.isEmpty
                    ? const Center(child: Text('尚未运行测试'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _log.length,
                        separatorBuilder: (_, _) => const Divider(height: 16),
                        itemBuilder: (context, index) {
                          return SelectableText(_log[index]);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_FetchTestCase> get _testCases => <_FetchTestCase>[
    _FetchTestCase(
      label: 'POST + clone',
      script: '''
const response = await fetch('$_httpbin/post', {
  method: 'POST',
  headers: { 'x-request-test': 'from-js' },
  body: 'hello',
});
const clone = response.clone();
const payload = await response.json();
const cloneBytes = new Uint8Array(await clone.arrayBuffer());
return [
  response.status,
  response.ok,
  payload.headers['X-Request-Test'],
  payload.data,
  cloneBytes.length > 0,
  response.bodyUsed,
].join('/');
''',
      expected: '200/true/from-js/hello/true/true',
    ),
    _FetchTestCase(
      label: '全局 API',
      script: '''
return [
  typeof fetch,
  typeof Headers,
  typeof Request,
  typeof Response,
  typeof AbortController,
  typeof AbortSignal,
  typeof FormData,
  typeof URLSearchParams,
  typeof Blob,
  typeof ReadableStream,
  typeof XMLHttpRequest,
].join('/');
''',
      expected:
          'function/function/function/function/function/function/function/function/function/function/function',
    ),
    _FetchTestCase(
      label: 'Response 静态方法',
      script: '''
const jsonResponse = Response.json({ ok: true });
const redirect = Response.redirect('$_httpbin/get', 307);
const error = Response.error();
return [
  jsonResponse.headers.get('content-type'),
  redirect.status,
  error.type,
  await jsonResponse.json().then((value) => value.ok),
].join('/');
''',
      expected: 'application/json/307/error/true',
    ),
    _FetchTestCase(
      label: 'URLSearchParams',
      script: '''
const response = await fetch('$_httpbin/post', {
  method: 'POST',
  body: new URLSearchParams({ a: '1', b: '2' }),
});
const payload = await response.json();
return payload.data;
''',
      expected: 'a=1&b=2',
    ),
    _FetchTestCase(
      label: 'FormData',
      script: '''
const form = new FormData();
form.append('name', 'quickjs');
const response = await fetch('$_httpbin/post', {
  method: 'POST',
  body: form,
});
const payload = await response.json();
return payload.form.name;
''',
      expected: 'quickjs',
    ),
    _FetchTestCase(
      label: 'blob / bytes',
      script: '''
const textResponse = await fetch('$_httpbin/post', {
  method: 'POST',
  body: 'blob-body',
});
const blob = await textResponse.blob();
const echoed = JSON.parse(await blob.text()).data;
const bytes = await Response.json({ n: 42 }).bytes();
return [echoed, bytes.length].join('/');
''',
      expected: 'blob-body/8',
    ),
    _FetchTestCase(
      label: 'AbortSignal',
      script: '''
const controller = new AbortController();
controller.abort();
try {
  await fetch('$_httpbin/get', { signal: controller.signal });
  return 'not-aborted';
} catch (error) {
  return error.name;
}
''',
      expected: 'AbortError',
    ),
    _FetchTestCase(
      label: 'XMLHttpRequest',
      script: '''
const xhr = new XMLHttpRequest();
const result = await new Promise((resolve, reject) => {
  xhr.open('POST', '$_httpbin/post');
  xhr.setRequestHeader('x-demo', 'xhr');
  xhr.responseType = 'json';
  xhr.onload = async () => {
    const response = xhr.toFetchResponse();
    const text = await response.text();
    resolve([
      xhr.status,
      xhr.response.data,
      response.ok,
      text.includes('xhr-body'),
    ].join('/'));
  };
  xhr.onerror = () => reject(new Error('xhr failed'));
  xhr.send('xhr-body');
});
return result;
''',
      expected: '200/xhr-body/true/true',
    ),
    _FetchTestCase(
      label: 'redirect follow',
      script: '''
const response = await fetch('$_httpbin/redirect/1');
return [
  response.status,
  response.redirected,
  response.url.includes('/get'),
].join('/');
''',
      expected: '200/true/true',
    ),
    _FetchTestCase(
      label: 'redirect manual',
      script: '''
const response = await fetch('$_httpbin/redirect/1', { redirect: 'manual' });
const location = response.headers.get('location') || '';
return [
  response.status,
  response.redirected,
  location.includes('/get'),
].join('/');
''',
      expected: '302/false/true',
    ),
    _FetchTestCase(
      label: 'redirect error',
      script: '''
try {
  await fetch('$_httpbin/redirect/1', { redirect: 'error' });
  return 'no-error';
} catch (error) {
  return error.name;
}
''',
      expected: 'TypeError',
    ),
    _FetchTestCase(
      label: 'JSON GET',
      script: '''
const response = await fetch('$_jsonPlaceholder/todos/1');
const todo = await response.json();
return [response.status, response.ok, todo.id, todo.title.length > 0].join('/');
''',
      expectedPrefix: '200/true/1/true',
    ),
    _FetchTestCase(
      label: 'Request 对象',
      script: '''
const request = new Request('$_httpbin/get', {
  headers: { 'X-Demo': 'request-object' },
});
const response = await fetch(request);
const payload = await response.json();
return payload.headers['X-Demo'];
''',
      expected: 'request-object',
    ),
    _FetchTestCase(
      label: 'redirect 越界',
      script: '''
await fetch('$_httpbin/redirect-to?url=https://example.com/');
return 'unexpected-success';
''',
      expectError: true,
      expectedErrorContains: 'origin is not allowed',
    ),
    _FetchTestCase(
      label: 'origin 拒绝',
      script: '''
await fetch('https://example.com/');
return 'unexpected-success';
''',
      expectError: true,
      expectedErrorContains: 'origin is not allowed',
    ),
  ];
}

final class _FetchTestCase {
  const _FetchTestCase({
    required this.label,
    required this.script,
    this.expected,
    this.expectedPrefix,
    this.expectError = false,
    this.expectedErrorContains,
  });

  final String label;
  final String script;
  final String? expected;
  final String? expectedPrefix;
  final bool expectError;
  final String? expectedErrorContains;

  String get expectedLabel => expected ?? expectedPrefix ?? expectedErrorContains ?? '';

  bool matches(String result) {
    if (expected != null) {
      return result == expected;
    }
    if (expectedPrefix != null) {
      return result.startsWith(expectedPrefix!);
    }
    return false;
  }

  bool errorMatches(String message) {
    final needle = expectedErrorContains;
    if (needle == null) {
      return false;
    }
    return message.contains(needle);
  }
}
