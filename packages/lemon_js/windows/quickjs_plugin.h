#ifndef FLUTTER_PLUGIN_QUICKJS_PLUGIN_H_
#define FLUTTER_PLUGIN_QUICKJS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace quickjs {

class QuickjsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  QuickjsPlugin();

  virtual ~QuickjsPlugin();

  QuickjsPlugin(const QuickjsPlugin&) = delete;
  QuickjsPlugin& operator=(const QuickjsPlugin&) = delete;
};

}  // namespace quickjs

#endif  // FLUTTER_PLUGIN_QUICKJS_PLUGIN_H_
