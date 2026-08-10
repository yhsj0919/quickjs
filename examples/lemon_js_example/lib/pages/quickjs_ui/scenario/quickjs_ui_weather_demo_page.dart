import 'package:flutter/material.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_ui_video_player/lemon_js_ui_video_player.dart';

class QuickjsUiWeatherDemoPage extends StatefulWidget {
  const QuickjsUiWeatherDemoPage({super.key});

  static const String path = 'assets/quickjs_ui/weather_demo_page.mjs';

  @override
  State<QuickjsUiWeatherDemoPage> createState() =>
      _QuickjsUiWeatherDemoPageState();
}

class _QuickjsUiWeatherDemoPageState extends State<QuickjsUiWeatherDemoPage> {
  late final QuickjsUiController _controller;

  @override
  void initState() {
    super.initState();
    _controller = QuickjsUiController(
      devOptions: QuickjsUiDevOptions.release,
      onConsole: _handleConsole,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleConsole(QuickjsConsoleEvent event) {
    debugPrint('[weather.console/${event.level.name}] ${event.text}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('天气综合页面')),
      body: QuickjsUiView.asset(
        path: QuickjsUiWeatherDemoPage.path,
        controller: _controller,
        mounts: _weatherMounts,
        uiPlugins: _weatherUiPlugins,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('QuickJS UI 天气 Demo error: $error'),
        ),
      ),
    );
  }
}

final List<QuickjsHostMount> _weatherMounts = <QuickjsHostMount>[
  QuickjsAxiosMount(
    assetKey: 'assets/js/axios.js',
    timeout: const Duration(seconds: 15),
  ),
];

final List<QuickjsUiPlugin> _weatherUiPlugins = <QuickjsUiPlugin>[
  QuickjsUiVideoPlayerPlugin.plugin,
];
