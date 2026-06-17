#include "quickjs_bridge.h"

#ifndef QUICKJS_BRIDGE_BUILD
#define QUICKJS_BRIDGE_BUILD
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#define strtok_r strtok_s
#endif

#include "quickjs-libc.h"
#include "quickjs.h"

typedef struct QuickjsPendingCallback {
  int64_t request_id;
  JSValue resolve;
  JSValue reject;
  struct QuickjsPendingCallback *next;
} QuickjsPendingCallback;

typedef struct QuickjsTimer {
  int32_t id;
  int is_interval;
  int cancelled;
  int running;
  int64_t delay_ms;
  int64_t due_ms;
  JSValue callback;
  JSValue *args;
  int argc;
  struct QuickjsTimer *next;
} QuickjsTimer;

typedef struct QuickjsModuleSource {
  char *name;
  char *source;
  struct QuickjsModuleSource *next;
} QuickjsModuleSource;

struct QuickjsRuntime {
  JSRuntime *rt;
  JSContext *ctx;
  /* Dart worker 写入这个共享标记，interrupt handler 读取后中断 JS。 */
  volatile int32_t *cancel_flag;
  QuickjsHostCallback host_callback;
  QuickjsHostStreamPull host_stream_pull;
  QuickjsHostStreamCancel host_stream_cancel;
  QuickjsHostSinkAction host_sink_action;
  QuickjsPendingCallback *pending_callbacks;
  QuickjsTimer *timers;
  QuickjsModuleSource *module_sources;
  int32_t next_timer_id;
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

static char qjs_hex_value(char ch) {
  if (ch >= '0' && ch <= '9') {
    return (char)(ch - '0');
  }
  if (ch >= 'a' && ch <= 'f') {
    return (char)(10 + ch - 'a');
  }
  if (ch >= 'A' && ch <= 'F') {
    return (char)(10 + ch - 'A');
  }
  return -1;
}

static char *qjs_percent_decode(const char *text, size_t len) {
  char *out = (char *)malloc(len + 1);
  size_t i;
  size_t j = 0;
  if (!out) {
    return NULL;
  }
  for (i = 0; i < len; i++) {
    if (text[i] == '%' && i + 2 < len) {
      char hi = qjs_hex_value(text[i + 1]);
      char lo = qjs_hex_value(text[i + 2]);
      if (hi >= 0 && lo >= 0) {
        out[j++] = (char)((hi << 4) | lo);
        i += 2;
        continue;
      }
    }
    out[j++] = text[i];
  }
  out[j] = '\0';
  return out;
}

static void qjs_free_module_sources(QuickjsRuntime *runtime) {
  QuickjsModuleSource *item;
  QuickjsModuleSource *next;
  if (!runtime) {
    return;
  }
  item = runtime->module_sources;
  while (item) {
    next = item->next;
    free(item->name);
    free(item->source);
    free(item);
    item = next;
  }
  runtime->module_sources = NULL;
}

static int qjs_add_module_source(QuickjsRuntime *runtime, char *name,
                                 char *source) {
  QuickjsModuleSource *item;
  if (!runtime || !name || !source) {
    free(name);
    free(source);
    return 0;
  }
  item = (QuickjsModuleSource *)calloc(1, sizeof(*item));
  if (!item) {
    free(name);
    free(source);
    return 0;
  }
  item->name = name;
  item->source = source;
  item->next = runtime->module_sources;
  runtime->module_sources = item;
  return 1;
}

static int qjs_set_module_sources(QuickjsRuntime *runtime, const char *modules) {
  const char *line;
  const char *line_end;
  const char *equals;
  char *name;
  char *source;

  qjs_free_module_sources(runtime);
  if (!runtime || !modules || !modules[0]) {
    return 1;
  }
  line = modules;
  while (*line) {
    line_end = strchr(line, '\n');
    if (!line_end) {
      line_end = line + strlen(line);
    }
    if (line_end > line) {
      equals = memchr(line, '=', (size_t)(line_end - line));
      if (equals) {
        name = qjs_percent_decode(line, (size_t)(equals - line));
        source = qjs_percent_decode(equals + 1, (size_t)(line_end - equals - 1));
        if (!qjs_add_module_source(runtime, name, source)) {
          return 0;
        }
      }
    }
    line = *line_end == '\n' ? line_end + 1 : line_end;
  }
  return 1;
}

static const char *qjs_find_module_source(QuickjsRuntime *runtime,
                                          const char *name) {
  QuickjsModuleSource *item;
  if (!runtime || !name) {
    return NULL;
  }
  for (item = runtime->module_sources; item; item = item->next) {
    if (strcmp(item->name, name) == 0) {
      return item->source;
    }
  }
  return NULL;
}

static void *qjs_js_alloc(void *opaque, size_t size) {
  return js_malloc((JSContext *)opaque, size);
}

static char *qjs_normalize_module_name_alloc(const char *base_name,
                                             const char *module_name,
                                             void *(*alloc_fn)(void *, size_t),
                                             void *opaque) {
  const char *base_end;
  char *cursor;
  char **parts = NULL;
  size_t part_count = 0;
  size_t part_capacity = 0;
  size_t out_len = 0;
  char *combined;
  char *result;
  char *token;
  char *saveptr = NULL;
  size_t i;

  if (!module_name) {
    return NULL;
  }
  if (strncmp(module_name, "./", 2) != 0 &&
      strncmp(module_name, "../", 3) != 0) {
    size_t module_name_len = strlen(module_name);
    result = (char *)alloc_fn(opaque, module_name_len + 1);
    if (result) {
      memcpy(result, module_name, module_name_len + 1);
    }
    return result;
  }

  base_end = base_name ? strrchr(base_name, '/') : NULL;
  if (base_end) {
    size_t base_len = (size_t)(base_end - base_name + 1);
    combined = (char *)malloc(base_len + strlen(module_name) + 1);
    if (!combined) {
      return NULL;
    }
    memcpy(combined, base_name, base_len);
    memcpy(combined + base_len, module_name, strlen(module_name) + 1);
  } else {
    combined = qjs_strdup(module_name);
    if (!combined) {
      return NULL;
    }
  }

  for (token = strtok_r(combined, "/", &saveptr); token;
       token = strtok_r(NULL, "/", &saveptr)) {
    if (strcmp(token, ".") == 0 || strcmp(token, "") == 0) {
      continue;
    }
    if (strcmp(token, "..") == 0) {
      if (part_count > 0) {
        part_count--;
      }
      continue;
    }
    if (part_count == part_capacity) {
      size_t new_capacity = part_capacity ? part_capacity * 2 : 8;
      char **new_parts =
          (char **)realloc(parts, new_capacity * sizeof(char *));
      if (!new_parts) {
        free(parts);
        free(combined);
        return NULL;
      }
      parts = new_parts;
      part_capacity = new_capacity;
    }
    parts[part_count++] = token;
  }

  for (i = 0; i < part_count; i++) {
    out_len += strlen(parts[i]) + (i > 0 ? 1 : 0);
  }
  result = (char *)alloc_fn(opaque, out_len + 1);
  if (result) {
    cursor = result;
    for (i = 0; i < part_count; i++) {
      size_t len = strlen(parts[i]);
      if (i > 0) {
        *((char *)cursor) = '/';
        cursor++;
      }
      memcpy((char *)cursor, parts[i], len);
      cursor += len;
    }
    *((char *)cursor) = '\0';
  }
  free(parts);
  free(combined);
  return result;
}

typedef struct QjsStringBuilder {
  char *data;
  size_t length;
  size_t capacity;
  int failed;
} QjsStringBuilder;

static char *qjs_exception_to_payload(JSContext *ctx, JSValue exception);
static char *qjs_value_to_string(JSContext *ctx, JSValue val);

static int64_t qjs_now_ms(void) {
#ifdef _WIN32
  return (int64_t)GetTickCount64();
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ((int64_t)ts.tv_sec * 1000) + (ts.tv_nsec / 1000000);
#endif
}

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

static JSValue qjs_callback_wire_codec(JSContext *ctx) {
  static const char *source =
      "(() => ({"
      "encode(value, seen = new WeakSet()) {"
      "if (value === undefined) return null;"
      "if (value === null || typeof value === 'number' || typeof value === 'boolean' || typeof value === 'string') return value;"
      "if (value instanceof ArrayBuffer) return { __quickjsType: 'bytes', value: Array.from(new Uint8Array(value)) };"
      "if (ArrayBuffer.isView(value)) return { __quickjsType: 'bytes', value: Array.from(new Uint8Array(value.buffer, value.byteOffset, value.byteLength)) };"
      "if (Array.isArray(value)) return value.map((item) => this.encode(item, seen));"
      "if (typeof value === 'object') {"
      "if (seen.has(value)) throw new TypeError('QuickJS callback value cannot contain circular references');"
      "seen.add(value);"
      "const out = {};"
      "for (const key of Object.keys(value)) out[key] = this.encode(value[key], seen);"
      "seen.delete(value);"
      "return out;"
      "}"
      "throw new TypeError('QuickJS callback value cannot be encoded: ' + typeof value);"
      "},"
      "decode(value) {"
      "if (Array.isArray(value)) return value.map((item) => this.decode(item));"
      "if (value && typeof value === 'object') {"
      "if (value.__quickjsType === 'bytes') return new Uint8Array(value.value || []);"
      "const out = {};"
      "for (const key of Object.keys(value)) out[key] = this.decode(value[key]);"
      "return out;"
      "}"
      "return value;"
      "}"
      "}))()";
  return JS_Eval(ctx, source, strlen(source), "<callback-codec>",
                 JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_STRICT);
}

static JSValue qjs_call_codec_method(JSContext *ctx, const char *method,
                                     JSValueConst value) {
  JSValue codec;
  JSValue function;
  JSValue result;

  codec = qjs_callback_wire_codec(ctx);
  if (JS_IsException(codec)) {
    return codec;
  }
  function = JS_GetPropertyStr(ctx, codec, method);
  result = JS_Call(ctx, function, codec, 1, &value);
  JS_FreeValue(ctx, function);
  JS_FreeValue(ctx, codec);
  return result;
}

static char *qjs_module_normalize(JSContext *ctx, const char *module_base_name,
                                  const char *module_name, void *opaque) {
  (void)opaque;
  return qjs_normalize_module_name_alloc(module_base_name, module_name,
                                         qjs_js_alloc, ctx);
}

static JSModuleDef *qjs_module_loader(JSContext *ctx, const char *module_name,
                                      void *opaque) {
  QuickjsRuntime *runtime = (QuickjsRuntime *)opaque;
  const char *source = qjs_find_module_source(runtime, module_name);
  JSValue compiled;
  JSModuleDef *module;

  if (!source) {
    JS_ThrowReferenceError(ctx, "could not load module '%s'", module_name);
    return NULL;
  }

  compiled = JS_Eval(ctx, source, strlen(source), module_name,
                     JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
  if (JS_IsException(compiled)) {
    return NULL;
  }
  module = (JSModuleDef *)JS_VALUE_GET_PTR(compiled);
  JS_FreeValue(ctx, compiled);
  return module;
}

static JSValue qjs_create_pending_promise(JSContext *ctx,
                                          QuickjsRuntime *runtime,
                                          int64_t request_id) {
  QuickjsPendingCallback *pending;
  JSValue resolving_funcs[2];
  JSValue promise;

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
  JSValue encoded;
  char *json;
  int i;

  array = JS_NewArray(ctx);
  for (i = 0; i < argc; i++) {
    JS_SetPropertyUint32(ctx, array, (uint32_t)i, JS_DupValue(ctx, argv[i]));
  }
  encoded = qjs_call_codec_method(ctx, "encode", array);
  json = JS_IsException(encoded) ? NULL : qjs_json_stringify(ctx, encoded);
  JS_FreeValue(ctx, encoded);
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

static void qjs_free_timer(QuickjsRuntime *runtime, QuickjsTimer *timer) {
  int i;

  if (!timer) {
    return;
  }
  JS_FreeValue(runtime->ctx, timer->callback);
  for (i = 0; i < timer->argc; i++) {
    JS_FreeValue(runtime->ctx, timer->args[i]);
  }
  free(timer->args);
  free(timer);
}

static void qjs_free_timers(QuickjsRuntime *runtime) {
  QuickjsTimer *entry;
  QuickjsTimer *next;

  entry = runtime->timers;
  while (entry) {
    next = entry->next;
    qjs_free_timer(runtime, entry);
    entry = next;
  }
  runtime->timers = NULL;
}

static QuickjsTimer *qjs_find_timer(QuickjsRuntime *runtime, int32_t id) {
  QuickjsTimer *entry;

  entry = runtime->timers;
  while (entry) {
    if (entry->id == id) {
      return entry;
    }
    entry = entry->next;
  }
  return NULL;
}

static void qjs_remove_timer(QuickjsRuntime *runtime, int32_t id) {
  QuickjsTimer **cursor;
  QuickjsTimer *entry;

  cursor = &runtime->timers;
  while (*cursor) {
    entry = *cursor;
    if (entry->id == id) {
      entry->cancelled = 1;
      if (entry->running) {
        return;
      }
      *cursor = entry->next;
      qjs_free_timer(runtime, entry);
      return;
    }
    cursor = &entry->next;
  }
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

static JSValue qjs_set_timer(JSContext *ctx, JSValueConst this_val, int argc,
                             JSValueConst *argv, int magic) {
  QuickjsRuntime *runtime;
  QuickjsTimer *timer;
  int64_t delay_ms = 0;
  int i;

  (void)this_val;

  runtime = (QuickjsRuntime *)JS_GetRuntimeOpaque(JS_GetRuntime(ctx));
  if (!runtime) {
    return JS_ThrowInternalError(ctx, "QuickJS timer runtime is not available");
  }
  if (argc < 1 || !JS_IsFunction(ctx, argv[0])) {
    return JS_ThrowTypeError(ctx, "QuickJS timer callback must be a function");
  }
  if (argc >= 2 && !JS_IsUndefined(argv[1]) && !JS_IsNull(argv[1])) {
    if (JS_ToInt64(ctx, &delay_ms, argv[1]) < 0) {
      return JS_EXCEPTION;
    }
  }
  if (delay_ms < 0) {
    delay_ms = 0;
  }
  if (magic && delay_ms == 0) {
    delay_ms = 1;
  }

  timer = (QuickjsTimer *)calloc(1, sizeof(*timer));
  if (!timer) {
    return JS_ThrowOutOfMemory(ctx);
  }
  timer->id = runtime->next_timer_id++;
  if (timer->id <= 0) {
    timer->id = runtime->next_timer_id++;
  }
  timer->is_interval = magic ? 1 : 0;
  timer->delay_ms = delay_ms;
  timer->due_ms = qjs_now_ms() + delay_ms;
  timer->callback = JS_DupValue(ctx, argv[0]);
  timer->argc = argc > 2 ? argc - 2 : 0;
  if (timer->argc > 0) {
    timer->args = (JSValue *)calloc((size_t)timer->argc, sizeof(JSValue));
    if (!timer->args) {
      JS_FreeValue(ctx, timer->callback);
      free(timer);
      return JS_ThrowOutOfMemory(ctx);
    }
    for (i = 0; i < timer->argc; i++) {
      timer->args[i] = JS_DupValue(ctx, argv[i + 2]);
    }
  }
  timer->next = runtime->timers;
  runtime->timers = timer;
  return JS_NewInt32(ctx, timer->id);
}

static JSValue qjs_clear_timer(JSContext *ctx, JSValueConst this_val, int argc,
                               JSValueConst *argv) {
  QuickjsRuntime *runtime;
  int32_t id;

  (void)this_val;

  runtime = (QuickjsRuntime *)JS_GetRuntimeOpaque(JS_GetRuntime(ctx));
  if (!runtime || argc < 1 || JS_ToInt32(ctx, &id, argv[0]) < 0) {
    return JS_UNDEFINED;
  }
  qjs_remove_timer(runtime, id);
  return JS_UNDEFINED;
}

static int qjs_run_due_timers(QuickjsRuntime *runtime) {
  QuickjsTimer *entry;
  QuickjsTimer *next;
  JSValue result;
  int64_t now_ms;
  int ran = 0;

  if (!runtime || !runtime->ctx) {
    return 0;
  }
  now_ms = qjs_now_ms();
  entry = runtime->timers;
  while (entry) {
    next = entry->next;
    if (!entry->cancelled && entry->due_ms <= now_ms) {
      entry->running = 1;
      result = JS_Call(runtime->ctx, entry->callback, JS_UNDEFINED,
                       entry->argc, entry->args);
      entry->running = 0;
      ran++;
      JS_FreeValue(runtime->ctx, result);
      if (entry->is_interval && !entry->cancelled &&
          qjs_find_timer(runtime, entry->id) == entry) {
        entry->due_ms = qjs_now_ms() + entry->delay_ms;
      } else {
        qjs_remove_timer(runtime, entry->id);
      }
    }
    entry = next;
  }
  return ran;
}

static void qjs_install_timers(QuickjsRuntime *runtime) {
  JSValue global;
  JSValue set_timeout;
  JSValue set_interval;
  JSValue clear_timeout;
  JSValue clear_interval;

  if (!runtime || !runtime->ctx) {
    return;
  }
  global = JS_GetGlobalObject(runtime->ctx);
  set_timeout =
      JS_NewCFunctionMagic(runtime->ctx, qjs_set_timer, "setTimeout", 2,
                           JS_CFUNC_generic_magic, 0);
  set_interval =
      JS_NewCFunctionMagic(runtime->ctx, qjs_set_timer, "setInterval", 2,
                           JS_CFUNC_generic_magic, 1);
  clear_timeout =
      JS_NewCFunction(runtime->ctx, qjs_clear_timer, "clearTimeout", 1);
  clear_interval =
      JS_NewCFunction(runtime->ctx, qjs_clear_timer, "clearInterval", 1);
  JS_SetPropertyStr(runtime->ctx, global, "setTimeout", set_timeout);
  JS_SetPropertyStr(runtime->ctx, global, "setInterval", set_interval);
  JS_SetPropertyStr(runtime->ctx, global, "clearTimeout", clear_timeout);
  JS_SetPropertyStr(runtime->ctx, global, "clearInterval", clear_interval);
  JS_FreeValue(runtime->ctx, global);
}

static JSValue qjs_host_callback(JSContext *ctx, JSValueConst this_val,
                                 int argc, JSValueConst *argv, int magic,
                                 JSValue *func_data) {
  QuickjsRuntime *runtime;
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
  return qjs_create_pending_promise(ctx, runtime, request_id);
}

static JSValue qjs_stream_pull(JSContext *ctx, JSValueConst this_val, int argc,
                               JSValueConst *argv) {
  QuickjsRuntime *runtime;
  int64_t stream_id;
  int64_t request_id;

  (void)this_val;
  if (argc < 1 || JS_ToInt64(ctx, &stream_id, argv[0]) < 0) {
    return JS_EXCEPTION;
  }
  runtime = (QuickjsRuntime *)JS_GetRuntimeOpaque(JS_GetRuntime(ctx));
  if (!runtime || !runtime->host_stream_pull) {
    return JS_ThrowInternalError(ctx, "QuickJS stream pull is not available");
  }
  request_id = runtime->host_stream_pull(stream_id);
  if (request_id <= 0) {
    return JS_ThrowInternalError(ctx, "QuickJS stream pull request failed");
  }
  return qjs_create_pending_promise(ctx, runtime, request_id);
}

static JSValue qjs_stream_cancel(JSContext *ctx, JSValueConst this_val,
                                 int argc, JSValueConst *argv) {
  QuickjsRuntime *runtime;
  int64_t stream_id;

  (void)this_val;
  if (argc < 1 || JS_ToInt64(ctx, &stream_id, argv[0]) < 0) {
    return JS_EXCEPTION;
  }
  runtime = (QuickjsRuntime *)JS_GetRuntimeOpaque(JS_GetRuntime(ctx));
  if (runtime && runtime->host_stream_cancel) {
    runtime->host_stream_cancel(stream_id);
  }
  return JS_UNDEFINED;
}

static JSValue qjs_sink_action(JSContext *ctx, JSValueConst this_val, int argc,
                               JSValueConst *argv, int magic,
                               JSValue *func_data) {
  QuickjsRuntime *runtime;
  int64_t sink_id;
  const char *action;
  char *payload_json = NULL;
  JSValue payload_value;
  int64_t request_id;

  (void)this_val;
  (void)magic;
  if (JS_ToInt64(ctx, &sink_id, func_data[0]) < 0) {
    return JS_EXCEPTION;
  }
  action = JS_ToCString(ctx, func_data[1]);
  if (!action) {
    return JS_EXCEPTION;
  }
  runtime = (QuickjsRuntime *)JS_GetRuntimeOpaque(JS_GetRuntime(ctx));
  if (!runtime || !runtime->host_sink_action) {
    JS_FreeCString(ctx, action);
    return JS_ThrowInternalError(ctx, "QuickJS sink action is not available");
  }
  if (argc >= 1 && !JS_IsUndefined(argv[0])) {
    payload_value = qjs_call_codec_method(ctx, "encode", argv[0]);
    if (JS_IsException(payload_value)) {
      JS_FreeCString(ctx, action);
      return payload_value;
    }
    payload_json = qjs_json_stringify(ctx, payload_value);
    JS_FreeValue(ctx, payload_value);
  }
  request_id = runtime->host_sink_action(sink_id, action, payload_json);
  free(payload_json);
  JS_FreeCString(ctx, action);
  if (request_id <= 0) {
    return JS_ThrowInternalError(ctx, "QuickJS sink action request failed");
  }
  return qjs_create_pending_promise(ctx, runtime, request_id);
}

static void qjs_install_stream_helpers(QuickjsRuntime *runtime) {
  static const char *source =
      "globalThis.__quickjsDartStream = {"
      "create(streamId) {"
      "return {"
      "[Symbol.asyncIterator]() { return this; },"
      "async next() {"
      "const payload = await __quickjsStreamPull(streamId);"
      "if (payload.done) return { done: true, value: undefined };"
      "return { done: false, value: payload.value };"
      "},"
      "async return() { __quickjsStreamCancel(streamId); return { done: true, value: undefined }; }"
      "};"
      "}"
      "};";
  JSValue global;
  JSValue pull;
  JSValue cancel;
  JSValue result;

  if (!runtime || !runtime->ctx) {
    return;
  }
  global = JS_GetGlobalObject(runtime->ctx);
  pull = JS_NewCFunction(runtime->ctx, qjs_stream_pull, "__quickjsStreamPull", 1);
  cancel =
      JS_NewCFunction(runtime->ctx, qjs_stream_cancel, "__quickjsStreamCancel", 1);
  JS_SetPropertyStr(runtime->ctx, global, "__quickjsStreamPull", pull);
  JS_SetPropertyStr(runtime->ctx, global, "__quickjsStreamCancel", cancel);
  JS_FreeValue(runtime->ctx, global);
  result = JS_Eval(runtime->ctx, source, strlen(source), "<stream-helpers>",
                   JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_STRICT);
  JS_FreeValue(runtime->ctx, result);
}

static JSValue qjs_create_dart_stream(JSContext *ctx, int64_t stream_id) {
  JSValue global;
  JSValue helper;
  JSValue create_fn;
  JSValue stream_id_value;
  JSValue result;

  global = JS_GetGlobalObject(ctx);
  helper = JS_GetPropertyStr(ctx, global, "__quickjsDartStream");
  create_fn = JS_GetPropertyStr(ctx, helper, "create");
  JS_FreeValue(ctx, helper);
  JS_FreeValue(ctx, global);
  if (JS_IsUndefined(create_fn)) {
    JS_FreeValue(ctx, create_fn);
    return JS_ThrowInternalError(ctx, "QuickJS stream helper is not installed");
  }
  stream_id_value = JS_NewInt64(ctx, stream_id);
  result = JS_Call(ctx, create_fn, JS_UNDEFINED, 1, &stream_id_value);
  JS_FreeValue(ctx, stream_id_value);
  JS_FreeValue(ctx, create_fn);
  return result;
}

static int qjs_value_is_dart_stream(JSContext *ctx, JSValueConst value,
                                    int64_t *stream_id) {
  JSValue type_value;
  const char *type_name;
  JSValue id_value;
  int result = 0;

  if (!JS_IsObject(value)) {
    return 0;
  }
  type_value = JS_GetPropertyStr(ctx, value, "__quickjsType");
  type_name = JS_ToCString(ctx, type_value);
  if (type_name && strcmp(type_name, "dartStream") == 0) {
    id_value = JS_GetPropertyStr(ctx, value, "streamId");
    result = JS_ToInt64(ctx, stream_id, id_value) == 0;
    JS_FreeValue(ctx, id_value);
  }
  if (type_name) {
    JS_FreeCString(ctx, type_name);
  }
  JS_FreeValue(ctx, type_value);
  return result;
}

static JSValue qjs_materialize_wire_value(JSContext *ctx, JSValue value) {
  int64_t stream_id;

  if (qjs_value_is_dart_stream(ctx, value, &stream_id)) {
    JS_FreeValue(ctx, value);
    return qjs_create_dart_stream(ctx, stream_id);
  }
  return value;
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
  if (qjs_run_due_timers(runtime) > 0 && qjs_execute_pending_jobs(runtime) < 0) {
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
  JS_SetModuleLoaderFunc(runtime->rt, qjs_module_normalize, qjs_module_loader,
                         runtime);
  runtime->next_timer_id = 1;
  qjs_install_timers(runtime);
  qjs_install_stream_helpers(runtime);
  return runtime;
}

void quickjs_runtime_free(QuickjsRuntime *runtime) {
  if (!runtime) {
    return;
  }
  if (runtime->ctx) {
    qjs_free_pending_callbacks(runtime);
    qjs_free_timers(runtime);
    qjs_free_module_sources(runtime);
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
  return quickjs_eval_timeout_named(runtime, code, "<eval>", timeout_ms);
}

char *quickjs_eval_timeout_named(QuickjsRuntime *runtime, const char *code,
                                 const char *name, int64_t timeout_ms) {
  JSValue result;
  QuickjsEvalInterrupt interrupt = {0, 0, 0, 0};
  const char *eval_name = name && *name ? name : "<eval>";

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

  result = JS_Eval(runtime->ctx, code, strlen(code), eval_name,
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

char *quickjs_eval_module(QuickjsRuntime *runtime, const char *source,
                          const char *name, const char *modules) {
  JSValue result;
  JSPromiseStateEnum state;
  JSValue promise_result;
  char *output;

  if (!runtime || !runtime->ctx || !source || !name) {
    return qjs_strdup("invalid arguments");
  }
  if (!qjs_set_module_sources(runtime, modules)) {
    return qjs_strdup("\x1eQuickJS_EXCEPTION{\"message\":\"QuickJS module table allocation failed\"}");
  }
  result = JS_Eval(runtime->ctx, source, strlen(source), name,
                   JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_STRICT);
  if (qjs_execute_pending_jobs(runtime) < 0) {
    JS_FreeValue(runtime->ctx, result);
    return qjs_strdup("\x1eQuickJS_EXCEPTION{\"message\":\"QuickJS pending job failed\"}");
  }
  if (JS_IsPromise(result)) {
    state = JS_PromiseState(runtime->ctx, result);
    if (state == JS_PROMISE_PENDING) {
      JS_FreeValue(runtime->ctx, result);
      return qjs_strdup("\x1eQuickJS_EXCEPTION{\"message\":\"QuickJS module evaluation is still pending\"}");
    }
    promise_result = JS_PromiseResult(runtime->ctx, result);
    if (state == JS_PROMISE_FULFILLED) {
      output = qjs_value_to_string(runtime->ctx, promise_result);
    } else {
      output = qjs_exception_to_payload(runtime->ctx, promise_result);
    }
    JS_FreeValue(runtime->ctx, promise_result);
    JS_FreeValue(runtime->ctx, result);
    return output;
  }
  output = qjs_value_to_string(runtime->ctx, result);
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
  return quickjs_eval_async_start_named(runtime, code, "<evalAsync>");
}

char *quickjs_eval_async_start_named(QuickjsRuntime *runtime, const char *code,
                                     const char *name) {
  JSValue result;
  const char *eval_name = name && *name ? name : "<evalAsync>";

  if (!runtime || !runtime->ctx || !code) {
    return qjs_strdup("invalid arguments");
  }
  if (!JS_IsUndefined(runtime->async_promise)) {
    return qjs_strdup("\x1eQuickJS_EXCEPTION{\"message\":\"QuickJS async eval is already running\"}");
  }

  result = JS_Eval(runtime->ctx, code, strlen(code), eval_name,
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
  if (success && !JS_IsException(value)) {
    JSValue decoded = qjs_call_codec_method(runtime->ctx, "decode", value);
    JS_FreeValue(runtime->ctx, value);
    value = qjs_materialize_wire_value(runtime->ctx, decoded);
  }
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

void quickjs_runtime_set_stream_handlers(QuickjsRuntime *runtime,
                                         QuickjsHostStreamPull pull,
                                         QuickjsHostStreamCancel cancel,
                                         QuickjsHostSinkAction sink_action) {
  if (!runtime) {
    return;
  }
  runtime->host_stream_pull = pull;
  runtime->host_stream_cancel = cancel;
  runtime->host_sink_action = sink_action;
}

int quickjs_runtime_resolve_stream_pull(QuickjsRuntime *runtime,
                                        int64_t request_id, int success,
                                        const char *payload_json) {
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
  if (success) {
    value = qjs_json_parse(runtime->ctx, payload_json);
    if (!JS_IsException(value)) {
      JSValue decoded = qjs_call_codec_method(runtime->ctx, "decode", value);
      JS_FreeValue(runtime->ctx, value);
      value = decoded;
    }
  } else {
    value = JS_NewError(runtime->ctx);
    JS_SetPropertyStr(runtime->ctx, value, "message",
                      JS_NewString(runtime->ctx,
                                   payload_json ? payload_json : ""));
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

int quickjs_runtime_resolve_sink_action(QuickjsRuntime *runtime,
                                        int64_t request_id, int success,
                                        const char *message) {
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
  if (success) {
    value = JS_UNDEFINED;
  } else {
    value = JS_NewError(runtime->ctx);
    JS_SetPropertyStr(runtime->ctx, value, "message",
                      JS_NewString(runtime->ctx, message ? message : ""));
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

int quickjs_runtime_bind_sink(QuickjsRuntime *runtime, int64_t sink_id,
                              const char *name) {
  JSValue global;
  JSValue sink;
  JSValue data[2];
  JSValue emit;
  JSValue close;
  JSValue error;
  int result;

  if (!runtime || !runtime->ctx || !name) {
    return -1;
  }
  sink = JS_NewObject(runtime->ctx);
  data[0] = JS_NewInt64(runtime->ctx, sink_id);

  data[1] = JS_NewString(runtime->ctx, "emit");
  emit = JS_NewCFunctionData(runtime->ctx, qjs_sink_action, 1, 0, 2, data);
  JS_FreeValue(runtime->ctx, data[1]);
  JS_SetPropertyStr(runtime->ctx, sink, "emit", emit);

  data[1] = JS_NewString(runtime->ctx, "close");
  close = JS_NewCFunctionData(runtime->ctx, qjs_sink_action, 0, 0, 2, data);
  JS_FreeValue(runtime->ctx, data[1]);
  JS_SetPropertyStr(runtime->ctx, sink, "close", close);

  data[1] = JS_NewString(runtime->ctx, "error");
  error = JS_NewCFunctionData(runtime->ctx, qjs_sink_action, 1, 0, 2, data);
  JS_FreeValue(runtime->ctx, data[1]);
  JS_SetPropertyStr(runtime->ctx, sink, "error", error);

  JS_FreeValue(runtime->ctx, data[0]);
  global = JS_GetGlobalObject(runtime->ctx);
  result = JS_SetPropertyStr(runtime->ctx, global, name, sink);
  JS_FreeValue(runtime->ctx, global);
  return result;
}

void quickjs_free_string(char *str) {
  free(str);
}
