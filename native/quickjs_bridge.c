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

struct QuickjsRuntime {
  JSRuntime *rt;
  JSContext *ctx;
  /* Dart worker 写入这个共享标记，interrupt handler 读取后中断 JS。 */
  volatile int32_t *cancel_flag;
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

static char *qjs_value_to_string(JSContext *ctx, JSValue val) {
  const char *str;
  const char *message;
  char *result;
  size_t prefix_len;
  size_t message_len;

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
    str = JS_ToCString(ctx, exception);
    message = str ? str : "JavaScript exception";
    prefix_len = strlen("\x1eQuickJS_EXCEPTION");
    message_len = strlen(message);
    result = (char *)malloc(prefix_len + message_len + 1);
    if (result) {
      memcpy(result, "\x1eQuickJS_EXCEPTION", prefix_len);
      memcpy(result + prefix_len, message, message_len + 1);
    }
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

void quickjs_free_string(char *str) {
  free(str);
}
