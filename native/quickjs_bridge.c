#include "quickjs_bridge.h"

#ifndef QUICKJS_BRIDGE_BUILD
#define QUICKJS_BRIDGE_BUILD
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "quickjs-libc.h"
#include "quickjs.h"

typedef struct QuickjsPendingCallback {
  int64_t request_id;
  JSValue resolve;
  JSValue reject;
  struct QuickjsPendingCallback *next;
} QuickjsPendingCallback;

struct QuickjsRuntime {
  JSRuntime *rt;
  JSContext *ctx;
  /* Dart worker 写入这个共享标记，interrupt handler 读取后中断 JS。 */
  volatile int32_t *cancel_flag;
  QuickjsHostCallback host_callback;
  QuickjsPendingCallback *pending_callbacks;
  JSValue async_promise;
};

/* 单次 eval 的中断状态。timeout 和 stop 都通过 QuickJS interrupt handler 收敛。 */
typedef struct QuickjsEvalInterrupt {
  int timed_out;
  int cancelled;
  int has_deadline;
  clock_t deadline;
} QuickjsEvalInterrupt;

static char *qjs_strdup(const char *src) {
  size_t len;
  char *copy;
  if (!src) {
    return NULL;
  }
  len = strlen(src);
  copy = (char *)malloc(len + 1);
  if (!copy) {
    return NULL;
  }
  memcpy(copy, src, len + 1);
  return copy;
}

typedef struct QjsStringBuilder {
  char *data;
  size_t length;
  size_t capacity;
  int failed;
} QjsStringBuilder;

static char *qjs_exception_to_payload(JSContext *ctx, JSValue exception);
static char *qjs_value_to_string(JSContext *ctx, JSValue val);

static void qjs_sb_init(QjsStringBuilder *builder) {
  builder->data = NULL;
  builder->length = 0;
  builder->capacity = 0;
  builder->failed = 0;
}

static int qjs_sb_reserve(QjsStringBuilder *builder, size_t extra) {
  size_t needed;
  size_t capacity;
  char *data;

  if (builder->failed) {
    return 0;
  }
  needed = builder->length + extra + 1;
  if (needed <= builder->capacity) {
    return 1;
  }
  capacity = builder->capacity ? builder->capacity : 128;
  while (capacity < needed) {
    capacity *= 2;
  }
  data = (char *)realloc(builder->data, capacity);
  if (!data) {
    free(builder->data);
    builder->data = NULL;
    builder->length = 0;
    builder->capacity = 0;
    builder->failed = 1;
    return 0;
  }
  builder->data = data;
  builder->capacity = capacity;
  return 1;
}

static void qjs_sb_append(QjsStringBuilder *builder, const char *text) {
  size_t len;

  if (!text) {
    return;
  }
  len = strlen(text);
  if (!qjs_sb_reserve(builder, len)) {
    return;
  }
  memcpy(builder->data + builder->length, text, len);
  builder->length += len;
  builder->data[builder->length] = '\0';
}

static void qjs_sb_append_char(QjsStringBuilder *builder, char ch) {
  if (!qjs_sb_reserve(builder, 1)) {
    return;
  }
  builder->data[builder->length++] = ch;
  builder->data[builder->length] = '\0';
}

static void qjs_sb_append_json_string(QjsStringBuilder *builder,
                                      const char *text) {
  const unsigned char *cursor;
  char escaped[7];

  qjs_sb_append_char(builder, '"');
  if (text) {
    for (cursor = (const unsigned char *)text; *cursor; cursor++) {
      switch (*cursor) {
      case '\\':
        qjs_sb_append(builder, "\\\\");
        break;
      case '"':
        qjs_sb_append(builder, "\\\"");
        break;
      case '\n':
        qjs_sb_append(builder, "\\n");
        break;
      case '\r':
        qjs_sb_append(builder, "\\r");
        break;
      case '\t':
        qjs_sb_append(builder, "\\t");
        break;
      default:
        if (*cursor < 0x20) {
          snprintf(escaped, sizeof(escaped), "\\u%04x", *cursor);
          qjs_sb_append(builder, escaped);
        } else {
          qjs_sb_append_char(builder, (char)*cursor);
        }
        break;
      }
    }
  }
  qjs_sb_append_char(builder, '"');
}

