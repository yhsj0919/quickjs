import 'package:flutter/material.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

class QuickjsUiWeatherBackgroundPage extends StatefulWidget {
  const QuickjsUiWeatherBackgroundPage({super.key});

  static const String path =
      'assets/quickjs_ui/weather_background_demo_page.mjs';

  @override
  State<QuickjsUiWeatherBackgroundPage> createState() =>
      _QuickjsUiWeatherBackgroundPageState();
}

class _QuickjsUiWeatherBackgroundPageState
    extends State<QuickjsUiWeatherBackgroundPage> {
  late final QuickjsUiController _controller;
  Map<String, Object?>? _initialProps;

  @override
  void initState() {
    super.initState();
    _controller = QuickjsUiController(devOptions: QuickjsUiDevOptions.release);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          _initialProps ??= <String, Object?>{
            'width': viewport.width,
            'height': viewport.height,
          };
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              QuickjsUiView.asset(
                path: QuickjsUiWeatherBackgroundPage.path,
                controller: _controller,
                initialProps: _initialProps!,
                mounts: _weatherBackgroundMounts,
                loadingBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
                errorBuilder: (_, error) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText('Weather background error: $error'),
                ),
              ),
              const SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: BackButton(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

final List<QuickjsHostMount> _weatherBackgroundMounts = <QuickjsHostMount>[
  QuickjsAxiosMount(
    assetKey: 'assets/js/axios.js',
    timeout: const Duration(seconds: 15),
  ),
];
