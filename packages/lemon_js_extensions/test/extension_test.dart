import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lemon_js_extensions/lemon_js_extensions.dart';

void main() {
  test('manager automatically selects a default store', () {
    final manager = JsExtensionManager(
      constraints: const <JsExtensionConstraint>[],
    );

    expect(manager.store, isA<JsExtensionDefaultStore>());
  });

  const manifestSource = '''
{
  "schemaVersion": 2,
  "id": "site.example1",
  "name": "站点 1",
  "description": "测试混合插件",
  "version": "1.0.0",
  "versionCode": 10000,
  "compatibilityCode": "lemon-content-source-v1",
  "service": {
    "entry": "service/main.mjs",
    "contract": "content-source/v1",
    "publicExports": ["getHome"],
    "uiExports": ["submitLogin"]
  },
  "ui": {
    "routes": {
      "authentication": {
        "entry": "ui/authentication.mjs",
        "title": "登录"
      }
    }
  },
  "flows": {
    "authentication": {"route": "authentication"}
  },
  "permissions": ["network", "storage"]
}
''';

  test('parses and round-trips a hybrid manifest', () {
    final manifest = JsExtensionManifest.parse(manifestSource);

    expect(manifest.id, 'site.example1');
    expect(manifest.service?.contract, 'content-source/v1');
    expect(manifest.ui?.routes.keys, contains('authentication'));
    expect(
      JsExtensionManifest.parse(manifest.toJson()).toMap(),
      manifest.toMap(),
    );
  });

  test('parses required and optional host capability versions', () {
    final source = manifestSource.replaceFirst(
      '"permissions": ["network", "storage"]',
      '''"capabilities": {
    "required": {"network": 1},
    "optional": {"cookieJar": 1}
  },
  "permissions": ["network", "storage"]''',
    );
    final manifest = JsExtensionManifest.parse(source);

    expect(manifest.capabilities.required, {'network': 1});
    expect(manifest.capabilities.optional, {'cookieJar': 1});
    expect(
      JsExtensionManifest.parse(manifest.toJson()).capabilities.toMap(),
      manifest.capabilities.toMap(),
    );
  });

  test('rejects duplicated and invalid capability declarations', () {
    expect(
      () => JsExtensionCapabilityManifest.fromMap({
        'required': {'network': 1},
        'optional': {'network': 1},
      }),
      throwsFormatException,
    );
    expect(
      () => JsExtensionCapabilityManifest.fromMap({
        'required': {'network': 0},
      }),
      throwsFormatException,
    );
  });

  test('rejects a flow referencing a missing route', () {
    expect(
      () => JsExtensionManifest.parse(
        manifestSource.replaceFirst(
          '"route": "authentication"',
          '"route": "missing"',
        ),
      ),
      throwsFormatException,
    );
  });

  test('rejects package paths that escape the extension root', () {
    expect(
      () => JsExtensionManifest.parse(
        manifestSource.replaceFirst('service/main.mjs', '../service/main.mjs'),
      ),
      throwsFormatException,
    );
  });

  test('creates one hybrid extension with matching service and UI', () {
    final manifest = JsExtensionManifest.parse(manifestSource);
    final extension = _hybridExtension(manifest);

    expect(extension.kind, JsExtensionKind.hybrid);
    expect(extension.id, 'site.example1');
  });

  test('loads a unified package into one hybrid extension', () async {
    final extension = await JsExtension.load(
      JsExtensionPackage(
        manifestSource: manifestSource,
        serviceModules: const <String, String>{
          'service/main.mjs': '''
export function getHome() { return []; }
export function submitLogin() { return true; }
''',
        },
        uiModules: const <String, String>{
          'ui/authentication.mjs': 'export default {};',
        },
      ),
    );

    expect(extension.kind, JsExtensionKind.hybrid);
    expect(
      extension.service?.plugin.manifest.entry,
      'site.example1/service/main.mjs',
    );
    expect(extension.ui?.routes.keys, ['authentication']);
  });

  test(
    'session keeps one lazy service runtime and restricts exports',
    () async {
      final manifest = JsExtensionManifest.parse(manifestSource);
      final runtimes = <_FakeRuntime>[];
      final session = JsExtensionSession(
        extension: _hybridExtension(manifest),
        grantedPermissions: const <String>['network', 'storage'],
        runtimeFactory: ({required options, required features}) async {
          final runtime = _FakeRuntime(options, features: features);
          runtimes.add(runtime);
          return runtime;
        },
      );

      expect(session.hasStartedService, isFalse);
      expect(await session.callPublic('getHome'), 'getHome:0');
      expect(
        await session.callUi('submitLogin', arguments: const <Object?>['user']),
        'submitLogin:1',
      );
      expect(runtimes, hasLength(1));
      expect(
        runtimes.single.features.where(
          (features) => features.name.startsWith('plugin:'),
        ),
        hasLength(1),
      );
      expect(
        runtimes.single.features.expand((features) => features.methods),
        contains(
          isA<JsHostMethod>().having(
            (provider) => provider.name,
            'name',
            'fetch.request',
          ),
        ),
      );
      expect(
        runtimes.single.features
            .expand((mount) => mount.methods)
            .map((provider) => provider.name),
        containsAll(<String>[
          'webcrypto.subtle.digest',
          'webcrypto.subtle.hmac',
        ]),
      );
      expect(
        runtimes.single.features
            .expand((mount) => mount.scripts)
            .expand((script) => script.globals),
        contains('crypto'),
      );
      expect(
        runtimes.single.features.whereType<AxiosFeatures>().single.path,
        'packages/lemon_js/assets/js/axios.js',
      );
      expect(session.state, JsExtensionSessionState.active);
      expect(() => session.callPublic('submitLogin'), throwsStateError);

      await session.disable();
      expect(runtimes.single.closed, isTrue);
      expect(() => session.callPublic('getHome'), throwsStateError);
    },
  );

  test('restarted session rebuilds and initializes its Core runtime', () async {
    final runtimes = <_FakeRuntime>[];
    final session = JsExtensionSession(
      extension: _hybridExtension(JsExtensionManifest.parse(manifestSource)),
      grantedPermissions: const <String>['network', 'storage'],
      runtimeFactory: ({required options, required features}) async {
        final runtime = _FakeRuntime(options, features: features);
        runtimes.add(runtime);
        return runtime;
      },
    );

    expect(await session.callPublic('getHome'), 'getHome:0');
    await session.restart();
    expect(runtimes.single.closed, isTrue);
    expect(session.state, JsExtensionSessionState.inactive);

    expect(await session.callPublic('getHome'), 'getHome:0');
    expect(runtimes, hasLength(2));
    expect(runtimes.last.initialized, isTrue);
  });

  test('registry exposes service and flow views from one installation', () {
    final manifest = JsExtensionManifest.parse(manifestSource);
    final registry = JsExtensionRegistry();
    final installed = JsExtensionInstaller(registry: registry).install(
      _hybridExtension(manifest),
      grantedPermissions: const <String>['network', 'storage'],
      runtimeFactory: ({required options, required features}) async =>
          _FakeRuntime(options, features: features),
    );

    expect(registry.servicesForContract('content-source/v1'), [installed]);
    final flow = registry.findFlow('site.example1', 'authentication');
    expect(flow?.installed, same(installed));
    expect(flow?.route, 'authentication');
  });

  test('storage is isolated by extension id', () async {
    final storage = JsMemoryKvStore();
    await storage.set('session', 'one', namespace: 'site.one');
    await storage.set('session', 'two', namespace: 'site.two');

    expect(await storage.get('session', namespace: 'site.one'), 'one');
    expect(await storage.get('session', namespace: 'site.two'), 'two');
    await storage.clear(namespace: 'site.one');
    expect(await storage.get('session', namespace: 'site.one'), isNull);
    expect(await storage.get('session', namespace: 'site.two'), 'two');
  });

  test('route features inject default storage and the bound service', () {
    final manifest = JsExtensionManifest.parse(manifestSource);
    final session = JsExtensionSession(
      extension: _hybridExtension(manifest),
      grantedPermissions: const <String>['network', 'storage'],
      runtimeFactory: ({required options, required features}) async =>
          _FakeRuntime(options, features: features),
    );

    final features = session.featuresForRoute('authentication');
    final modules = features.expand((item) => item.modules).toList();
    expect(
      modules.map((module) => module.name),
      containsAll(<String>[
        'lemon_js_extensions/storage',
        'lemon_js_extensions/plugin_service',
      ]),
    );
    final bridgeSource = modules
        .singleWhere(
          (module) => module.name == 'lemon_js_extensions/plugin_service',
        )
        .source!;
    expect(bridgeSource, contains('call(method, ...args)'));
    expect(bridgeSource, isNot(contains('pluginId')));
  });

  test('optional host capabilities can all be disabled', () async {
    final runtimes = <_FakeRuntime>[];
    final session = JsExtensionSession(
      extension: _hybridExtension(JsExtensionManifest.parse(manifestSource)),
      grantedPermissions: const <String>['network', 'storage'],
      features: const JsExtensionFeatures.none(),
      runtimeFactory: ({required options, required features}) async {
        final runtime = _FakeRuntime(options, features: features);
        runtimes.add(runtime);
        return runtime;
      },
    );

    await session.callPublic('getHome');
    final features = runtimes.single.features;
    expect(features.expand((item) => item.methods), isEmpty);
    expect(
      session
          .featuresForRoute('authentication')
          .expand((item) => item.modules)
          .map((module) => module.name),
      isNot(contains('lemon_js_extensions/storage')),
    );
  });

  test('session rejects permissions not declared by manifest', () {
    final manifest = JsExtensionManifest.parse(manifestSource);
    expect(
      () => JsExtensionSession(
        extension: _hybridExtension(manifest),
        grantedPermissions: const <String>['camera'],
      ),
      throwsArgumentError,
    );
  });

  test(
    'flow runner launches interaction and retries service only once',
    () async {
      final manifest = JsExtensionManifest.parse(manifestSource);
      final responses = <Object?>[
        <String, Object?>{
          'status': 'interactionRequired',
          'interaction': <String, Object?>{
            'flow': 'authentication',
            'reason': 'sessionExpired',
          },
        },
        <String, Object?>{'status': 'ok', 'data': 'ready'},
      ];
      final registry = JsExtensionRegistry();
      JsExtensionInstaller(registry: registry).install(
        _hybridExtension(manifest),
        grantedPermissions: const <String>['network', 'storage'],
        runtimeFactory: ({required options, required features}) async =>
            _FakeRuntime(
              options,
              features: features,
              onCall: (_, _) => responses.removeAt(0),
            ),
      );
      var launches = 0;
      final runner = JsExtensionFlowRunner(
        registry: registry,
        launch: (flow, props) async {
          launches++;
          expect(flow.route, 'authentication');
          expect(props['reason'], 'sessionExpired');
          return const JsExtensionFlowResult.completed();
        },
      );

      final result = await runner.call('site.example1', 'getHome');

      expect(result.status, JsExtensionCallStatus.ok);
      expect(result.data, 'ready');
      expect(launches, 1);
      expect(responses, isEmpty);
    },
  );

  test('loads a hybrid package from assets', () async {
    final manifestWithResource = manifestSource.replaceFirst(
      '"permissions": ["network", "storage"]',
      '"resources": ["images/logo.png"],\n  '
          '"permissions": ["network", "storage"]',
    );
    final package = await JsExtensionPackage.asset(
      manifestAsset: 'extensions/demo/manifest.json',
      bundle: _MemoryAssetBundle(<String, String>{
        'extensions/demo/manifest.json': manifestWithResource,
        ..._hybridModuleFiles('extensions/demo/'),
        'extensions/demo/images/logo.png': 'image-bytes',
      }),
    );

    expect((await JsExtension.load(package)).kind, JsExtensionKind.hybrid);
    expect(
      package.resourceFiles['images/logo.png'],
      utf8.encode('image-bytes'),
    );
  });

  test('loads a hybrid package from files', () async {
    final directory = await Directory.systemTemp.createTemp('lemon_extension_');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/manifest.json').writeAsString(manifestSource);
    for (final module in _hybridModuleFiles().entries) {
      final file = File('${directory.path}/${module.key}');
      await file.parent.create(recursive: true);
      await file.writeAsString(module.value);
    }

    final package = await JsExtensionPackage.file(
      manifestPath: '${directory.path}/manifest.json',
    );

    expect((await JsExtension.load(package)).kind, JsExtensionKind.hybrid);
  });

  test('loads a hybrid package from network', () async {
    final files = <String, String>{
      'manifest.json': manifestSource,
      ..._hybridModuleFiles(),
    };
    final package = await JsExtensionPackage.network(
      manifestUrl: Uri.parse('https://example.test/plugin/manifest.json'),
      client: MockClient((request) async {
        final source =
            files[request.url.pathSegments.last == 'manifest.json'
                ? 'manifest.json'
                : request.url.pathSegments.skip(1).join('/')];
        return source == null
            ? http.Response('', 404)
            : http.Response.bytes(utf8.encode(source), 200);
      }),
    );

    expect((await JsExtension.load(package)).kind, JsExtensionKind.hybrid);
  });

  test('loads a hybrid package from ZIP bytes', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', manifestSource))
      ..addFile(ArchiveFile('images/logo.png', 4, <int>[0, 1, 2, 3]));
    for (final module in _hybridModuleFiles().entries) {
      archive.addFile(ArchiveFile.string(module.key, module.value));
    }

    final package = await JsExtensionPackage.zipBytes(
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );

    expect((await JsExtension.load(package)).kind, JsExtensionKind.hybrid);
    expect(package.resourceFiles['images/logo.png'], <int>[0, 1, 2, 3]);
  });

  test(
    'manager reports optional capabilities and rejects missing required',
    () async {
      final manager = JsExtensionManager(
        store: JsExtensionMemoryStore(),
        constraints: _extensionConstraints(),
        features: const JsExtensionFeatures.none(),
        runtimeFactory: ({required options, required features}) async =>
            _FakeRuntime(options, features: features),
      );
      String withCapabilities(String declaration) =>
          manifestSource.replaceFirst(
            '"permissions": ["network", "storage"]',
            '$declaration,\n  "permissions": ["network", "storage"]',
          );
      final optionalPackage = _hybridPackage(
        withCapabilities('''"capabilities": {
    "optional": {"network": 1, "cookieJar": 1}
  }'''),
      );

      final report = await manager.inspectPackage(optionalPackage);
      expect(report.canInstall, isTrue);
      expect(report.missingOptional, {'network': 1, 'cookieJar': 1});
      final installed = await manager.install(optionalPackage);
      expect(installed.capabilityReport?.missingOptional, {
        'network': 1,
        'cookieJar': 1,
      });

      final requiredPackage = _hybridPackage(
        withCapabilities('''"capabilities": {
    "required": {"crypto": 2}
  }''').replaceFirst('site.example1', 'site.required'),
      );
      await expectLater(
        manager.install(requiredPackage),
        throwsA(
          isA<JsExtensionCapabilityException>().having(
            (error) => error.report.missingRequired,
            'missingRequired',
            {'crypto': 2},
          ),
        ),
      );
      expect(await manager.store.load('site.required'), isNull);
    },
  );

  test('manager installs, calls by id and restores lazily', () async {
    final store = JsExtensionMemoryStore();
    final runtimes = <_FakeRuntime>[];
    Future<JsExtensionServiceRuntime> factory({
      required JsOptions options,
      required List<JsFeatures> features,
    }) async {
      final runtime = _FakeRuntime(options, features: features);
      runtimes.add(runtime);
      return runtime;
    }

    final first = JsExtensionManager(
      store: store,
      constraints: _extensionConstraints(),
      runtimeFactory: factory,
    );
    await first.install(
      _hybridPackage(manifestSource),
      grantedPermissions: const <String>['network', 'storage'],
    );
    expect(await first.call('site.example1', 'getHome'), 'getHome:0');
    expect(runtimes, hasLength(1));

    await first.disable('site.example1');
    final restored = JsExtensionManager(
      store: store,
      constraints: _extensionConstraints(),
      runtimeFactory: factory,
    );
    await restored.restore();

    expect(restored.extensions.single.state, JsExtensionManagerState.disabled);
    expect(runtimes, hasLength(1), reason: 'restore must keep Core lazy');
    await restored.enable('site.example1');
    expect(await restored.call('site.example1', 'getHome'), 'getHome:0');
    expect(runtimes, hasLength(2));
  });

  test('manager updates and rolls back a rejected replacement', () async {
    final store = JsExtensionMemoryStore();
    final manager = JsExtensionManager(
      store: store,
      constraints: _extensionConstraints(),
      runtimeFactory: ({required options, required features}) async =>
          _FakeRuntime(options, features: features),
    );
    await manager.install(
      _hybridPackage(manifestSource),
      grantedPermissions: const <String>['network', 'storage'],
    );
    final version2 = manifestSource
        .replaceFirst('"version": "1.0.0"', '"version": "2.0.0"')
        .replaceFirst('"versionCode": 10000', '"versionCode": 20000');
    await manager.update('site.example1', _hybridPackage(version2));
    expect(manager.find('site.example1')?.version, '2.0.0');

    final incompatible = version2
        .replaceFirst('"version": "2.0.0"', '"version": "3.0.0"')
        .replaceFirst('"versionCode": 20000', '"versionCode": 30000')
        .replaceFirst(
          '"permissions": ["network", "storage"]',
          '"permissions": ["storage"]',
        );
    await expectLater(
      manager.update('site.example1', _hybridPackage(incompatible)),
      throwsArgumentError,
    );

    expect(manager.find('site.example1')?.version, '2.0.0');
    expect((await store.load('site.example1'))?.record.version, '2.0.0');
  });

  test('manager rejects an update with a different extension id', () async {
    final store = JsExtensionMemoryStore();
    final manager = JsExtensionManager(
      store: store,
      constraints: _extensionConstraints(),
      runtimeFactory: ({required options, required features}) async =>
          _FakeRuntime(options, features: features),
    );
    await manager.install(_hybridPackage(manifestSource));
    final replacement = manifestSource
        .replaceFirst('"id": "site.example1"', '"id": "site.example2"')
        .replaceFirst('"versionCode": 10000', '"versionCode": 20000');

    await expectLater(
      manager.update('site.example1', _hybridPackage(replacement)),
      throwsArgumentError,
    );
    expect((await store.load('site.example1'))?.record.versionCode, 10000);
    expect(await store.load('site.example2'), isNull);
  });

  test('install cannot overwrite a stored id before restore', () async {
    final store = JsExtensionMemoryStore();
    final first = JsExtensionManager(
      store: store,
      constraints: _extensionConstraints(),
      runtimeFactory: ({required options, required features}) async =>
          _FakeRuntime(options, features: features),
    );
    await first.install(_hybridPackage(manifestSource));
    final second = JsExtensionManager(
      store: store,
      constraints: _extensionConstraints(),
      runtimeFactory: ({required options, required features}) async =>
          _FakeRuntime(options, features: features),
    );

    await expectLater(
      second.install(_hybridPackage(manifestSource)),
      throwsStateError,
    );
    expect((await store.load('site.example1'))?.record.versionCode, 10000);
  });

  test('manager migrates versioned KV before activating an update', () async {
    final store = JsExtensionMemoryStore();
    final storage = JsMemoryKvStore();
    await storage.set('token', 'old', namespace: 'site.example1');
    final migrations = <List<Object?>>[];
    final manager = JsExtensionManager(
      store: store,
      storage: storage,
      constraints: _extensionConstraints(),
      runtimeFactory: ({required options, required features}) async =>
          _FakeRuntime(
            options,
            features: features,
            onCall: (method, arguments) async {
              if (method == 'migrateStorage') {
                migrations.add(arguments);
                await storage.set('token', 'new', namespace: 'site.example1');
              }
              return null;
            },
          ),
    );
    await manager.install(_hybridPackage(manifestSource));
    final next = manifestSource
        .replaceFirst('"version": "1.0.0"', '"version": "2.0.0"')
        .replaceFirst(
          '"versionCode": 10000',
          '"versionCode": 20000,\n  "storageVersion": 1',
        )
        .replaceFirst(
          '"contract": "content-source/v1",',
          '"contract": "content-source/v1",\n    "storageMigrationExport": "migrateStorage",',
        );

    await manager.update('site.example1', _hybridPackage(next));

    expect(migrations, <List<Object?>>[
      <Object?>[0, 1],
    ]);
    expect(await storage.get('token', namespace: 'site.example1'), 'new');
    expect((await store.load('site.example1'))?.record.storageVersion, 1);
  });

  test('failed KV migration restores the previous namespace', () async {
    final storage = JsMemoryKvStore();
    await storage.set('token', 'old', namespace: 'site.example1');
    final manager = JsExtensionManager(
      store: JsExtensionMemoryStore(),
      storage: storage,
      constraints: _extensionConstraints(),
      runtimeFactory: ({required options, required features}) async =>
          _FakeRuntime(
            options,
            features: features,
            onCall: (method, arguments) async {
              if (method == 'migrateStorage') {
                await storage.set(
                  'token',
                  'partial',
                  namespace: 'site.example1',
                );
                throw StateError('migration failed');
              }
              return null;
            },
          ),
    );
    await manager.install(_hybridPackage(manifestSource));
    final next = manifestSource
        .replaceFirst('"version": "1.0.0"', '"version": "2.0.0"')
        .replaceFirst(
          '"versionCode": 10000',
          '"versionCode": 20000,\n  "storageVersion": 1',
        )
        .replaceFirst(
          '"contract": "content-source/v1",',
          '"contract": "content-source/v1",\n    "storageMigrationExport": "migrateStorage",',
        );

    await expectLater(
      manager.update('site.example1', _hybridPackage(next)),
      throwsStateError,
    );
    expect(await storage.get('token', namespace: 'site.example1'), 'old');
    expect(manager.find('site.example1')?.versionCode, 10000);
  });

  test(
    'manager requires an id when a contract has multiple providers',
    () async {
      final manager = JsExtensionManager(
        store: JsExtensionMemoryStore(),
        constraints: _extensionConstraints(),
        runtimeFactory: ({required options, required features}) async =>
            _FakeRuntime(options, features: features),
      );
      await manager.install(
        _hybridPackage(manifestSource),
        grantedPermissions: const <String>['network', 'storage'],
      );
      await manager.install(
        _hybridPackage(
          manifestSource
              .replaceAll('site.example1', 'site.example2')
              .replaceFirst('站点 1', '站点 2'),
        ),
        grantedPermissions: const <String>['network', 'storage'],
      );

      expect(
        () => manager.callContract('content-source/v1', 'getHome'),
        throwsStateError,
      );
      expect(
        await manager.callContract(
          'content-source/v1',
          'getHome',
          pluginId: 'site.example2',
        ),
        'getHome:0',
      );
    },
  );

  test('file store restores records in a new manager instance', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lemon_extension_store_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final first = JsExtensionManager(
      store: JsExtensionFileStore(directoryPath: directory.path),
      constraints: _extensionConstraints(),
      runtimeFactory: ({required options, required features}) async =>
          _FakeRuntime(options, features: features),
    );
    await first.install(
      _hybridPackage(manifestSource),
      grantedPermissions: const <String>['storage'],
    );

    final restored = JsExtensionManager(
      store: JsExtensionFileStore(directoryPath: directory.path),
      constraints: _extensionConstraints(),
      runtimeFactory: ({required options, required features}) async =>
          _FakeRuntime(options, features: features),
    );
    await restored.restore();

    expect(restored.extensions.single.id, 'site.example1');
    expect(restored.extensions.single.version, '1.0.0');
  });

  test('restore isolates a broken extension record', () async {
    final store = JsExtensionMemoryStore();
    final now = DateTime.now().toUtc();
    await store.save(
      JsExtensionStoreEntry(
        record: JsExtensionInstallRecord(
          id: 'site.broken',
          name: 'Broken',
          description: 'Broken test plugin',
          version: '1.0.0',
          versionCode: 10000,
          compatibilityCode: 'lemon-content-source-v1',
          state: JsExtensionInstallState.enabled,
          grantedPermissions: const <String>[],
          installedAt: now,
          updatedAt: now,
        ),
        package: JsExtensionPackage(manifestSource: '{not json'),
      ),
    );
    final manager = JsExtensionManager(
      store: store,
      constraints: _extensionConstraints(),
    );

    await manager.restore();

    expect(manager.find('site.broken')?.state, JsExtensionManagerState.broken);
    expect(manager.find('site.broken')?.error, isNotNull);
  });

  test(
    'extension constraint accepts optional subsets and rejects missing required',
    () {
      final constraints = _constraints();
      final valid = JsExtensionManifest.parse(manifestSource);
      expect(() => constraints.validate(valid), returnsNormally);

      final missing = JsExtensionManifest.parse(
        manifestSource.replaceFirst('"getHome"', '"search"'),
      );
      expect(() => constraints.validate(missing), throwsFormatException);
    },
  );

  test('loads recursive bare Core and UI entries from assets', () async {
    final bundle = _MemoryAssetBundle(<String, String>{
      'plugins/core/main.mjs':
          "import './helper.mjs'; export function getHome() {}",
      'plugins/core/helper.mjs': 'export const value = 1;',
      'plugins/ui/main.mjs': "import './card.mjs'; export default {};",
      'plugins/ui/card.mjs': 'export const card = {};',
    });
    final core = await JsExtensionPackage.moduleAsset(
      path: 'plugins/core/main.mjs',
      bundle: bundle,
      adapter: _coreAdapter(),
    );
    final ui = await JsExtensionPackage.moduleAsset(
      path: 'plugins/ui/main.mjs',
      bundle: bundle,
      adapter: _uiAdapter(),
    );

    expect(
      core.serviceModules.keys,
      containsAll(<String>['main.mjs', 'helper.mjs']),
    );
    expect(ui.uiModules.keys, containsAll(<String>['main.mjs', 'card.mjs']));
    expect((await JsExtension.load(core)).kind, JsExtensionKind.js);
    expect((await JsExtension.load(ui)).kind, JsExtensionKind.ui);
  });

  test('manager compares versionCode and update descriptor', () async {
    final store = JsExtensionMemoryStore();
    final manager = JsExtensionManager(
      store: store,
      constraints: _extensionConstraints(),
      runtimeFactory: ({required options, required features}) async =>
          _FakeRuntime(options, features: features),
    );
    final initial = manifestSource.replaceFirst(
      '"version": "1.0.0",',
      '"version": "1.0.0",\n  "updateUrl": "https://example.test/update.json",',
    );
    await manager.install(
      _hybridPackage(initial),
      grantedPermissions: const <String>['network', 'storage'],
    );
    final client = MockClient(
      (request) async => http.Response.bytes(
        utf8.encode('''
{"id":"site.example1","version":"2.0.0","versionCode":20000,
 "compatibilityCode":"lemon-content-source-v1",
 "downloadUrl":"https://example.test/plugin.zip"}
'''),
        200,
      ),
    );

    final check = await manager.checkForUpdate('site.example1', client: client);
    expect(check.available, isTrue);
    expect(check.info.versionCode, 20000);

    await expectLater(
      manager.update('site.example1', _hybridPackage(initial)),
      throwsStateError,
    );
  });

  test('persists JSUI resource references in unified packages', () {
    final package = JsExtensionPackage(
      manifestSource: manifestSource,
      serviceModules: _hybridPackage(manifestSource).serviceModules,
      uiModules: _hybridPackage(manifestSource).uiModules,
      uiResources: const <String, JsUiResourceReference>{
        'logo': JsUiResourceReference(
          uri: 'https://example.test/logo.png',
          kind: JsUiResourceKind.network,
          mimeType: 'image/png',
        ),
      },
    );

    final restored = JsExtensionPackage.fromMap(package.toMap());
    expect(restored.uiResources['logo']?.mimeType, 'image/png');
    expect(
      restored.buildUiBundle(restored.manifest).resources,
      contains('logo'),
    );
  });

  test('persists embedded non-JavaScript package resources', () {
    final bytes = Uint8List.fromList(<int>[0, 1, 2, 255]);
    final package = JsExtensionPackage(
      manifestSource: manifestSource,
      serviceModules: _hybridPackage(manifestSource).serviceModules,
      uiModules: _hybridPackage(manifestSource).uiModules,
      resourceFiles: <String, Uint8List>{'images/logo.png': bytes},
    );

    final restored = JsExtensionPackage.fromMap(package.toMap());
    expect(restored.resourceFiles['images/logo.png'], bytes);
    final reference = restored
        .buildUiBundle(restored.manifest)
        .resources['images/logo.png'];
    expect(reference?.kind, JsUiResourceKind.data);
    expect(reference?.uri, startsWith('data:image/png;base64,'));
  });

  test(
    'failed Core runtime is discarded and rebuilt on the next call',
    () async {
      final runtimes = <_FakeRuntime>[];
      var creations = 0;
      final session = JsExtensionSession(
        extension: _hybridExtension(JsExtensionManifest.parse(manifestSource)),
        storage: JsMemoryKvStore(),
        grantedPermissions: const <String>['network', 'storage'],
        runtimeFactory: ({required options, required features}) async {
          creations++;
          final runtime = _FakeRuntime(
            options,
            features: features,
            onCall: (_, _) {
              if (creations == 1) throw const JsRuntimeCrashException();
              return 'recovered';
            },
          );
          runtimes.add(runtime);
          return runtime;
        },
      );

      await expectLater(
        session.callPublic('getHome'),
        throwsA(isA<JsRuntimeCrashException>()),
      );
      expect(session.state, JsExtensionSessionState.failed);
      expect(runtimes.first.closed, isTrue);

      expect(await session.callPublic('getHome'), 'recovered');
      expect(creations, 2);
      expect(session.state, JsExtensionSessionState.active);
    },
  );
}

