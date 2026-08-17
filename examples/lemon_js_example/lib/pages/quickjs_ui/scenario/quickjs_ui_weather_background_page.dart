import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

class JsUiWeatherBackgroundPage extends StatefulWidget {
  const JsUiWeatherBackgroundPage({super.key});

  static const String path =
      'assets/quickjs_ui/weather_background_demo_page.mjs';

  @override
  State<JsUiWeatherBackgroundPage> createState() =>
      _JsUiWeatherBackgroundPageState();
}

class _JsUiWeatherBackgroundPageState extends State<JsUiWeatherBackgroundPage> {
  late final JsUiController _controller;
  Map<String, Object?>? _initialProps;

  @override
  void initState() {
    super.initState();
    _controller = JsUiController(devOptions: JsUiDevOptions.release);
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
              JsUiView.asset(
                path: JsUiWeatherBackgroundPage.path,
                controller: _controller,
                initialProps: _initialProps!,
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