static char *qjs_sb_take(QjsStringBuilder *builder) {
  char *data;

  if (builder->failed) {
    return NULL;
  }
  if (!builder->data && !qjs_sb_reserve(builder, 0)) {
    return NULL;
  }
  data = builder->data;
  builder->data = NULL;
  builder->length = 0;
  builder->capacity = 0;
  return data;
}

static char *qjs_get_string_prop(JSContext *ctx, JSValue obj,
                                 const char *name) {
  JSValue prop;
  const char *str;
  char *copy;

  prop = JS_GetPropertyStr(ctx, obj, name);
  if (JS_IsException(prop) || JS_IsUndefined(prop) || JS_IsNull(prop)) {
    JS_FreeValue(ctx, prop);
    return NULL;
  }
  str = JS_ToCString(ctx, prop);
  if (!str) {
    JS_FreeValue(ctx, prop);
    return NULL;
  }
  copy = qjs_strdup(str);
  JS_FreeCString(ctx, str);
  JS_FreeValue(ctx, prop);
  return copy;
}

static int qjs_get_int_prop(JSContext *ctx, JSValue obj, const char *name,
                            int *out) {
  JSValue prop;
  int32_t value;

  prop = JS_GetPropertyStr(ctx, obj, name);
  if (JS_IsException(prop) || !JS_IsNumber(prop) ||
      JS_ToInt32(ctx, &value, prop) < 0) {
    JS_FreeValue(ctx, prop);
    return 0;
  }
  JS_FreeValue(ctx, prop);
  *out = value;
  return 1;
}

static void qjs_append_json_string_field(QjsStringBuilder *builder,
                                         const char *name, const char *value) {
  qjs_sb_append_json_string(builder, name);
  qjs_sb_append_char(builder, ':');
  if (value) {
    qjs_sb_append_json_string(builder, value);
  } else {
    qjs_sb_append(builder, "null");
  }
}

static void qjs_append_json_int_field(QjsStringBuilder *builder,
                                      const char *name, int has_value,
                                      int value) {
  char number[32];

  qjs_sb_append_json_string(builder, name);
  qjs_sb_append_char(builder, ':');
  if (has_value) {
    snprintf(number, sizeof(number), "%d", value);
    qjs_sb_append(builder, number);
  } else {
    qjs_sb_append(builder, "null");
  }
}

static char *qjs_exception_to_payload(JSContext *ctx, JSValue exception) {
  const char *fallback_str;
  char *fallback = NULL;
  char *message;
  char *name;
  char *stack;
  char *file_name;
  int line = 0;
  int column = 0;
  int has_line;
  int has_column;
  QjsStringBuilder builder;
  char *result;

  message = qjs_get_string_prop(ctx, exception, "message");
  name = qjs_get_string_prop(ctx, exception, "name");
  stack = qjs_get_string_prop(ctx, exception, "stack");
  file_name = qjs_get_string_prop(ctx, exception, "fileName");
  has_line = qjs_get_int_prop(ctx, exception, "lineNumber", &line);
  has_column = qjs_get_int_prop(ctx, exception, "columnNumber", &column);

  if (!message || !*message) {
    fallback_str = JS_ToCString(ctx, exception);
    fallback = qjs_strdup(fallback_str ? fallback_str : "JavaScript exception");
    if (fallback_str) {
      JS_FreeCString(ctx, fallback_str);
    }
    free(message);
    message = fallback;
    fallback = NULL;
  }

  qjs_sb_init(&builder);
  qjs_sb_append(&builder, "\x1eQuickJS_EXCEPTION");
  qjs_sb_append_char(&builder, '{');
  qjs_append_json_string_field(&builder, "message", message);
  qjs_sb_append_char(&builder, ',');
  qjs_append_json_string_field(&builder, "name", name);
  qjs_sb_append_char(&builder, ',');
  qjs_append_json_string_field(&builder, "stack", stack);
  qjs_sb_append_char(&builder, ',');
  qjs_append_json_string_field(&builder, "fileName", file_name);
  qjs_sb_append_char(&builder, ',');
  qjs_append_json_int_field(&builder, "line", has_line, line);
  qjs_sb_append_char(&builder, ',');
  qjs_append_json_int_field(&builder, "column", has_column, column);
  qjs_sb_append_char(&builder, '}');
  result = qjs_sb_take(&builder);

  free(message);
  free(name);
  free(stack);
  free(file_name);
  return result;
}

