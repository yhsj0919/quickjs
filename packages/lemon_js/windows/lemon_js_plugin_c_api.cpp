#include "include/lemon_js/lemon_js_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "lemon_js_plugin.h"

void LemonJsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  lemon_js::LemonJsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
