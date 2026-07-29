import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

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
  Size? _pendingSize;
  Size? _appliedSize;
  bool _viewportUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = QuickjsUiController()..addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (_controller.plugin != null) _scheduleViewportUpdate();
  }

  void _recordViewport(Size size) {
    if (_pendingSize == size) return;
    _pendingSize = size;
    _scheduleViewportUpdate();
  }

  void _scheduleViewportUpdate() {
    if (_viewportUpdateScheduled) return;
    _viewportUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportUpdateScheduled = false;
      if (!mounted) return;
      final size = _pendingSize;
      if (size == null || size == _appliedSize || _controller.plugin == null) {
        return;
      }
      _appliedSize = size;
      unawaited(
        _controller.setState(<String, Object?>{
          'viewportWidth': size.width,
          'viewportHeight': size.height,
        }),
      );
    });
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
          _recordViewport(viewport);
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              QuickjsUiView.asset(
                path: QuickjsUiWeatherBackgroundPage.path,
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
