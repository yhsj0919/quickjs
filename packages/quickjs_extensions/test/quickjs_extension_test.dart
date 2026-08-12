import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quickjs_extensions/quickjs_extensions.dart';

void main() {
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
    final manifest = QuickjsExtensionManifest.parse(manifestSource);

    expect(manifest.id, 'site.example1');
    expect(manifest.service?.contract, 'content-source/v1');
    expect(manifest.ui?.routes.keys, contains('authentication'));
    expect(
      QuickjsExtensionManifest.parse(manifest.toJson()).toMap(),
      manifest.toMap(),
    );
  });

  test('rejects a flow referencing a missing route', () {
    expect(
      () => QuickjsExtensionManifest.parse(
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
      () => QuickjsExtensionManifest.parse(
        manifestSource.replaceFirst('service/main.mjs', '../service/main.mjs'),
      ),
      throwsFormatException,
    );
  });

  test('creates one hybrid extension with matching service and UI', () {
    final manifest = QuickjsExtensionManifest.parse(manifestSource);
    final extension = _hybridExtension(manifest);

    expect(extension.kind, QuickjsExtensionKind.hybrid);
    expect(extension.id, 'site.example1');
  });

  test('loads a unified package into one hybrid extension', () async {
    final extension = await QuickjsExtension.load(
      QuickjsExtensionPackage(
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

    expect(extension.kind, QuickjsExtensionKind.hybrid);
    expect(
      extension.service?.plugin.manifest.entry,
      'site.example1/service/main.mjs',
    );
    expect(extension.ui?.routes.keys, ['authentication']);
  });

  test(
    'session keeps one lazy service runtime and restricts exports',
    () async {
      final manifest = QuickjsExtensionManifest.parse(manifestSource);
      final runtimes = <_FakeRuntime>[];
      final session = QuickjsExtensionSession(
        extension: _hybridExtension(manifest),
        grantedPermissions: const <String>['network', 'storage'],
        runtimeFactory: (options) async {
          final runtime = _FakeRuntime(options);
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
        runtimes.single.options.mounts.whereType<QuickjsPluginMount>(),
        hasLength(1),
      );
      expect(session.state, QuickjsExtensionSessionState.active);
      expect(() => session.callPublic('submitLogin'), throwsStateError);

      await session.disable();
      expect(runtimes.single.closed, isTrue);
      expect(() => session.callPublic('getHome'), throwsStateError);
    },
  );

  test('registry exposes service and flow views from one installation', () {
    final manifest = QuickjsExtensionManifest.parse(manifestSource);
    final registry = QuickjsExtensionRegistry();
    final installed = QuickjsExtensionInstaller(registry: registry).install(
      _hybridExtension(manifest),
      grantedPermissions: const <String>['network', 'storage'],
      runtimeFactory: (options) async => _FakeRuntime(options),
    );

    expect(registry.servicesForContract('content-source/v1'), [installed]);
    final flow = registry.findFlow('site.example1', 'authentication');
    expect(flow?.installed, same(installed));
    expect(flow?.route, 'authentication');
  });

  test('storage is isolated by extension id', () async {
    final storage = InMemoryQuickjsExtensionStorage();
    await storage.set('session', 'one', namespace: 'site.one');
    await storage.set('session', 'two', namespace: 'site.two');

    expect(await storage.get('session', namespace: 'site.one'), 'one');
    expect(await storage.get('session', namespace: 'site.two'), 'two');
    await storage.clear(namespace: 'site.one');
    expect(await storage.get('session', namespace: 'site.one'), isNull);
    expect(await storage.get('session', namespace: 'site.two'), 'two');
  });

  test('route mounts inject storage and bound service without plugin id', () {
    final manifest = QuickjsExtensionManifest.parse(manifestSource);
    final session = QuickjsExtensionSession(
      extension: _hybridExtension(manifest),
      grantedPermissions: const <String>['network', 'storage'],
      runtimeFactory: (options) async => _FakeRuntime(options),
    );

    final mounts = session.mountsForRoute('authentication');
    final modules = mounts.expand((mount) => mount.modules).toList();
    expect(
      modules.map((module) => module.specifier),
      containsAll(<String>[
        'quickjs_extensions/storage',
        'quickjs_extensions/plugin_service',
      ]),
    );
    final bridgeSource = modules
        .singleWhere(
          (module) => module.specifier == 'quickjs_extensions/plugin_service',
        )
        .source!;
    expect(bridgeSource, contains('call(method, ...args)'));
    expect(bridgeSource, isNot(contains('pluginId')));
  });

  test('session rejects permissions not declared by manifest', () {
    final manifest = QuickjsExtensionManifest.parse(manifestSource);
    expect(
      () => QuickjsExtensionSession(
        extension: _hybridExtension(manifest),
        grantedPermissions: const <String>['camera'],
      ),
      throwsArgumentError,
    );
  });

  test(
    'flow runner launches interaction and retries service only once',
    () async {
      final manifest = QuickjsExtensionManifest.parse(manifestSource);
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
      final registry = QuickjsExtensionRegistry();
      QuickjsExtensionInstaller(registry: registry).install(
        _hybridExtension(manifest),
        grantedPermissions: const <String>['network', 'storage'],
        runtimeFactory: (options) async =>
            _FakeRuntime(options, onCall: (_, _) => responses.removeAt(0)),
      );
      var launches = 0;
      final runner = QuickjsExtensionFlowRunner(
        registry: registry,
        launch: (flow, props) async {
          launches++;
          expect(flow.route, 'authentication');
          expect(props['reason'], 'sessionExpired');
          return const QuickjsExtensionFlowResult.completed();
        },
      );

      final result = await runner.call('site.example1', 'getHome');

      expect(result.status, QuickjsExtensionCallStatus.ok);
      expect(result.data, 'ready');
      expect(launches, 1);
      expect(responses, isEmpty);
    },
  );

  test('loads a hybrid package from assets', () async {
    final package = await QuickjsExtensionPackage.asset(
      manifestAsset: 'extensions/demo/manifest.json',
      bundle: _MemoryAssetBundle(<String, String>{
        'extensions/demo/manifest.json': manifestSource,
        ..._hybridModuleFiles('extensions/demo/'),
      }),
    );

    expect(
      (await QuickjsExtension.load(package)).kind,
      QuickjsExtensionKind.hybrid,
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

    final package = await QuickjsExtensionPackage.file(
      manifestPath: '${directory.path}/manifest.json',
    );

    expect(
      (await QuickjsExtension.load(package)).kind,
      QuickjsExtensionKind.hybrid,
    );
  });

  test('loads a hybrid package from network', () async {
    final files = <String, String>{
      'manifest.json': manifestSource,
      ..._hybridModuleFiles(),
    };
    final package = await QuickjsExtensionPackage.network(
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

    expect(
      (await QuickjsExtension.load(package)).kind,
      QuickjsExtensionKind.hybrid,
    );
  });

  test('loads a hybrid package from ZIP bytes', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', manifestSource));
    for (final module in _hybridModuleFiles().entries) {
      archive.addFile(ArchiveFile.string(module.key, module.value));
    }

    final package = await QuickjsExtensionPackage.zipBytes(
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );

    expect(
      (await QuickjsExtension.load(package)).kind,
      QuickjsExtensionKind.hybrid,
    );
  });

  test('manager installs, calls by id and restores lazily', () async {
    final store = InMemoryQuickjsExtensionStore();
    final runtimes = <_FakeRuntime>[];
    Future<QuickjsExtensionServiceRuntime> factory(
      QuickjsRuntimeOptions options,
    ) async {
      final runtime = _FakeRuntime(options);
      runtimes.add(runtime);
      return runtime;
    }

    final first = QuickjsExtensionManager(
      store: store,
      compatibilityRegistry: _compatibilityRegistry(),
      runtimeFactory: factory,
    );
    await first.install(
      _hybridPackage(manifestSource),
      grantedPermissions: const <String>['network', 'storage'],
    );
    expect(await first.call('site.example1', 'getHome'), 'getHome:0');
    expect(runtimes, hasLength(1));

    await first.disable('site.example1');
    final restored = QuickjsExtensionManager(
      store: store,
      compatibilityRegistry: _compatibilityRegistry(),
      runtimeFactory: factory,
    );
    await restored.restore();

    expect(
      restored.extensions.single.state,
      ManagedQuickjsExtensionState.disabled,
    );
    expect(runtimes, hasLength(1), reason: 'restore must keep Core lazy');
    await restored.enable('site.example1');
    expect(await restored.call('site.example1', 'getHome'), 'getHome:0');
    expect(runtimes, hasLength(2));
  });

  test('manager updates and rolls back a rejected replacement', () async {
    final store = InMemoryQuickjsExtensionStore();
    final manager = QuickjsExtensionManager(
      store: store,
      compatibilityRegistry: _compatibilityRegistry(),
      runtimeFactory: (options) async => _FakeRuntime(options),
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

  test(
    'manager requires an id when a contract has multiple providers',
    () async {
      final manager = QuickjsExtensionManager(
        store: InMemoryQuickjsExtensionStore(),
        compatibilityRegistry: _compatibilityRegistry(),
        runtimeFactory: (options) async => _FakeRuntime(options),
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
    final first = QuickjsExtensionManager(
      store: QuickjsExtensionFileStore(directoryPath: directory.path),
      compatibilityRegistry: _compatibilityRegistry(),
      runtimeFactory: (options) async => _FakeRuntime(options),
    );
    await first.install(
      _hybridPackage(manifestSource),
      grantedPermissions: const <String>['storage'],
    );

    final restored = QuickjsExtensionManager(
      store: QuickjsExtensionFileStore(directoryPath: directory.path),
      compatibilityRegistry: _compatibilityRegistry(),
      runtimeFactory: (options) async => _FakeRuntime(options),
    );
    await restored.restore();

    expect(restored.extensions.single.id, 'site.example1');
    expect(restored.extensions.single.version, '1.0.0');
  });

  test('restore isolates a broken extension record', () async {
    final store = InMemoryQuickjsExtensionStore();
    final now = DateTime.now().toUtc();
    await store.save(
      StoredQuickjsExtension(
        record: QuickjsExtensionInstallRecord(
          id: 'site.broken',
          name: 'Broken',
          description: 'Broken test plugin',
          version: '1.0.0',
          versionCode: 10000,
          compatibilityCode: 'lemon-content-source-v1',
          state: QuickjsExtensionInstallState.enabled,
          grantedPermissions: const <String>[],
          installedAt: now,
          updatedAt: now,
        ),
        package: QuickjsExtensionPackage(manifestSource: '{not json'),
      ),
    );
    final manager = QuickjsExtensionManager(
      store: store,
      compatibilityRegistry: _compatibilityRegistry(),
    );

    await manager.restore();

    expect(
      manager.find('site.broken')?.state,
      ManagedQuickjsExtensionState.broken,
    );
    expect(manager.find('site.broken')?.error, isNotNull);
  });

  test(
    'compatibility policy accepts optional subsets and rejects missing required',
    () {
      final policy = _compatibilityRegistry();
      final valid = QuickjsExtensionManifest.parse(manifestSource);
      expect(() => policy.validate(valid), returnsNormally);

      final missing = QuickjsExtensionManifest.parse(
        manifestSource.replaceFirst('"getHome"', '"search"'),
      );
      expect(() => policy.validate(missing), throwsFormatException);
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
    final core = await QuickjsExtensionPackage.coreAsset(
      entryAsset: 'plugins/core/main.mjs',
      bundle: bundle,
      adapter: _coreAdapter(),
    );
    final ui = await QuickjsExtensionPackage.uiAsset(
      entryAsset: 'plugins/ui/main.mjs',
      bundle: bundle,
      adapter: _uiAdapter(),
    );

    expect(
      core.serviceModules.keys,
      containsAll(<String>['main.mjs', 'helper.mjs']),
    );
    expect(ui.uiModules.keys, containsAll(<String>['main.mjs', 'card.mjs']));
    expect((await QuickjsExtension.load(core)).kind, QuickjsExtensionKind.js);
    expect((await QuickjsExtension.load(ui)).kind, QuickjsExtensionKind.ui);
  });

  test('manager compares versionCode and update descriptor', () async {
    final store = InMemoryQuickjsExtensionStore();
    final manager = QuickjsExtensionManager(
      store: store,
      compatibilityRegistry: _compatibilityRegistry(),
      runtimeFactory: (options) async => _FakeRuntime(options),
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
    final package = QuickjsExtensionPackage(
      manifestSource: manifestSource,
      serviceModules: _hybridPackage(manifestSource).serviceModules,
      uiModules: _hybridPackage(manifestSource).uiModules,
      uiResources: const <String, QuickjsUiResourceReference>{
        'logo': QuickjsUiResourceReference(
          location: 'https://example.test/logo.png',
          kind: QuickjsUiResourceKind.network,
          mimeType: 'image/png',
        ),
      },
    );

    final restored = QuickjsExtensionPackage.fromMap(package.toMap());
    expect(restored.uiResources['logo']?.mimeType, 'image/png');
    expect(
      restored.buildUiBundle(restored.manifest).resources,
      contains('logo'),
    );
  });
}

Map<String, String> _hybridModuleFiles([String prefix = '']) =>
    <String, String>{
      '${prefix}service/main.mjs': '''
export function getHome() { return []; }
export function submitLogin() { return true; }
''',
      '${prefix}ui/authentication.mjs': 'export default {};',
    };

QuickjsExtensionPackage _hybridPackage(String manifestSource) {
  final modules = _hybridModuleFiles();
  return QuickjsExtensionPackage(
    manifestSource: manifestSource,
    serviceModules: <String, String>{
      'service/main.mjs': modules['service/main.mjs']!,
    },
    uiModules: <String, String>{
      'ui/authentication.mjs': modules['ui/authentication.mjs']!,
    },
  );
}

QuickjsExtensionCompatibilityRegistry _compatibilityRegistry() =>
    QuickjsExtensionCompatibilityRegistry(<QuickjsExtensionCompatibilityPolicy>[
      QuickjsExtensionCompatibilityPolicy(
        compatibilityCode: 'lemon-content-source-v1',
        requiredPublicExports: const <String>{'getHome'},
      ),
    ]);

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

QuickjsPlugin _servicePlugin(QuickjsExtensionManifest manifest) {
  return QuickjsPlugin(
    manifest: QuickjsPluginManifest(
      id: manifest.id,
      version: manifest.version,
      entry: '${manifest.id}/${manifest.service!.entry}',
      exports: const <String>['getHome', 'submitLogin'],
    ),
    modules: <QuickjsPluginModule>[
      QuickjsPluginModule(
        specifier: '${manifest.id}/${manifest.service!.entry}',
        source: '''
export function getHome() { return []; }
export function submitLogin() { return true; }
''',
      ),
    ],
  );
}

QuickjsCorePackageAdapter _coreAdapter() => const QuickjsCorePackageAdapter(
  id: 'legacy.core',
  name: 'Legacy Core',
  description: 'Legacy Core test plugin',
  version: '1.0.0',
  versionCode: 10000,
  compatibilityCode: 'lemon-content-source-v1',
  contract: 'content-source/v1',
  publicExports: <String>['getHome'],
);

QuickjsUiPackageAdapter _uiAdapter() => const QuickjsUiPackageAdapter(
  id: 'legacy.ui',
  name: 'Legacy UI',
  description: 'Legacy UI test plugin',
  version: '1.0.0',
  versionCode: 10000,
  compatibilityCode: 'lemon-miniapp-v1',
);

QuickjsUiBundle _uiBundle(QuickjsExtensionManifest manifest) {
  return QuickjsUiBundle.compiled(
    id: manifest.id,
    version: manifest.version,
    entry: 'ui/authentication.mjs',
    modules: const <String, String>{
      'ui/authentication.mjs': 'export default {};',
    },
  );
}

QuickjsExtension _hybridExtension(QuickjsExtensionManifest manifest) {
  return QuickjsExtension.hybrid(
    manifest: manifest,
    service: QuickjsServiceComponent(
      plugin: _servicePlugin(manifest),
      contract: 'content-source/v1',
      publicExports: const <String>['getHome'],
      uiExports: const <String>['submitLogin'],
    ),
    ui: QuickjsUiComponent(
      bundle: _uiBundle(manifest),
      routes: manifest.ui!.routes,
    ),
  );
}

typedef _CallHandler = Object? Function(String method, List<Object?> args);

final class _FakeRuntime implements QuickjsExtensionServiceRuntime {
  _FakeRuntime(this.options, {this.onCall});

  final QuickjsRuntimeOptions options;
  final _CallHandler? onCall;
  bool closed = false;
  bool initialized = false;

  @override
  Future<void> validatePlugin(
    QuickjsPlugin plugin, {
    Duration? timeout,
  }) async {}

  @override
  Future<Object?> initPlugin(
    QuickjsPlugin plugin, {
    Map<String, Object?> context = const <String, Object?>{},
    Duration? timeout,
  }) async {
    initialized = true;
    return null;
  }

  @override
  Future<Object?> callPlugin(
    QuickjsPlugin plugin,
    String method,
    List<Object?> args, {
    Duration? timeout,
  }) async {
    if (!initialized || closed) throw StateError('runtime is unavailable');
    return onCall?.call(method, args) ?? '$method:${args.length}';
  }

  @override
  Future<Object?> disposePlugin(
    QuickjsPlugin plugin, {
    Duration? timeout,
  }) async => null;

  @override
  Future<void> close() async {
    closed = true;
  }
}
