import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs_ui/quickjs_ui.dart';
import 'package:quickjs_ui_video_player/quickjs_ui_video_player.dart';

/// 天气综合 Demo：城市切换、刷新、当前天气、小时预报与生活提示。
///
/// 演示业务 [mounts]（Axios 网络）与 [uiPlugins]（VideoPlayer 原生控件）的分工。
class QuickjsUiWeatherDemoPage extends StatelessWidget {
  const QuickjsUiWeatherDemoPage({super.key});

  /// 入口 JS 页面的 Flutter asset 路径。
  static const String path = 'assets/quickjs_ui/weather_demo_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI 天气综合 Demo')),
      body: QuickjsUiView.asset(
        path: path,
        mounts: _weatherMounts,
        uiPlugins: _weatherUiPlugins,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(padding: const EdgeInsets.all(16), child: SelectableText('QuickJS UI 天气 Demo error: $error')),
      ),
    );
  }
}

/// 业务 JS 能力：一行启用 Axios（内部已包含 Fetch/XHR 依赖）。
final List<QuickjsHostMount> _weatherMounts = <QuickjsHostMount>[QuickjsAxiosMount(assetKey: 'assets/js/axios.js')];

/// 原生 UI 插件：注册 VideoPlayer 的 JS 模块与 Flutter 渲染器。
final List<QuickjsUiPlugin> _weatherUiPlugins = <QuickjsUiPlugin>[QuickjsUiVideoPlayerPlugin.plugin];
