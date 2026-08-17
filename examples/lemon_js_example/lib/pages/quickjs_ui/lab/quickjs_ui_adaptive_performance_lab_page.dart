import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

class JsUiAdaptivePerformanceLabPage extends StatefulWidget {
  const JsUiAdaptivePerformanceLabPage({super.key});

  @override
  State<JsUiAdaptivePerformanceLabPage> createState() =>
      _JsUiAdaptivePerformanceLabPageState();
}

class _JsUiAdaptivePerformanceLabPageState
    extends State<JsUiAdaptivePerformanceLabPage> {
  late final JsUiController _controller;
  late JsUiPerformanceController _performance;
  JsUiPerformanceMode _mode = JsUiPerformanceMode.auto;
  Timer? _refreshTimer;
  JsUiPerformanceReport? _report;

  @override
  void initState() {
    super.initState();
    _controller = JsUiController();
    _performance = _createPerformance(_mode);
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  JsUiPerformanceController _createPerformance(JsUiPerformanceMode mode) =>
      JsUiPerformanceController(mode: mode);

  void _setMode(JsUiPerformanceMode mode) {
    if (_mode == mode) return;
    final previous = _performance;
    setState(() {
      _mode = mode;
      _performance = _createPerformance(mode);
      _report = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  void _toggleSession() {
    if (_performance.isSessionActive) {
      setState(() => _report = _performance.stopSession());
      return;
    }
    _performance.startSession(
      warmUp: const Duration(seconds: 2),
      scene: const <String, Object?>{'demo': 'adaptive-performance-lab'},
      metadata: const <String, Object?>{'app': 'quickjs-example'},
    );
    setState(() => _report = null);
  }

  Future<void> _copyReport() async {
    final report = _report;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: report.toJson()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('性能报告 JSON 已复制')));
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
        title: const Text('自适应效果质量'),
        backgroundColor: const Color(0xFF020617),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: <Widget>[
          _QualitySelector(
            mode: _mode,
            enabled: !_performance.isSessionActive,
            onChanged: _setMode,
          ),
          _SessionControls(
            recording: _performance.isSessionActive,
            hasReport: _report != null,
            onToggle: _toggleSession,
            onCopy: _copyReport,
          ),
          Expanded(
            child: JsUiView.asset(
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
          _MetricsPanel(metrics: metrics, report: _report),
        ],
      ),
    );
  }
}

class _SessionControls extends StatelessWidget {
  const _SessionControls({
    required this.recording,
    required this.hasReport,
    required this.onToggle,
    required this.onCopy,
  });

  final bool recording;
  final bool hasReport;
  final VoidCallback onToggle;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Row(
      children: <Widget>[
        FilledButton.icon(
          onPressed: onToggle,
          icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
          label: Text(recording ? '停止并生成报告' : '开始采样（预热 2 秒）'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: hasReport ? onCopy : null,
          icon: const Icon(Icons.copy),
          label: const Text('复制 JSON'),
        ),
      ],
    ),
  );
}

class _QualitySelector extends StatelessWidget {
  const _QualitySelector({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final JsUiPerformanceMode mode;
  final bool enabled;
  final ValueChanged<JsUiPerformanceMode> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
    child: Row(
      children: <Widget>[
        for (final value in JsUiPerformanceMode.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ChoiceChip(
              label: Text(value.name),
              selected: value == mode,
              onSelected: enabled ? (_) => onChanged(value) : null,
            ),
          ),
      ],
    ),
  );
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.metrics, required this.report});

  final Map<String, Object?> metrics;
  final JsUiPerformanceReport? report;

  String _metric(Object? value, {int digits = 2}) {
    if (value is num) return value.toStringAsFixed(digits);
    return '-';
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    collapsedTextColor: Colors.white,
    textColor: Colors.white,
    iconColor: Colors.white,
    collapsedIconColor: Colors.white,
    title: Text(
      'mode=${metrics['mode']} · quality=${metrics['quality']} · '
      '${_metric(metrics['refreshRate'], digits: 1)}Hz\n'
      'budget=${_metric(metrics['targetFrameBudgetMs'])}ms · '
      'rasterP90=${_metric(metrics['rasterP90Ms'])}ms · '
      'slowFrames=${metrics['consecutiveSlowFrames'] ?? 0}',
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    ),
    children: <Widget>[
      SizedBox(
        height: 180,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            report?.toJson() ??
                const JsonEncoder.withIndent(' ').convert(metrics),
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
