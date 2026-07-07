import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

void main() {
  group('quickjs_ui package format', () {
    test('parses manifest metadata and permissions', () {
      final manifest = QuickjsUiManifest.parse('''
{
  "schemaVersion": 1,
  "id": "quickjs_ui.test.package",
  "name": "Package Test",
  "version": "1.2.3",
  "entry": "main.mjs",
  "modules": {
    "main.mjs": {
      "sha256": "${quickjsUiSha256Hex('export default 1;')}"
    }
  },
  "permissions": [
    "quickjs_ui.host.network"
  ],
  "routes": {
    "main": {
      "entry": "main.mjs",
      "title": "Main"
    }
  },
  "cache": {
    "mode": "versioned",
    "immutable": true,
    "maxAgeSeconds": 60
  }
}
''');

      manifest.validatePackageRoot();

      expect(manifest.id, 'quickjs_ui.test.package');
      expect(manifest.name, 'Package Test');
      expect(manifest.permissions, <String>['quickjs_ui.host.network']);
      expect(manifest.routes['main']?.entry, 'main.mjs');
      expect(manifest.cache?.mode, 'versioned');
      expect(manifest.cache?.immutable, isTrue);
    });

    test('rejects checksum mismatch', () async {
      const source = 'export default 1;';
      final manifest = '''
{
  "schemaVersion": 1,
  "id": "quickjs_ui.test.bad_checksum",
  "version": "1.0.0",
  "entry": "main.mjs",
  "modules": {
    "main.mjs": {
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
    }
  }
}
''';

      expect(
        () => QuickjsUiBundle.fromManifestSource(
          manifest,
          resolver: QuickjsUiResourceResolver.memory(const <String, String>{
            'main.mjs': source,
          }),
          validatePackageRoot: true,
        ),
        throwsFormatException,
      );
    });

    test('rejects undeclared relative imports', () async {
      const source = "import './missing.mjs';\nexport default 1;";
      final manifest =
          '''
{
  "schemaVersion": 1,
  "id": "quickjs_ui.test.missing_import",
  "version": "1.0.0",
  "entry": "main.mjs",
  "modules": {
    "main.mjs": {
      "sha256": "${quickjsUiSha256Hex(source)}"
    }
  }
}
''';

      expect(
        () => QuickjsUiBundle.fromManifestSource(
          manifest,
          resolver: QuickjsUiResourceResolver.memory(const <String, String>{
            'main.mjs': source,
          }),
          validatePackageRoot: true,
        ),
        throwsFormatException,
      );
    });

    test('loads zip package from bytes', () async {
      const mainSource =
          "import { value } from './feature.mjs';\nexport { value };";
      const featureSource = 'export const value = 42;';
      final manifest =
          '''
{
  "schemaVersion": 1,
  "id": "quickjs_ui.test.zip",
  "version": "1.0.0",
  "entry": "main.mjs",
  "modules": {
    "main.mjs": {
      "sha256": "${quickjsUiSha256Hex(mainSource)}"
    },
    "feature.mjs": {
      "sha256": "${quickjsUiSha256Hex(featureSource)}"
    }
  },
  "permissions": [
    "quickjs_ui.host.navigation"
  ]
}
''';
      final archive = Archive()
        ..addFile(ArchiveFile.string('manifest.json', manifest))
        ..addFile(ArchiveFile.string('main.mjs', mainSource))
        ..addFile(ArchiveFile.string('feature.mjs', featureSource));
      final bytes = ZipEncoder().encode(archive);

      final bundle = await QuickjsUiBundle.zipPackageBytes(bytes);

      expect(bundle.id, 'quickjs_ui.test.zip');
      expect(
        bundle.modules.keys,
        containsAll(<String>['main.mjs', 'feature.mjs']),
      );
      expect(bundle.permissions, <String>['quickjs_ui.host.navigation']);
    });

    test('loads compiled package sources', () {
      const mainSource =
          "import { value } from './feature.mjs';\nexport { value };";
      const featureSource = 'export const value = 42;';
      final manifest =
          '''
{
  "schemaVersion": 1,
  "id": "quickjs_ui.test.compiled",
  "version": "1.0.0",
  "entry": "main.mjs",
  "modules": {
    "main.mjs": {
      "sha256": "${quickjsUiSha256Hex(mainSource)}"
    },
    "feature.mjs": {
      "sha256": "${quickjsUiSha256Hex(featureSource)}"
    }
  },
  "permissions": [
    "quickjs_ui.host.navigation"
  ]
}
''';

      final bundle = QuickjsUiBundle.compiledPackage(
        manifestSource: manifest,
        modules: const <String, String>{
          'main.mjs': mainSource,
          'feature.mjs': featureSource,
        },
        validatePackageRoot: true,
      );

      expect(bundle.id, 'quickjs_ui.test.compiled');
      expect(
        bundle.modules.keys,
        containsAll(<String>['main.mjs', 'feature.mjs']),
      );
      expect(bundle.permissions, <String>['quickjs_ui.host.navigation']);
    });

    test('creates page plugins from inline sources', () {
      final plugin = QuickjsUiPagePlugin.singleFile(
        id: 'quickjs_ui_test_source_page',
        version: '0.1.0',
        source: 'export default { mount() { return { type: "text" }; } };',
      );

      expect(plugin.manifest.id, 'quickjs_ui_test_source_page');
      expect(plugin.modules.map((module) => module.specifier), <String>[
        'quickjs_ui_test_source_page/page',
        'quickjs_ui_test_source_page/main',
      ]);
    });

    test('bundle permissions are passed to plugin manifest', () {
      final bundle = QuickjsUiBundle(
        id: 'quickjs_ui.test.permissions',
        version: '1.0.0',
        entry: 'main.mjs',
        modules: const <String, String>{'main.mjs': 'export default {};'},
        permissions: const <String>['quickjs_ui.host.network'],
      );

      expect(bundle.toPlugin().manifest.permissions, <String>[
        'quickjs_ui.host.network',
      ]);
    });
  });
}