Map<String, String> _hybridModuleFiles([String prefix = '']) =>
    <String, String>{
      '${prefix}service/main.mjs': '''
export function getHome() { return []; }
export function submitLogin() { return true; }
''',
      '${prefix}ui/authentication.mjs': 'export default {};',
    };

JsExtensionPackage _hybridPackage(String manifestSource) {
  final modules = _hybridModuleFiles();
  return JsExtensionPackage(
    manifestSource: manifestSource,
    serviceModules: <String, String>{
      'service/main.mjs': modules['service/main.mjs']!,
    },
    uiModules: <String, String>{
      'ui/authentication.mjs': modules['ui/authentication.mjs']!,
    },
  );
}

List<JsExtensionConstraint> _extensionConstraints() => <JsExtensionConstraint>[
  JsExtensionConstraint(
    compatibilityCode: 'lemon-content-source-v1',
    requiredPublicExports: const <String>{'getHome'},
  ),
];

JsExtensionConstraints _constraints() =>
    JsExtensionConstraints(_extensionConstraints());

final class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final source = files[key];
    if (source == null) throw StateError('Missing test asset: $key');
    final bytes = Uint8List.fromList(utf8.encode(source));
    return ByteData.sublistView(bytes);
  }
}

JsPlugin _servicePlugin(JsExtensionManifest manifest) {
  return JsPlugin(
    manifest: JsPluginManifest(
      id: manifest.id,
      version: manifest.version,
      entry: '${manifest.id}/${manifest.service!.entry}',
      exports: const <String>['getHome', 'submitLogin'],
    ),
    modules: <JsPluginModule>[
      JsPluginModule(
        name: '${manifest.id}/${manifest.service!.entry}',
        source: '''
export function getHome() { return []; }
export function submitLogin() { return true; }
''',
      ),
    ],
  );
}

