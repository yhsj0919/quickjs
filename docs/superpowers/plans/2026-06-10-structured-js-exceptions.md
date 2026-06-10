# 结构化 JavaScript 异常 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `JsException` 在 native 和 web 上稳定暴露 `message/name/stack/fileName/line/column`。

**Architecture:** 保留现有 `\x1eQuickJS_EXCEPTION` sentinel 协议，把 sentinel 后的 payload 升级为 JSON。Dart 侧新增统一解析器，优先把结构化 payload 映射为 `JsException`，无法解析时回退旧纯文本语义。

**Tech Stack:** Dart, Flutter test, QuickJS C API, quickjs-wasi web bridge, PowerShell.

---

### Task 1: 先写结构化异常失败测试

**Files:**
- Modify: `test/quickjs_test.dart`
- Modify: `test/quickjs_consistency_test.dart`

- [x] **Step 1: 在 native/root 测试中断言 Error 字段**

在 `test/quickjs_test.dart` 的 `javascript throw is reported as JsException` 附近新增测试：

```dart
test('javascript Error exposes structured exception fields', () async {
  final engine = await Quickjs.create();
  addTearDown(engine.dispose);

  await expectLater(
    engine.eval('throw new TypeError("structured boom")'),
    throwsA(
      isA<JsException>()
          .having((error) => error.message, 'message', contains('structured boom'))
          .having((error) => error.name, 'name', 'TypeError')
          .having((error) => error.stack, 'stack', isNot(isEmpty)),
    ),
  );
});
```

- [x] **Step 2: 在 native/root 测试中断言非 Error throw 回退**

在同一文件新增：

```dart
test('non Error JavaScript throw still reports a useful JsException', () async {
  final engine = await Quickjs.create();
  addTearDown(engine.dispose);

  await expectLater(
    engine.eval('throw "plain boom"'),
    throwsA(
      isA<JsException>()
          .having((error) => error.message, 'message', contains('plain boom'))
          .having((error) => error.name, 'name', anyOf(isNull, isNotEmpty)),
    ),
  );
});
```

- [x] **Step 3: 在 native/web 一致性测试中断言基础结构字段**

在 `test/quickjs_consistency_test.dart` 的 JS throw 测试附近新增：

```dart
test('maps JavaScript Error details consistently', () async {
  final engine = await Quickjs.create();
  addTearDown(engine.dispose);

  await expectLater(
    engine.eval('throw new TypeError("consistent boom")'),
    throwsA(
      isA<JsException>()
          .having((error) => error.message, 'message', contains('consistent boom'))
          .having((error) => error.name, 'name', 'TypeError')
          .having((error) => error.stack, 'stack', isNot(isEmpty)),
    ),
  );
});
```

- [x] **Step 4: 运行测试确认红灯**

Run:

```powershell
flutter test test\quickjs_test.dart --plain-name "javascript Error exposes structured exception fields"
flutter test test\quickjs_test.dart --plain-name "non Error JavaScript throw still reports a useful JsException"
flutter test test\quickjs_consistency_test.dart --plain-name "maps JavaScript Error details consistently"
```

Expected: 第一个和一致性测试因为 `JsException.name` 尚不存在或为空失败；非 Error 测试至少应能验证旧回退路径。

### Task 2: 实现 Dart 侧结构化异常模型和解析器

**Files:**
- Modify: `lib/src/quickjs_exception.dart`
- Modify: `lib/src/native/quickjs_native_worker.dart`
- Modify: `lib/src/web/quickjs_web_backend.dart`

- [x] **Step 1: 给 `JsException` 增加 `name` 字段**

更新构造函数并保持 `toString()` 兼容：

```dart
const JsException(
  this.message, {
  this.name,
  this.stack,
  this.fileName,
  this.line,
  this.column,
});

final String? name;
```

- [x] **Step 2: 增加 sentinel payload 解析器**

在 `quickjs_exception.dart` 中新增 `parseJsExceptionPayload(String payload)`：

```dart
JsException parseJsExceptionPayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, Object?>) {
      final message = decoded['message'];
      return JsException(
        message is String && message.isNotEmpty ? message : payload,
        name: decoded['name'] is String ? decoded['name'] as String : null,
        stack: decoded['stack'] is String ? decoded['stack'] as String : null,
        fileName: decoded['fileName'] is String
            ? decoded['fileName'] as String
            : null,
        line: _readInt(decoded['line'] ?? decoded['lineNumber']),
        column: _readInt(decoded['column'] ?? decoded['columnNumber']),
      );
    }
  } catch (_) {
    // Legacy payload: the whole payload is the message.
  }
  return JsException(payload);
}
```

