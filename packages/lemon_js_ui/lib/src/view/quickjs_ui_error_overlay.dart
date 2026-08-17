import 'package:flutter/widgets.dart';

import '../diagnostics/quickjs_ui_error.dart';

/// Public JSUI js ui error overlay API.
final class JsUiErrorOverlay extends StatelessWidget {
  /// Creates a js ui error overlay.
  const JsUiErrorOverlay({super.key, required this.error});

  /// The error value.
  final JsUiError error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xfffff6f6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Color(0xff2f1b1b),
              fontSize: 13,
              height: 1.35,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'quickjs_ui error',
                  style: TextStyle(
                    color: Color(0xff8a1f1f),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _ErrorLine(label: 'kind', value: error.kind.name),
                _ErrorLine(label: 'message', value: error.message),
                for (final entry in error.toMap().entries)
                  if (entry.key != 'kind' &&
                      entry.key != 'message' &&
                      entry.key != 'stackTrace')
                    _ErrorLine(
                      label: _label(entry.key),
                      value: '${entry.value}',
                    ),
                if (error.stackTrace != null) ...<Widget>[
                  const SizedBox(height: 12),
                  const Text(
                    'stack',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text('${error.stackTrace}'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _label(String key) => switch (key) {
  'schemaPath' => 'schema path',
  'causeType' => 'cause type',
  'causeSource' => 'schema source',
  'causeOffset' => 'schema offset',
  _ => key,
};

final class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('$label: $value'),
    );
  }
}