static char *qjs_value_to_string(JSContext *ctx, JSValue val) {
  const char *str;
  char *result;

  if (JS_IsUndefined(val)) {
    return qjs_strdup("undefined");
  }
  if (JS_IsNull(val)) {
    return qjs_strdup("null");
  }
  if (JS_IsBool(val)) {
    return qjs_strdup(JS_ToBool(ctx, val) ? "true" : "false");
  }
  if (JS_IsException(val)) {
    /* JS throw 不能和普通字符串混淆，前面加 sentinel 交给 Dart 映射成 JsException。 */
    JSValue exception = JS_GetException(ctx);
    result = qjs_exception_to_payload(ctx, exception);
    JS_FreeValue(ctx, exception);
    return result;
  }

  str = JS_ToCString(ctx, val);
  if (!str) {
    return qjs_strdup("[unprintable]");
  }
  result = qjs_strdup(str);
  JS_FreeCString(ctx, str);
  return result;
}

static int qjs_interrupt_handler(JSRuntime *rt, void *opaque) {
  QuickjsEvalInterrupt *interrupt = (QuickjsEvalInterrupt *)opaque;
  QuickjsRuntime *runtime;
  (void)rt;
  if (!interrupt) {
    return 0;
  }
  runtime = (QuickjsRuntime *)JS_GetRuntimeOpaque(rt);
  if (runtime && runtime->cancel_flag && *runtime->cancel_flag) {
    interrupt->cancelled = 1;
    return 1;
  }
  if (interrupt->has_deadline &&
      (clock_t)(clock() - interrupt->deadline) >= 0) {
    interrupt->timed_out = 1;
    return 1;
  }
  return 0;
}

static char *qjs_json_stringify(JSContext *ctx, JSValueConst value) {
  JSValue global;
  JSValue json;
  JSValue stringify;
  JSValue result;
  const char *str;
  char *copy;

  global = JS_GetGlobalObject(ctx);
  json = JS_GetPropertyStr(ctx, global, "JSON");
  stringify = JS_GetPropertyStr(ctx, json, "stringify");
  result = JS_Call(ctx, stringify, json, 1, &value);
  copy = NULL;
  if (!JS_IsException(result)) {
    str = JS_ToCString(ctx, result);
    if (str) {
      copy = qjs_strdup(str);
      JS_FreeCString(ctx, str);
    }
  }
  JS_FreeValue(ctx, result);
  JS_FreeValue(ctx, stringify);
  JS_FreeValue(ctx, json);
  JS_FreeValue(ctx, global);
  return copy;
}

static JSValue qjs_json_parse(JSContext *ctx, const char *json) {
  JSValue global;
  JSValue json_obj;
  JSValue parse;
  JSValue text;
  JSValue result;

  global = JS_GetGlobalObject(ctx);
  json_obj = JS_GetPropertyStr(ctx, global, "JSON");
  parse = JS_GetPropertyStr(ctx, json_obj, "parse");
  text = JS_NewString(ctx, json ? json : "null");
  result = JS_Call(ctx, parse, json_obj, 1, &text);
  JS_FreeValue(ctx, text);
  JS_FreeValue(ctx, parse);
  JS_FreeValue(ctx, json_obj);
  JS_FreeValue(ctx, global);
  return result;
}

static char *qjs_args_to_json(JSContext *ctx, int argc, JSValueConst *argv) {
  JSValue array;
  char *json;
  int i;

  array = JS_NewArray(ctx);
  for (i = 0; i < argc; i++) {
    JS_SetPropertyUint32(ctx, array, (uint32_t)i, JS_DupValue(ctx, argv[i]));
  }
  json = qjs_json_stringify(ctx, array);
  JS_FreeValue(ctx, array);
  return json;
}

