#include "quickjs_bridge.h"

#ifndef QUICKJS_BRIDGE_BUILD
#define QUICKJS_BRIDGE_BUILD
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "quickjs-libc.h"
#include "quickjs.h"

struct QuickjsRuntime {
  JSRuntime *rt;
  JSContext *ctx;
};

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
    JSValue exception = JS_GetException(ctx);
    str = JS_ToCString(ctx, exception);
    result = qjs_strdup(str ? str : "JavaScript exception");
    if (str) {
      JS_FreeCString(ctx, str);
    }
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

  runtime->rt = JS_NewRuntime();
  if (!runtime->rt) {
    free(runtime);
    return NULL;
  }

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
    JS_FreeContext(runtime->ctx);
    runtime->ctx = NULL;
  }
  if (runtime->rt) {
    JS_FreeRuntime(runtime->rt);
    runtime->rt = NULL;
  }
  free(runtime);
}

char *quickjs_eval(QuickjsRuntime *runtime, const char *code) {
  JSValue result;

  if (!runtime || !runtime->ctx || !code) {
    return qjs_strdup("invalid arguments");
  }

  result = JS_Eval(runtime->ctx, code, strlen(code), "<eval>",
                   JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_STRICT);
  char *output = qjs_value_to_string(runtime->ctx, result);
  JS_FreeValue(runtime->ctx, result);
  return output;
}

void quickjs_free_string(char *str) {
  free(str);
}
