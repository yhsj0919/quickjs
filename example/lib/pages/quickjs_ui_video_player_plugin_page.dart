import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs_ui/quickjs_ui.dart';
import 'package:quickjs_ui_video_player/quickjs_ui_video_player.dart';

class QuickjsUiVideoPlayerPluginPage extends StatelessWidget {
  const QuickjsUiVideoPlayerPluginPage({super.key});

  static const String path = 'assets/quickjs_ui/video_player_plugin_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI VideoPlayer Plugin')),
      body: QuickjsUiView.asset(
        path: path,
        registry: _videoPlayerRegistry,
        mounts: const <QuickjsHostMount>[QuickjsUiVideoPlayerPlugin.mount],
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

final QuickjsUiComponentRegistry _videoPlayerRegistry =
    QuickjsUiVideoPlayerPlugin.registry();