static QuickjsPendingCallback *qjs_take_pending_callback(QuickjsRuntime *runtime,
                                                        int64_t request_id) {
  QuickjsPendingCallback **cursor;
  QuickjsPendingCallback *entry;

  cursor = &runtime->pending_callbacks;
  while (*cursor) {
    entry = *cursor;
    if (entry->request_id == request_id) {
      *cursor = entry->next;
      entry->next = NULL;
      return entry;
    }
    cursor = &entry->next;
  }
  return NULL;
}

static void qjs_free_pending_callbacks(QuickjsRuntime *runtime) {
  QuickjsPendingCallback *entry;
  QuickjsPendingCallback *next;

  entry = runtime->pending_callbacks;
  while (entry) {
    next = entry->next;
    JS_FreeValue(runtime->ctx, entry->resolve);
    JS_FreeValue(runtime->ctx, entry->reject);
    free(entry);
    entry = next;
  }
  runtime->pending_callbacks = NULL;
}

static int qjs_execute_pending_jobs(QuickjsRuntime *runtime) {
  JSContext *ctx;
  int result;

  if (!runtime || !runtime->rt) {
    return -1;
  }
  do {
    ctx = NULL;
    result = JS_ExecutePendingJob(runtime->rt, &ctx);
  } while (result > 0);
  return result;
}

static JSValue qjs_host_callback(JSContext *ctx, JSValueConst this_val,
                                 int argc, JSValueConst *argv, int magic,
                                 JSValue *func_data) {
  QuickjsRuntime *runtime;
  QuickjsPendingCallback *pending;
  JSValue resolving_funcs[2];
  JSValue promise;
  char *args_json;
  int64_t callback_id;
  int64_t request_id;

  (void)this_val;
  (void)magic;

  runtime = (QuickjsRuntime *)JS_GetRuntimeOpaque(JS_GetRuntime(ctx));
  if (!runtime || !runtime->host_callback) {
    return JS_ThrowInternalError(ctx, "QuickJS host callback is not available");
  }
  if (JS_ToInt64(ctx, &callback_id, func_data[0]) < 0) {
    return JS_EXCEPTION;
  }

  args_json = qjs_args_to_json(ctx, argc, argv);
  if (!args_json) {
    return JS_ThrowInternalError(ctx, "QuickJS host callback arguments cannot be encoded");
  }
  request_id = runtime->host_callback(callback_id, args_json);
  free(args_json);
  if (request_id <= 0) {
    return JS_ThrowInternalError(ctx, "QuickJS host callback request failed");
  }

  promise = JS_NewPromiseCapability(ctx, resolving_funcs);
  if (JS_IsException(promise)) {
    return promise;
  }

  pending = (QuickjsPendingCallback *)calloc(1, sizeof(*pending));
  if (!pending) {
    JS_FreeValue(ctx, resolving_funcs[0]);
    JS_FreeValue(ctx, resolving_funcs[1]);
    JS_FreeValue(ctx, promise);
    return JS_ThrowOutOfMemory(ctx);
  }
  pending->request_id = request_id;
  pending->resolve = resolving_funcs[0];
  pending->reject = resolving_funcs[1];
  pending->next = runtime->pending_callbacks;
  runtime->pending_callbacks = pending;
  return promise;
}

static char *qjs_async_poll_result(QuickjsRuntime *runtime) {
  JSPromiseStateEnum state;
  JSValue result;
  char *output;

  if (!runtime || !runtime->ctx || JS_IsUndefined(runtime->async_promise)) {
    return qjs_strdup("\x1eQuickJS_EXCEPTION{\"message\":\"QuickJS async eval is not running\"}");
  }

  if (qjs_execute_pending_jobs(runtime) < 0) {
    return qjs_strdup("\x1eQuickJS_EXCEPTION{\"message\":\"QuickJS pending job failed\"}");
  }

  state = JS_PromiseState(runtime->ctx, runtime->async_promise);
  if (state == JS_PROMISE_PENDING) {
    return qjs_strdup("\x1eQuickJS_PENDING");
  }

  result = JS_PromiseResult(runtime->ctx, runtime->async_promise);
  JS_FreeValue(runtime->ctx, runtime->async_promise);
  runtime->async_promise = JS_UNDEFINED;

  if (state == JS_PROMISE_FULFILLED) {
    output = qjs_value_to_string(runtime->ctx, result);
  } else {
    output = qjs_exception_to_payload(runtime->ctx, result);
  }
  JS_FreeValue(runtime->ctx, result);
  return output;
}

