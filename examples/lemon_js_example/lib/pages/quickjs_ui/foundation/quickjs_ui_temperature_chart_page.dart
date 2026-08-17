import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

class JsUiTemperatureChartPage extends StatelessWidget {
  const JsUiTemperatureChartPage({super.key});

  static const String path = 'assets/quickjs_ui/temperature_chart_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Canvas 温度折线图')),
      body: JsUiView.asset(
        path: path,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('QuickJS UI temperature chart error: $error'),
        ),
      ),
    );
  }
}
