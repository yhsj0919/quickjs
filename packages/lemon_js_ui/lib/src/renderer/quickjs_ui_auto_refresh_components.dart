import 'dart:async';

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_types.dart';
import 'quickjs_ui_render_context.dart';

final QuickjsUiComponentBuilderMap quickjsUiAutoRefreshComponentBuilders =
    <String, QuickjsUiComponentBuilder>{
      'AutoRefresh': _buildAutoRefresh,
      'DateTimeText': _buildDateTimeText,
    };

Widget _buildAutoRefresh(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final intervalMs = QuickjsUiProps.intValue(
    node.props['intervalMs'],
    name: 'AutoRefresh intervalMs',
  );
  if (intervalMs == null || intervalMs < 16 || intervalMs > 86400000) {
    throw const FormatException(
      'quickjs_ui AutoRefresh intervalMs must be between 16 and 86400000',
    );
  }
  return _AutoRefresh(
    interval: Duration(milliseconds: intervalMs),
    paused: node.props['paused'] == true,
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildDateTimeText(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return _DateTimeText(
    format: QuickjsUiProps.string(node.props['format']) ?? 'HH:mm:ss',
    textAlign: QuickjsUiProps.textAlign(node.props['textAlign']),
    maxLines: QuickjsUiProps.intValue(node.props['maxLines']),
    softWrap: QuickjsUiProps.boolValue(node.props['softWrap']),
    overflow: _textOverflow(node.props['overflow']),
    style: context.textStyle(node.props['style']),
  );
}

TextOverflow? _textOverflow(Object? value) => switch (value) {
  null => null,
  'clip' => TextOverflow.clip,
  'fade' => TextOverflow.fade,
  'ellipsis' => TextOverflow.ellipsis,
  'visible' => TextOverflow.visible,
  _ => throw const FormatException('Unknown quickjs_ui DateTimeText overflow'),
};

final class _AutoRefresh extends StatefulWidget {
  const _AutoRefresh({
    required this.interval,
    required this.paused,
    required this.child,
  });

  final Duration interval;
  final bool paused;
  final Widget child;

  @override
  State<_AutoRefresh> createState() => _AutoRefreshState();
}

final class _AutoRefreshState extends State<_AutoRefresh> {
  final ValueNotifier<DateTime> _clock = ValueNotifier<DateTime>(
    DateTime.now(),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _AutoRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval ||
        oldWidget.paused != widget.paused) {
      _syncTimer();
    }
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.paused) return;
    _timer = Timer.periodic(widget.interval, (_) {
      _clock.value = DateTime.now();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AutoRefreshScope(clock: _clock, child: widget.child);
  }
}

final class _AutoRefreshScope
    extends InheritedNotifier<ValueNotifier<DateTime>> {
  const _AutoRefreshScope({
    required ValueNotifier<DateTime> clock,
    required super.child,
  }) : super(notifier: clock);

  static DateTime now(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AutoRefreshScope>()
            ?.notifier
            ?.value ??
        DateTime.now();
  }
}

final class _DateTimeText extends StatelessWidget {
  const _DateTimeText({
    required this.format,
    required this.textAlign,
    required this.maxLines,
    required this.softWrap,
    required this.overflow,
    required this.style,
  });

  final String format;
  final TextAlign? textAlign;
  final int? maxLines;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatDateTime(_AutoRefreshScope.now(context), format),
      textAlign: textAlign,
      maxLines: maxLines,
      softWrap: softWrap,
      overflow: overflow,
      style: style,
    );
  }
}

String _formatDateTime(DateTime value, String format) {
  final replacements = <String, String>{
    'yyyy': value.year.toString().padLeft(4, '0'),
    'MM': value.month.toString().padLeft(2, '0'),
    'dd': value.day.toString().padLeft(2, '0'),
    'HH': value.hour.toString().padLeft(2, '0'),
    'mm': value.minute.toString().padLeft(2, '0'),
    'ss': value.second.toString().padLeft(2, '0'),
  };
  var result = format;
  for (final entry in replacements.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result;
}
