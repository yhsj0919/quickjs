#ifndef FLUTTER_PLUGIN_LEMON_JS_PLUGIN_H_
#define FLUTTER_PLUGIN_LEMON_JS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace lemon_js {

class LemonJsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  LemonJsPlugin();

  virtual ~LemonJsPlugin();

  LemonJsPlugin(const LemonJsPlugin&) = delete;
  LemonJsPlugin& operator=(const LemonJsPlugin&) = delete;
};

}  // namespace lemon_js

#endif  // FLUTTER_PLUGIN_LEMON_JS_PLUGIN_H_
