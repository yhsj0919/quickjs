#ifndef QUICKJS_BRIDGE_H
#define QUICKJS_BRIDGE_H

#include <stdint.h>

#ifdef _WIN32
#  ifdef QUICKJS_BRIDGE_BUILD
#    define QJS_BRIDGE_EXPORT __declspec(dllexport)
#  else
#    define QJS_BRIDGE_EXPORT __declspec(dllimport)
#  endif
#else
#  define QJS_BRIDGE_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* 返回当前打包的 QuickJS 版本字符串，例如 "0.15.1"。 */
QJS_BRIDGE_EXPORT const char *quickjs_version(void);

/* Dart 侧只持有这个不透明指针，不直接访问内部 JSRuntime / JSContext。 */
typedef struct QuickjsRuntime QuickjsRuntime;

QJS_BRIDGE_EXPORT QuickjsRuntime *quickjs_runtime_new(void);
QJS_BRIDGE_EXPORT void quickjs_runtime_free(QuickjsRuntime *runtime);
QJS_BRIDGE_EXPORT void quickjs_runtime_set_memory_limit(
    QuickjsRuntime *runtime, int64_t limit_bytes);
QJS_BRIDGE_EXPORT void quickjs_runtime_set_stack_limit(
    QuickjsRuntime *runtime, int64_t limit_bytes);
QJS_BRIDGE_EXPORT void quickjs_runtime_set_cancel_flag(
    QuickjsRuntime *runtime, int32_t *cancel_flag);

/*
 * 在全局作用域执行 JavaScript。
 * 返回新分配的 UTF-8 字符串；调用方必须用 quickjs_free_string() 释放。
 * 特殊错误通过不可见 sentinel 前缀返回，由 Dart worker 还原成异常类型。
 */
QJS_BRIDGE_EXPORT char *quickjs_eval(QuickjsRuntime *runtime, const char *code);
QJS_BRIDGE_EXPORT char *quickjs_eval_timeout(QuickjsRuntime *runtime,
                                             const char *code,
                                             int64_t timeout_ms);

QJS_BRIDGE_EXPORT void quickjs_free_string(char *str);

#ifdef __cplusplus
}
#endif

#endif /* QUICKJS_BRIDGE_H */
