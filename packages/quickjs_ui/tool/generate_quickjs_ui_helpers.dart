import 'dart:convert';
import 'dart:io';

void main() {
  final packageRoot = Directory.current;
  final sourceFile = File('${packageRoot.path}/js/quickjs_ui.js');
  final outputFile = File(
    '${packageRoot.path}/lib/src/runtime/quickjs_ui_helpers.g.dart',
  );

  final source = sourceFile.readAsStringSync();
  final generated =
      '''
// GENERATED CODE - DO NOT MODIFY BY HAND.
//
// Source: js/quickjs_ui.js
// To update, run:
//   dart run tool/generate_quickjs_ui_helpers.dart

part of 'quickjs_ui_helpers.dart';

const String quickjsUiHelperModuleSource = ${jsonEncode(source)};
''';

  outputFile.writeAsStringSync(generated);
}
