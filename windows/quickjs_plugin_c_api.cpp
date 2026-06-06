#include "include/quickjs/quickjs_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "quickjs_plugin.h"

void QuickjsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  quickjs::QuickjsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