- [x] **Step 3: native/web 后端改用解析器**

把当前 `JsException(message)` 替换为：

```dart
final exception = parseJsExceptionPayload(payload);
```

OOM 和 stack overflow 判断继续读取 `exception.message`，命中时仍返回对应资源异常。

- [x] **Step 4: 运行 Dart 目标测试确认仍红或部分绿**

Run:

```powershell
flutter test test\quickjs_test.dart --plain-name "javascript Error exposes structured exception fields"
```

Expected: 如果 bridge 尚未输出 JSON，测试仍因 `name == null` 失败。

### Task 3: 实现 native C bridge JSON payload

**Files:**
- Modify: `native/quickjs_bridge.c`

- [x] **Step 1: 从 exception object 读取字符串和整数属性**

新增 C helper：

```c
static char *qjs_get_string_prop(JSContext *ctx, JSValue obj, const char *name);
static int qjs_get_int_prop(JSContext *ctx, JSValue obj, const char *name, int *out);
```

字符串属性通过 `JS_GetPropertyStr` 和 `JS_ToCString` 读取，读取失败返回 `NULL`。整数属性通过 `JS_ToInt32` 读取，成功返回 1。

- [x] **Step 2: 增加 JSON 字符串转义 helper**

新增 `qjs_json_append_escaped`，至少处理 `\`, `"`, `\n`, `\r`, `\t` 和小于 `0x20` 的控制字符。

- [x] **Step 3: 将 JS exception 编码成 sentinel + JSON**

替换 `JS_IsException(val)` 分支中的纯字符串拼接逻辑，输出：

```json
{"message":"...","name":"...","stack":"...","fileName":"...","line":1,"column":7}
```

缺失字段输出 `null`，message 缺失时使用 `JS_ToCString(ctx, exception)`。

- [x] **Step 4: 运行 native 目标测试确认通过**

Run:

```powershell
flutter test test\quickjs_test.dart --plain-name "javascript Error exposes structured exception fields"
flutter test test\quickjs_test.dart --plain-name "non Error JavaScript throw still reports a useful JsException"
```

Expected: 两个测试 PASS。

### Task 4: 实现 web bridge JSON payload

**Files:**
- Modify: `assets/web/quickjs_bridge.mjs`

- [x] **Step 1: 增加 JS 异常序列化 helper**

新增：

```js
function exceptionToPayload(err) {
  const fallback = err && typeof err === 'object' && 'message' in err
    ? String(err.message)
    : String(err);
  return JSON.stringify({
    message: fallback,
    name: readStringProperty(err, 'name'),
    stack: readStringProperty(err, 'stack'),
    fileName: readStringProperty(err, 'fileName'),
    line: readNumberProperty(err, 'lineNumber'),
    column: readNumberProperty(err, 'columnNumber'),
  });
}
```

- [x] **Step 2: catch 分支输出 sentinel + JSON**

把 `evalOnVm` 的 catch 分支改成：

```js
return `${exceptionSentinel}${exceptionToPayload(err)}`;
```

- [x] **Step 3: 运行一致性目标测试**

Run:

```powershell
flutter test test\quickjs_consistency_test.dart --plain-name "maps JavaScript Error details consistently"
```

Expected: native 平台 PASS；Chrome 目标在完整验证中覆盖。

### Task 5: 完整验证并更新路线图

**Files:**
- Modify: `ROADMAP.md`

- [x] **Step 1: 运行格式化**

Run:

```powershell
dart format lib test
```

Expected: Dart 文件格式化完成。

- [x] **Step 2: 运行验证命令**

Run:

```powershell
flutter analyze
flutter test
flutter test test\quickjs_consistency_test.dart -d chrome
```

Expected: 全部 PASS。

- [x] **Step 3: 更新 `ROADMAP.md`**

把 `0.4.0` 结构化 JS 异常中的 `message/name/stack/fileName/line/column` 标记为完成；如果 location 字段只保证 nullable 暴露，在文字中说明 eval 场景下字段可能为空。

- [x] **Step 4: 最终提交**

Run:

```powershell
git status --short
git add lib/src/quickjs_exception.dart lib/src/native/quickjs_native_worker.dart lib/src/web/quickjs_web_backend.dart native/quickjs_bridge.c assets/web/quickjs_bridge.mjs test/quickjs_test.dart test/quickjs_consistency_test.dart ROADMAP.md docs/superpowers/plans/2026-06-10-structured-js-exceptions.md
git commit -m "feat: structure js exceptions"
```

Expected: 生成一个包含实现、测试、路线图和中文计划的提交。