const char *quickjs_version(void) {
#if defined(QJS_VERSION_SUFFIX)
  static char version[32];
  static int initialized;
  if (!initialized) {
    snprintf(version, sizeof(version), "%d.%d.%d%s", QJS_VERSION_MAJOR,
             QJS_VERSION_MINOR, QJS_VERSION_PATCH, QJS_VERSION_SUFFIX);
    initialized = 1;
  }
  return version;
#else
  return "unknown";
#endif
}

QuickjsRuntime *quickjs_runtime_new(void) {
  QuickjsRuntime *runtime = (QuickjsRuntime *)calloc(1, sizeof(*runtime));
  if (!runtime) {
    return NULL;
  }
  runtime->async_promise = JS_UNDEFINED;

  runtime->rt = JS_NewRuntime();
  if (!runtime->rt) {
    free(runtime);
    return NULL;
  }
  JS_SetRuntimeOpaque(runtime->rt, runtime);

  /* std/os helpers 先保留，后续 module 和宿主能力设计时再收紧暴露边界。 */
  js_std_init_handlers(runtime->rt);
  runtime->ctx = JS_NewContext(runtime->rt);
  if (!runtime->ctx) {
    JS_FreeRuntime(runtime->rt);
    free(runtime);
    return NULL;
  }

  js_init_module_std(runtime->ctx, "std");
  js_init_module_os(runtime->ctx, "os");
  js_std_add_helpers(runtime->ctx, 0, NULL);
  return runtime;
}

void quickjs_runtime_free(QuickjsRuntime *runtime) {
  if (!runtime) {
    return;
  }
  if (runtime->ctx) {
    qjs_free_pending_callbacks(runtime);
    if (!JS_IsUndefined(runtime->async_promise)) {
      JS_FreeValue(runtime->ctx, runtime->async_promise);
      runtime->async_promise = JS_UNDEFINED;
    }
    JS_FreeContext(runtime->ctx);
    runtime->ctx = NULL;
  }
  if (runtime->rt) {
    JS_FreeRuntime(runtime->rt);
    runtime->rt = NULL;
  }
  free(runtime);
}

void quickjs_runtime_set_memory_limit(QuickjsRuntime *runtime,
                                      int64_t limit_bytes) {
  if (!runtime || !runtime->rt || limit_bytes <= 0) {
    return;
  }
  JS_SetMemoryLimit(runtime->rt, (size_t)limit_bytes);
}

void quickjs_runtime_set_stack_limit(QuickjsRuntime *runtime,
                                     int64_t limit_bytes) {
  if (!runtime || !runtime->rt || limit_bytes <= 0) {
    return;
  }
  JS_SetMaxStackSize(runtime->rt, (size_t)limit_bytes);
}

char *quickjs_eval(QuickjsRuntime *runtime, const char *code) {
  return quickjs_eval_timeout(runtime, code, 0);
}

void quickjs_runtime_set_cancel_flag(QuickjsRuntime *runtime,
                                     int32_t *cancel_flag) {
  if (!runtime) {
    return;
  }
  runtime->cancel_flag = cancel_flag;
}