JsExtensionCoreAdapter _coreAdapter() => const JsExtensionCoreAdapter(
  id: 'legacy.core',
  name: 'Legacy Core',
  description: 'Legacy Core test plugin',
  version: '1.0.0',
  versionCode: 10000,
  compatibilityCode: 'lemon-content-source-v1',
  contract: 'content-source/v1',
  publicExports: <String>['getHome'],
);

JsExtensionUiAdapter _uiAdapter() => const JsExtensionUiAdapter(
  id: 'legacy.ui',
  name: 'Legacy UI',
  description: 'Legacy UI test plugin',
  version: '1.0.0',
  versionCode: 10000,
  compatibilityCode: 'lemon-miniapp-v1',
);

JsUiBundle _uiBundle(JsExtensionManifest manifest) {
  return JsUiBundle.sources(
    id: manifest.id,
    version: manifest.version,
    entry: 'ui/authentication.mjs',
    modules: const <String, String>{
      'ui/authentication.mjs': 'export default {};',
    },
  );
}

JsExtension _hybridExtension(JsExtensionManifest manifest) {
  return JsExtension.hybrid(
    manifest: manifest,
    service: JsExtensionServiceComponent(
      plugin: _servicePlugin(manifest),
      contract: 'content-source/v1',
      publicExports: const <String>['getHome'],
      uiExports: const <String>['submitLogin'],
    ),
    ui: JsExtensionUiComponent(
      bundle: _uiBundle(manifest),
      routes: manifest.ui!.routes,
    ),
  );
}

typedef _CallHandler = Object? Function(String method, List<Object?> args);

final class _FakeRuntime implements JsExtensionServiceRuntime {
  _FakeRuntime(this.options, {required this.features, this.onCall});

  final JsOptions options;
  final List<JsFeatures> features;
  final _CallHandler? onCall;
  bool closed = false;
  bool initialized = false;

  @override
  Future<void> validatePlugin(JsPlugin plugin, {Duration? timeout}) async {}

  @override
  Future<Object?> initPlugin(
    JsPlugin plugin, {
    Map<String, Object?> context = const <String, Object?>{},
    Duration? timeout,
  }) async {
    initialized = true;
    return null;
  }

  @override
  Future<Object?> callPluginExport(
    JsPlugin plugin,
    String method,
    List<Object?> args, {
    Duration? timeout,
  }) async {
    if (!initialized || closed) throw StateError('runtime is unavailable');
    return onCall?.call(method, args) ?? '$method:${args.length}';
  }

  @override
  Future<Object?> disposePlugin(JsPlugin plugin, {Duration? timeout}) async =>
      null;

  @override
  Future<void> close() async {
    closed = true;
  }
}
