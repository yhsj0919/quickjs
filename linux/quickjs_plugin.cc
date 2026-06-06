#include "include/quickjs/quickjs_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include "quickjs_plugin_private.h"

#define QUICKJS_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), quickjs_plugin_get_type(), \
                              QuickjsPlugin))

struct _QuickjsPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(QuickjsPlugin, quickjs_plugin, g_object_get_type())

static void quickjs_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(quickjs_plugin_parent_class)->dispose(object);
}

static void quickjs_plugin_class_init(QuickjsPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = quickjs_plugin_dispose;
}

static void quickjs_plugin_init(QuickjsPlugin* self) {}

void quickjs_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  QuickjsPlugin* plugin = QUICKJS_PLUGIN(
      g_object_new(quickjs_plugin_get_type(), nullptr));
  g_object_unref(plugin);
}
