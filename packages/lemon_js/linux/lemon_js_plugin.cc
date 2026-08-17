#include "include/lemon_js/lemon_js_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include "lemon_js_plugin_private.h"

#define LEMON_JS_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), lemon_js_plugin_get_type(), \
                              LemonJsPlugin))

struct _LemonJsPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(LemonJsPlugin, lemon_js_plugin, g_object_get_type())

static void lemon_js_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(lemon_js_plugin_parent_class)->dispose(object);
}

static void lemon_js_plugin_class_init(LemonJsPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = lemon_js_plugin_dispose;
}

static void lemon_js_plugin_init(LemonJsPlugin* self) {}

void lemon_js_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  LemonJsPlugin* plugin = LEMON_JS_PLUGIN(
      g_object_new(lemon_js_plugin_get_type(), nullptr));
  g_object_unref(plugin);
}
