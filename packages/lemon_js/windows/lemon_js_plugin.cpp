#include "lemon_js_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace lemon_js {

void LemonJsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  registrar->AddPlugin(std::make_unique<LemonJsPlugin>());
}

LemonJsPlugin::LemonJsPlugin() {}

LemonJsPlugin::~LemonJsPlugin() {}

}  // namespace lemon_js
