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

/* Returns the bundled QuickJS version string (e.g. "0.15.1"). */
QJS_BRIDGE_EXPORT const char *quickjs_version(void);

typedef struct QuickjsRuntime QuickjsRuntime;

QJS_BRIDGE_EXPORT QuickjsRuntime *quickjs_runtime_new(void);
QJS_BRIDGE_EXPORT void quickjs_runtime_free(QuickjsRuntime *runtime);
QJS_BRIDGE_EXPORT void quickjs_runtime_set_cancel_flag(
    QuickjsRuntime *runtime, int32_t *cancel_flag);

/*
 * Evaluates JavaScript in global scope.
 * Returns a newly allocated UTF-8 string (result or error message).
 * The caller must free it with quickjs_free_string().
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
