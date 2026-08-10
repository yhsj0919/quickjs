import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_ui_video_player/lemon_js_ui_video_player.dart';

/// VideoPlayer 插件 Demo：通过 `quickjs_ui/video_player` 模块暴露视频播放组件。
class QuickjsUiVideoPlayerPluginPage extends StatelessWidget {
  const QuickjsUiVideoPlayerPluginPage({super.key});

  /// 入口 JS 页面的 Flutter asset 路径。
  static const String path = 'assets/quickjs_ui/video_player_plugin_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('视频播放器插件')),
      body: QuickjsUiView.asset(
        path: path,
        uiPlugins: _videoPlayerPlugins,
        initialProps: const <String, Object?>{
          'title': 'VideoPlayer plugin demo',
          'autoplay': true,
          'loop': true,
        },
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('QuickJS UI video player plugin error: $error'),
        ),
      ),
    );
  }
}

/// 本页使用的 VideoPlayer UI 插件。
final List<QuickjsUiPlugin> _videoPlayerPlugins = <QuickjsUiPlugin>[
  QuickjsUiVideoPlayerPlugin.plugin,
];
