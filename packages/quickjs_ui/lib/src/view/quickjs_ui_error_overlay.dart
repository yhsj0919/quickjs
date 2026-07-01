import 'dart:io';

import 'package:flutter/widgets.dart';

final class QuickjsUiErrorDetails {
  const QuickjsUiErrorDetails({
    this.schemaPath,
    this.resourceKey,
    this.routeName,
    this.action,
    this.source,
  });

  final String? schemaPath;
  final String? resourceKey;
  final String? routeName;
  final String? action;
  final String? source;

  Iterable<MapEntry<String, String>> get entries sync* {
    final source = this.source;
    if (source != null && source.isNotEmpty) {
      yield MapEntry<String, String>('source', source);
    }
    final resourceKey = this.resourceKey;
    if (resourceKey != null && resourceKey.isNotEmpty) {
      yield MapEntry<String, String>('resource', resourceKey);
    }
    final schemaPath = this.schemaPath;
    if (schemaPath != null && schemaPath.isNotEmpty) {
      yield MapEntry<String, String>('schema path', schemaPath);
    }
    final routeName = this.routeName;
    if (routeName != null && routeName.isNotEmpty) {
      yield MapEntry<String, String>('route', routeName);
    }
    final action = this.action;
    if (action != null && action.isNotEmpty) {
      yield MapEntry<String, String>('action', action);
    }
  }
}

final class QuickjsUiErrorOverlay extends StatelessWidget {
  const QuickjsUiErrorOverlay({
    super.key,
    required this.error,
    this.details = const QuickjsUiErrorDetails(),
  });

  final Object error;
  final QuickjsUiErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final stackTrace = _stackTrace(error);
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
                _ErrorLine(label: 'type', value: error.runtimeType.toString()),
                _ErrorLine(label: 'message', value: _message(error)),
                for (final detail in details.entries)
                  _ErrorLine(label: detail.key, value: detail.value),
                if (error is HttpException)
                  _ErrorLine(
                    label: 'uri',
                    value: (error as HttpException).uri?.toString() ?? '',
                  ),
                if (error is FormatException)
                  _FormatExceptionDetails(error: error as FormatException),
                if (stackTrace != null && stackTrace.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  const Text(
                    'stack',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(stackTrace),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _FormatExceptionDetails extends StatelessWidget {
  const _FormatExceptionDetails({required this.error});

  final FormatException error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (error.source != null)
          _ErrorLine(label: 'schema source', value: '${error.source}'),
        if (error.offset != null)
          _ErrorLine(label: 'schema offset', value: '${error.offset}'),
      ],
    );
  }
}

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

String _message(Object error) {
  if (error is FormatException) {
    return error.message;
  }
  if (error is HttpException) {
    return error.message;
  }
  return '$error';
}

String? _stackTrace(Object error) {
  if (error is Error) {
    return error.stackTrace?.toString();
  }
  return null;
}
