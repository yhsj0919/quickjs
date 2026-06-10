# Structured JavaScript Exceptions Design

## Context

Roadmap item `0.4.0` requires JavaScript exceptions to expose structured fields:
`message`, `stack`, `name`, `fileName`, `line`, and `column`.

The public `JsException` already exposes `message`, `stack`, `fileName`, `line`,
and `column`, but it does not expose `name`. Native and web currently carry JS
exceptions through the same sentinel string protocol:
`\x1eQuickJS_EXCEPTION<text>`.

## Chosen Approach

Use a structured JSON payload behind the existing JS exception sentinel.

The bridge result remains prefixed with `\x1eQuickJS_EXCEPTION`, but the payload
after the sentinel becomes JSON when structured exception data is available:

```json
{
  "message": "boom",
  "name": "Error",
  "stack": "Error: boom\n    at ...",
  "fileName": "<eval>",
  "line": 1,
  "column": 7
}
```

Dart parsing stays backward compatible:

- If the sentinel payload is valid JSON object data, map it to `JsException`.
- If parsing fails, treat the payload as the legacy exception message string.
- Existing OOM and stack overflow classification continues to take precedence
  so resource limit failures keep their stable public exception types.

## Public API

Extend `JsException` with a nullable `name` field:

```dart
final class JsException implements QuickjsException {
  const JsException(
    this.message, {
    this.name,
    this.stack,
    this.fileName,
    this.line,
    this.column,
  });
}
```

`message` remains the primary display text and `toString()` continues returning
`message` to avoid breaking existing callers.

## Native Bridge

When `JS_Eval` returns a JS exception:

1. Call `JS_GetException(ctx)`.
2. Read properties from the exception object:
   `message`, `name`, `stack`, `fileName`, `lineNumber`, and `columnNumber`.
3. Fall back to `JS_ToCString(ctx, exception)` for `message` if structured
   extraction fails or if the thrown value is not a normal Error object.
4. Emit the sentinel plus JSON payload.

QuickJS may omit some location fields for eval source. Missing or non-numeric
fields are encoded as `null` or omitted and become nullable Dart fields.

## Web Bridge

When `quickjs-wasi` throws during `vm.evalCode(code)`:

1. Extract `message`, `name`, `stack`, `fileName`, `lineNumber`, and
   `columnNumber` from the caught error when present.
2. Fall back to `String(err)` for `message`.
3. Emit the same sentinel plus JSON payload as native.

This preserves native/web semantic alignment while allowing implementation
differences in the underlying QuickJS binding.

## Dart Mapping

Add a shared parser for sentinel payloads used by both native and web backends:

- Input: payload after `\x1eQuickJS_EXCEPTION`.
- Output: `JsException`.
- JSON object keys are optional.
- `lineNumber` and `columnNumber` are accepted as aliases for `line` and
  `column` to tolerate bridge variation.
- Legacy plain text payloads still produce `JsException(payload)`.

OOM and stack overflow checks should inspect the parsed message before falling
back to `JsException`, preserving `JsOutOfMemoryException` and
`JsStackOverflowException`.

## Tests

Use TDD and add failing tests before production changes:

1. Native/root test: `throw new TypeError("boom")` maps to `JsException` with:
   `message` containing `boom`, `name == "TypeError"`, and non-empty `stack`.
2. Native/root test: throwing a non-Error value, such as `throw "boom"`, still
   maps to `JsException` with a useful `message` and nullable optional fields.
3. Native/web consistency test: the same `TypeError` exposes `message`, `name`,
   and `stack` consistently on both platforms.
4. Location fields are asserted loosely: if present, `fileName` is non-empty and
   `line` / `column` are positive integers. They are not required to be present
   because QuickJS eval and quickjs-wasi do not guarantee identical source
   location metadata.

## Out Of Scope

- Source maps and stack remapping.
- Custom source file names for `eval`.
- Module stack traces.
- Promise rejection structuring.
- Handle-based non-convertible exception values.
