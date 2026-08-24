#ifndef LEMON_JS_NATIVE_BRIDGE_H
#define LEMON_JS_NATIVE_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/* Link anchor used by the Swift plugin shell. Dart resolves the full API. */
const char *quickjs_version(void);

#ifdef __cplusplus
}
#endif

#endif
