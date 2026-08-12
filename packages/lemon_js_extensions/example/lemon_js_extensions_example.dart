import 'package:lemon_js_extensions/lemon_js_extensions.dart';

Future<void> main() async {
  final extension = await QuickjsExtension.load(
    QuickjsExtensionPackage(
      manifestSource: '''
{
  "schemaVersion": 2,
  "id": "site.example",
  "name": "Example site",
  "description": "Minimal extension package example",
  "version": "1.0.0",
  "versionCode": 10000,
  "compatibilityCode": "lemon-content-source-v1",
  "service": {
    "entry": "main.mjs",
    "contract": "content-source/v1",
    "publicExports": ["getHome"]
  }
}
''',
      serviceModules: const <String, String>{
        'main.mjs': 'export function getHome() { return {items: []}; }',
      },
    ),
  );

  final registry = QuickjsExtensionRegistry();
  QuickjsExtensionInstaller(registry: registry).install(extension);

  // ignore: avoid_print
  print('${extension.id}: ${extension.kind}');
}
