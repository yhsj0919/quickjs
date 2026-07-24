import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiAdaptivePerformanceLabPage extends StatefulWidget {
  const QuickjsUiAdaptivePerformanceLabPage({super.key});

  @override
  State<QuickjsUiAdaptivePerformanceLabPage> createState() =>
      _QuickjsUiAdaptivePerformanceLabPageState();
}

class _QuickjsUiAdaptivePerformanceLabPageState
    extends State<QuickjsUiAdaptivePerformanceLabPage> {
  late final QuickjsUiController _controller;
  late QuickjsUiPerformanceController _performance;
  QuickjsUiPerformanceMode _mode = QuickjsUiPerformanceMode.auto;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _controller = QuickjsUiController();
    _performance = _createPerformance(_mode);
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  QuickjsUiPerformanceController _createPerformance(
    QuickjsUiPerformanceMode mode,
  ) => QuickjsUiPerformanceController(mode: mode);

  void _setMode(QuickjsUiPerformanceMode mode) {
    if (_mode == mode) return;
    final previous = _performance;
    setState(() {
      _mode = mode;
      _performance = _createPerformance(mode);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _performance.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _performance.snapshot.toMap();
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        title: const Text('Adaptive Performance Lab'),
        backgroundColor: const Color(0xFF020617),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: <Widget>[
          _QualitySelector(mode: _mode, onChanged: _setMode),
          Expanded(
            child: QuickjsUiView.asset(
              path: 'assets/quickjs_ui/adaptive_performance_lab_page.mjs',
              controller: _controller,
              performanceController: _performance,
              loadingBuilder: (_) =>
                  const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, error) => SelectableText(
                'Performance lab error: $error',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          _MetricsPanel(metrics: metrics),
        ],
      ),
    );
  }
}

class _QualitySelector extends StatelessWidget {
  const _QualitySelector({required this.mode, required this.onChanged});

  final QuickjsUiPerformanceMode mode;
  final ValueChanged<QuickjsUiPerformanceMode> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
    child: Row(
      children: <Widget>[
        for (final value in QuickjsUiPerformanceMode.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ChoiceChip(
              label: Text(value.name),
              selected: value == mode,
              onSelected: (_) => onChanged(value),
            ),
          ),
      ],
    ),
  );
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.metrics});

  final Map<String, Object?> metrics;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    collapsedTextColor: Colors.white,
    textColor: Colors.white,
    iconColor: Colors.white,
    collapsedIconColor: Colors.white,
    title: Text(
      'quality=${metrics['quality']} · '
      '${metrics['refreshRate'] ?? '-'}Hz · '
      'budget=${metrics['targetFrameBudgetMs']}ms · '
      'rasterP90=${metrics['rasterP90Ms'] ?? '-'}ms',
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    ),
    children: <Widget>[
      SizedBox(
        height: 180,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(metrics),
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ),
      ),
    ],
  );
}
