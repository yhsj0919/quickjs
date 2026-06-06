#include "quickjs_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace quickjs {

void QuickjsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  registrar->AddPlugin(std::make_unique<QuickjsPlugin>());
}

QuickjsPlugin::QuickjsPlugin() {}

QuickjsPlugin::~QuickjsPlugin() {}

}  // namespace quickjs
