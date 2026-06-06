//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <quickjs/quickjs_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) quickjs_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "QuickjsPlugin");
  quickjs_plugin_register_with_registrar(quickjs_registrar);
}
