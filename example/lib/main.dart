import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;

import 'app.dart';

/// example 应用入口。
void main() {
  fvp.registerWith(
    options: const <String, Object>{
      'platforms': <String>['windows', 'macos', 'linux'],
    },
  );
  runApp(const ExampleApp());
}