char *quickjs_eval_timeout(QuickjsRuntime *runtime, const char *code,
                           int64_t timeout_ms) {
  JSValue result;
  QuickjsEvalInterrupt interrupt = {0, 0, 0, 0};

  if (!runtime || !runtime->ctx || !code) {
    return qjs_strdup("invalid arguments");
  }

  if (timeout_ms > 0 || runtime->cancel_flag) {
    /* timeout 和 stop 都依赖 JS_SetInterruptHandler；无 timeout 时仍允许 cancel_flag 中断。 */
    interrupt.has_deadline = timeout_ms > 0;
    interrupt.deadline =
        clock() + (clock_t)((timeout_ms * CLOCKS_PER_SEC) / 1000);
    JS_SetInterruptHandler(runtime->rt, qjs_interrupt_handler, &interrupt);
  }

  result = JS_Eval(runtime->ctx, code, strlen(code), "<eval>",
                   JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_STRICT);
  if (timeout_ms > 0 || runtime->cancel_flag) {
    JS_SetInterruptHandler(runtime->rt, NULL, NULL);
  }
  if (interrupt.cancelled) {
    JS_FreeValue(runtime->ctx, result);
    return qjs_strdup("\x1eQuickJS_CANCELLED");
  }
  if (interrupt.timed_out) {
    JS_FreeValue(runtime->ctx, result);
    return qjs_strdup("\x1eQuickJS_TIMEOUT");
  }
  char *output = qjs_value_to_string(runtime->ctx, result);
  JS_FreeValue(runtime->ctx, result);
  return output;
}

int quickjs_runtime_bind_callback(QuickjsRuntime *runtime, int64_t callback_id,
                                  const char *name,
                                  QuickjsHostCallback callback) {
  JSValue global;
  JSValue data;
  JSValue function;
  int result;

  if (!runtime || !runtime->ctx || !name || !callback) {
    return -1;
  }

  runtime->host_callback = callback;
  data = JS_NewInt64(runtime->ctx, callback_id);
  function = JS_NewCFunctionData(runtime->ctx, qjs_host_callback, 0, 0, 1, &data);
  JS_FreeValue(runtime->ctx, data);
  if (JS_IsException(function)) {
    return -1;
  }

  global = JS_GetGlobalObject(runtime->ctx);
  result = JS_SetPropertyStr(runtime->ctx, global, name, function);
  JS_FreeValue(runtime->ctx, global);
  return result;
}

char *quickjs_eval_async_start(QuickjsRuntime *runtime, const char *code) {
  JSValue result;

  if (!runtime || !runtime->ctx || !code) {
    return qjs_strdup("invalid arguments");
  }
  if (!JS_IsUndefined(runtime->async_promise)) {
    return qjs_strdup("\x1eQuickJS_EXCEPTION{\"message\":\"QuickJS async eval is already running\"}");
  }

  result = JS_Eval(runtime->ctx, code, strlen(code), "<evalAsync>",
                   JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_STRICT);
  if (JS_IsException(result)) {
    return qjs_value_to_string(runtime->ctx, result);
  }
  if (!JS_IsPromise(result)) {
    char *output = qjs_value_to_string(runtime->ctx, result);
    JS_FreeValue(runtime->ctx, result);
    return output;
  }

  runtime->async_promise = result;
  return qjs_async_poll_result(runtime);
}

char *quickjs_eval_async_poll(QuickjsRuntime *runtime) {
  return qjs_async_poll_result(runtime);
}

int quickjs_runtime_resolve_callback(QuickjsRuntime *runtime, int64_t request_id,
                                     int success, const char *payload_json) {
  QuickjsPendingCallback *pending;
  JSValue value;
  JSValue function;
  JSValue call_result;

  if (!runtime || !runtime->ctx) {
    return -1;
  }

  pending = qjs_take_pending_callback(runtime, request_id);
  if (!pending) {
    return -1;
  }

  value = success ? qjs_json_parse(runtime->ctx, payload_json)
                  : JS_NewError(runtime->ctx);
  if (!success) {
    JSValue message = JS_NewString(runtime->ctx, payload_json ? payload_json : "");
    JS_SetPropertyStr(runtime->ctx, value, "message", message);
  }
  if (JS_IsException(value)) {
    value = JS_NewString(runtime->ctx, payload_json ? payload_json : "");
  }

  function = success ? pending->resolve : pending->reject;
  call_result = JS_Call(runtime->ctx, function, JS_UNDEFINED, 1, &value);
  JS_FreeValue(runtime->ctx, call_result);
  JS_FreeValue(runtime->ctx, value);
  JS_FreeValue(runtime->ctx, pending->resolve);
  JS_FreeValue(runtime->ctx, pending->reject);
  free(pending);
  return qjs_execute_pending_jobs(runtime);
}

void quickjs_free_string(char *str) {
  free(str);
}
