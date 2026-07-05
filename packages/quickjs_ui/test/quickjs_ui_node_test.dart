import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs_ui/quickjs_ui.dart';
import 'package:quickjs_ui/src/renderer/quickjs_ui_event_ingress.dart';

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

final class _RouteCaptureObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  test('parses serializable ui nodes', () {
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Column',
      'gap': 8,
      'children': <Object?>[
        <String, Object?>{'type': 'Text', 'data': 'Hello'},
      ],
    });

    expect(node.type, 'Column');
    expect(node.props['gap'], 8);
    expect(node.children.single.type, 'Text');
    expect(node.toMap(), <String, Object?>{
      'type': 'Column',
      'gap': 8,
      'children': <Object?>[
        <String, Object?>{'type': 'Text', 'data': 'Hello'},
      ],
    });
  });

  test('parses Flutter-style child property', () {
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'ElevatedButton',
      'child': <String, Object?>{'type': 'Text', 'data': 'Add'},
      'onPressed': <String, Object?>{'action': 'increment'},
    });

    expect(node.children.single.type, 'Text');
    expect(node.props['onPressed'], <String, Object?>{'action': 'increment'});
    expect(node.toMap(), <String, Object?>{
      'type': 'ElevatedButton',
      'onPressed': <String, Object?>{'action': 'increment'},
      'children': <Object?>[
        <String, Object?>{'type': 'Text', 'data': 'Add'},
      ],
    });
  });

  test('rejects overly deep node trees before stack overflow', () {
    Map<String, Object?> node = <String, Object?>{
      'type': 'Text',
      'data': 'leaf',
    };
    for (var index = 0; index <= QuickjsUiNode.maxDepth + 1; index++) {
      node = <String, Object?>{'type': 'Padding', 'child': node};
    }

    expect(
      () => QuickjsUiNode.fromMap(node),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'quickjs_ui node tree is too deep',
        ),
      ),
    );
  });

  test('parses shared Flutter-style props', () {
    expect(QuickjsUiProps.color('#336699'), const Color(0xff336699));
    expect(QuickjsUiProps.color('0x80336699'), const Color(0x80336699));
    expect(QuickjsUiProps.color(0xff112233), const Color(0xff112233));
    expect(QuickjsUiProps.edgeInsets(8), const EdgeInsets.all(8));
    expect(
      QuickjsUiProps.edgeInsets(<String, Object?>{
        'horizontal': 12,
        'vertical': 4,
        'left': 2,
      }),
      const EdgeInsets.fromLTRB(2, 4, 12, 4),
    );
    expect(QuickjsUiProps.borderRadius(6), BorderRadius.circular(6));
    expect(
      QuickjsUiProps.borderRadius(<String, Object?>{'topLeft': 4}),
      const BorderRadius.only(topLeft: Radius.circular(4)),
    );
    expect(QuickjsUiProps.fontWeight('w700'), FontWeight.w700);
    expect(QuickjsUiProps.fontWeight(600), FontWeight.w600);
    expect(QuickjsUiProps.opacity(2), 1);
    expect(QuickjsUiProps.opacity(-1), 0);
  });

  test('loads bundle manifest from memory resources', () async {
    final bundle = await QuickjsUiBundle.fromManifestSource(
      '''
{
  "id": "quickjs_ui_bundle_counter",
  "version": "0.2.0",
  "entry": "pages/counter.mjs",
  "permissions": ["toast", "app.customEcho"],
  "modules": [
    "pages/counter.mjs",
    "components/label.mjs"
  ]
}
''',
      resolver: QuickjsUiResourceResolver.memory(const <String, String>{
        'pages/counter.mjs': 'export default {};',
        'components/label.mjs': 'export function label() {}',
      }),
    );

    expect(bundle.id, 'quickjs_ui_bundle_counter');
    expect(bundle.version, '0.2.0');
    expect(bundle.entry, 'pages/counter.mjs');
    expect(bundle.permissions, <String>['toast', 'app.customEcho']);
    expect(bundle.toPlugin().manifest.permissions, <String>[
      'toast',
      'app.customEcho',
    ]);
    expect(bundle.modules.keys, <String>[
      'pages/counter.mjs',
      'components/label.mjs',
    ]);
    expect(
      QuickjsUiResourceResolver.normalizePath(
        '../components/label.mjs',
        from: 'pages/counter.mjs',
      ),
      'components/label.mjs',
    );
  });

  test('validates quickjs_ui permissions only when policy is restricted', () {
    final plugin = QuickjsUiPagePlugin.singleFile(
      id: 'quickjs_ui_permission_test',
      version: '0.3.0',
      permissions: const <String>['toast', 'app.customEcho'],
      source: '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  build() {
    return Text('permission test');
  }
});
''',
    );

    expect(
      () => const QuickjsUiPermissionPolicy.unrestricted().validate(
        plugin: plugin,
        grantedPermissions: const <String>[],
      ),
      returnsNormally,
    );
    expect(
      () =>
          QuickjsUiPermissionPolicy.restricted(
            allowed: const <String>['toast', 'app.customEcho'],
          ).validate(
            plugin: plugin,
            grantedPermissions: const <String>['toast', 'app.customEcho'],
          ),
      returnsNormally,
    );
    expect(
      () =>
          QuickjsUiPermissionPolicy.restricted(
            allowed: const <String>['toast'],
          ).validate(
            plugin: plugin,
            grantedPermissions: const <String>['toast', 'app.customEcho'],
          ),
      throwsA(
        isA<QuickjsUiPermissionException>().having(
          (error) => error.deniedByPolicy,
          'deniedByPolicy',
          contains('app.customEcho'),
        ),
      ),
    );
    expect(
      () => QuickjsUiPermissionPolicy.restricted(
        allowed: const <String>['toast', 'app.customEcho'],
      ).validate(plugin: plugin, grantedPermissions: const <String>['toast']),
      throwsA(
        isA<QuickjsUiPermissionException>().having(
          (error) => error.missingGrants,
          'missingGrants',
          contains('app.customEcho'),
        ),
      ),
    );
  });

  test('ships JSON Schema for supported UI nodes', () {
    final file = File('js/quickjs_ui.schema.json');
    final schema = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final defs = schema[r'$defs']! as Map<String, Object?>;
    final node = defs['node']! as Map<String, Object?>;
    final variants = node['oneOf']! as List<Object?>;

    expect(schema[r'$schema'], 'https://json-schema.org/draft/2020-12/schema');
    expect(schema['title'], 'quickjs_ui UI schema');
    expect(
      variants.map((variant) => (variant! as Map<String, Object?>)[r'$ref']),
      containsAll(<String>[
        '#/\$defs/text',
        '#/\$defs/elevatedButton',
        '#/\$defs/row',
        '#/\$defs/column',
        '#/\$defs/container',
        '#/\$defs/image',
        '#/\$defs/listView',
        '#/\$defs/textField',
        '#/\$defs/stack',
        '#/\$defs/padding',
        '#/\$defs/center',
        '#/\$defs/sizedBox',
      ]),
    );

    final textField = defs['textField']! as Map<String, Object?>;
    final allOf = textField['allOf']! as List<Object?>;
    final props =
        (allOf.last! as Map<String, Object?>)['properties']!
            as Map<String, Object?>;
    expect(props.keys, containsAll(<String>['onChanged', 'onSubmitted']));
    expect(props.keys, containsAll(<String>['onFocus', 'onBlur']));

    final color = defs['color']! as Map<String, Object?>;
    final colorVariants = color['oneOf']! as List<Object?>;
    expect(
      colorVariants.any(
        (variant) =>
            variant is Map<String, Object?> &&
            '${variant['pattern']}'.contains(r'^\$'),
      ),
      isTrue,
    );
    final textStyle = defs['textStyle']! as Map<String, Object?>;
    expect(textStyle['oneOf'], isA<List<Object?>>());
  });

  test('runtime helper is generated from JS helper source', () {
    final source = File('js/quickjs_ui.js').readAsStringSync();

    expect(quickjsUiHelperModuleSource, source);
  });

  test('dispatches page lifecycle hooks', () async {
    final disposed = Completer<void>();
    final engine = await Quickjs.create(
      options: QuickjsRuntimeOptions(
        mounts: <QuickjsHostMount>[
          QuickjsHostMount(
            name: 'lifecycle-test',
            providers: <QuickjsHostProvider>[
              QuickjsHostProvider.dart(
                name: 'test.disposed',
                callback: (_, _) {
                  if (!disposed.isCompleted) {
                    disposed.complete();
                  }
                  return true;
                },
              ),
            ],
            environmentPatches: const <QuickjsHostScript>[
              QuickjsHostScript.js(
                name: 'lifecycle-test:globals.js',
                globals: <String>['quickjsUiTest'],
                source: '''
globalThis.quickjsUiTest = {
  disposed() {
    return globalThis.__quickjsHostProviders['test.disposed']();
  },
};
''',
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(engine.dispose);
    final controller = QuickjsUiController(engine: engine);
    addTearDown(controller.dispose);
    final plugin = QuickjsUiPagePlugin.singleFile(
      id: 'quickjs_ui_lifecycle_test',
      version: '0.3.0',
      source: '''
import { Page, Text } from 'quickjs_ui';

function append(state, value) {
  return { events: [...state.events, value] };
}

export default Page({
  createState() {
    return { events: [] };
  },
  build(state) {
    return Text(state.events.join('|'));
  },
  onMount(state) {
    return append(state, 'mount');
  },
  onShow(state) {
    return append(state, 'show');
  },
  onHide(state) {
    return append(state, 'hide');
  },
  onPause(state) {
    return append(state, 'pause');
  },
  onResume(state) {
    return append(state, 'resume');
  },
  onRouteEnter(state, payload) {
    return append(state, `enter:\${payload.route}`);
  },
  onRouteLeave(state, payload) {
    return append(state, `leave:\${payload.to}`);
  },
  onRouteResult(state, payload) {
    return append(state, `result:\${payload.from}:\${payload.result.value}`);
  },
  async onDispose(state) {
    await quickjsUiTest.disposed();
    return null;
  }
});
''',
    );

    await controller.loadPlugin(plugin);
    await controller.lifecycle('mount');
    await controller.routeLifecycle('show');
    await controller.routeLifecycle('hide');
    await controller.lifecycle('pause');
    await controller.lifecycle('resume');
    await controller.lifecycle(
      'routeEnter',
      payload: const <String, Object?>{'route': 'detail'},
    );
    await controller.lifecycle(
      'routeLeave',
      payload: const <String, Object?>{'to': 'child'},
    );
    await controller.lifecycle(
      'routeResult',
      payload: const <String, Object?>{
        'from': 'child',
        'result': <String, Object?>{'value': 'ok'},
      },
    );

    expect((controller.state! as Map)['events'], <Object?>[
      'mount',
      'show',
      'hide',
      'pause',
      'resume',
      'enter:detail',
      'leave:child',
      'result:child:ok',
    ]);
    expect(
      controller.node?.props['data'],
      'mount|show|hide|pause|resume|enter:detail|leave:child|result:child:ok',
    );

    controller.dispose();
    await disposed.future.timeout(const Duration(seconds: 2));
  });

  test('forwards JS console events from owned runtime', () async {
    final events = <QuickjsConsoleEvent>[];
    final controller = QuickjsUiController(onConsole: events.add);
    addTearDown(controller.dispose);
    final plugin = QuickjsUiPagePlugin.singleFile(
      id: 'quickjs_ui_console_test',
      version: '0.3.0',
      source: '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  createState() {
    return {};
  },
  build() {
    return Text('console');
  },
  onMount(state) {
    console.log('lifecycle state', JSON.stringify(state));
    return null;
  }
});
''',
    );

    await controller.loadPlugin(plugin);
    await controller.lifecycle('mount');

    expect(events, hasLength(1));
    expect(events.single.level, QuickjsConsoleLevel.log);
    expect(events.single.text, contains('lifecycle state'));
  });

  test('does not notify for no-op lifecycle hooks', () async {
    final controller = QuickjsUiController();
    addTearDown(controller.dispose);
    final plugin = QuickjsUiPagePlugin.singleFile(
      id: 'quickjs_ui_noop_lifecycle_notify_test',
      version: '0.4.0',
      source: '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  createState() {
    return { label: 'idle' };
  },
  build(state) {
    return Text(state.label);
  }
});
''',
    );

    await controller.loadPlugin(plugin);
    var notifications = 0;
    controller.addListener(() {
      notifications += 1;
    });

    await controller.lifecycle('pause');

    expect(notifications, 0);
  });

  test(
    'skips JS lifecycle calls when page declares no lifecycle hooks',
    () async {
      final session = QuickjsUiSession();
      addTearDown(session.dispose);

      await session.loadPlugin(
        QuickjsUiPagePlugin.singleFile(
          id: 'quickjs_ui_no_lifecycle_hooks',
          version: '0.4.0',
          source: '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  createState() {
    return { lifecycleCalls: 0 };
  },
  build(state) {
    return Text('calls: ' + state.lifecycleCalls);
  },
  lifecycle(state) {
    return { lifecycleCalls: state.lifecycleCalls + 1 };
  }
});
''',
        ),
      );

      expect(session.state, <String, Object?>{'lifecycleCalls': 0});
      expect(await session.lifecycle('mount'), isFalse);
      expect(await session.routeLifecycle('show'), isFalse);
      expect(session.state, <String, Object?>{'lifecycleCalls': 0});
    },
  );

  test('runs dispose lifecycle before closing owned runtime', () async {
    final disposed = Completer<QuickjsConsoleEvent>();
    final controller = QuickjsUiController(
      onConsole: (event) {
        if (event.text.contains('dispose state') && !disposed.isCompleted) {
          disposed.complete(event);
        }
      },
    );
    final plugin = QuickjsUiPagePlugin.singleFile(
      id: 'quickjs_ui_dispose_console_test',
      version: '0.3.0',
      source: '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  createState() {
    return { value: 1 };
  },
  build() {
    return Text('dispose');
  },
  onDispose(state) {
    console.log('dispose state', JSON.stringify(state));
    return null;
  }
});
''',
    );

    await controller.loadPlugin(plugin);
    controller.dispose();
    final event = await disposed.future.timeout(const Duration(seconds: 2));

    expect(event.level, QuickjsConsoleLevel.log);
    expect(event.text, contains('"value":1'));
  });

  test('builds configurable host capabilities as mounts', () async {
    final calls = <String>[];
    final capabilities = QuickjsUiHostCapabilities.system(
      options: const QuickjsUiHostCapabilityOptions(
        enabled: <QuickjsUiHostCapability>{
          QuickjsUiHostCapability.toast,
          QuickjsUiHostCapability.confirm,
          QuickjsUiHostCapability.storage,
        },
      ),
      handlers: QuickjsUiHostApiHandlers(
        onToast: (message, options) {
          calls.add('toast:$message:${options['source']}');
          return <String, Object?>{'shown': true, 'message': message};
        },
        onConfirm: (message, _) {
          calls.add('confirm:$message');
          return true;
        },
      ),
      storage: const <String, Object?>{'boot': 'ready'},
    );
    final engine = await Quickjs.create(
      options: QuickjsRuntimeOptions(mounts: capabilities.mounts),
    );
    addTearDown(engine.dispose);

    expect(capabilities.permissions, contains('toast'));
    expect(
      await engine.evalAsync(
        "return JSON.stringify(await quickjsUiHost.toast('Saved', { source: 'test' }));",
      ),
      '{"shown":true,"message":"Saved"}',
    );
    expect(
      await engine.evalAsync(
        "return await quickjsUiHost.confirm('Continue?');",
      ),
      'true',
    );
    expect(
      await engine.evalAsync(
        "await quickjsUiHost.storage.setItem('name', 'Ada'); return await quickjsUiHost.storage.getItem('name');",
      ),
      'Ada',
    );
    expect(await engine.eval('typeof quickjsUiHost.network'), 'undefined');
    expect(calls, <String>['toast:Saved:test', 'confirm:Continue?']);
  });

  test('cancels pending host capability provider on stop', () async {
    final invoked = Completer<QuickjsHostProviderContext>();
    var invocationCount = 0;
    final capabilities = QuickjsUiHostCapabilities(
      groups: <QuickjsUiCapabilityGroup>[
        QuickjsUiCapabilityGroup.methods(
          name: 'app-wait',
          namespace: 'app',
          globalName: 'quickjsUiApp',
          methods: <QuickjsUiHostMethod>[
            QuickjsUiHostMethod(
              name: 'wait',
              callback: (_, context) async {
                invocationCount += 1;
                if (invocationCount == 1) {
                  invoked.complete(context);
                  await context.cancelled;
                  context.throwIfCancelled();
                }
                return 42;
              },
            ),
          ],
        ),
      ],
    );
    final engine = await Quickjs.create(
      options: QuickjsRuntimeOptions(mounts: capabilities.mounts),
    );
    addTearDown(engine.dispose);

    final running = engine.evalAsync('return await quickjsUiApp.wait();');
    final context = await invoked.future.timeout(const Duration(seconds: 2));
    final runningFailure = expectLater(
      running,
      throwsA(
        anyOf(isA<JsCancelledException>(), isA<JsRuntimeClosedException>()),
      ),
    );

    await engine.stop().timeout(const Duration(seconds: 2));
    await runningFailure;
    expect(context.isCancelled, isTrue);
    expect(context.cancellationReason, isA<JsCancelledException>());
    expect(await engine.evalAsync('return await quickjsUiApp.wait();'), '42');
  });

  test('describes host capability methods for policy and tooling', () {
    final capabilities = QuickjsUiHostCapabilities(
      groups: <QuickjsUiCapabilityGroup>[
        QuickjsUiCapabilityGroup.system(
          options: const QuickjsUiHostCapabilityOptions(
            enabled: <QuickjsUiHostCapability>{
              QuickjsUiHostCapability.toast,
              QuickjsUiHostCapability.storage,
            },
          ),
        ),
        const QuickjsUiCapabilityGroup(
          name: 'app-custom',
          mounts: <QuickjsHostMount>[QuickjsHostMount(name: 'app-custom')],
          permissions: <String>{'app.customEcho'},
          methods: <QuickjsUiHostMethodDeclaration>[
            QuickjsUiHostMethodDeclaration(
              name: 'quickjsUiApp.customEcho',
              providerName: 'app.customEcho',
              inputSchema: <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'value': <String, Object?>{'type': 'string'},
                },
                'required': <String>['value'],
              },
              outputSchema: <String, Object?>{'type': 'string'},
            ),
          ],
        ),
      ],
    );

    expect(
      capabilities.methods.map((method) => method.name),
      containsAll(<String>[
        'quickjsUiHost.toast',
        'quickjsUiHost.storage.getItem',
        'quickjsUiHost.storage.setItem',
        'quickjsUiHost.storage.removeItem',
        'quickjsUiApp.customEcho',
      ]),
    );
    expect(
      capabilities.methodMaps.last,
      containsPair('providerName', 'app.customEcho'),
    );
    expect(
      capabilities.methodMaps.last['inputSchema'],
      containsPair('required', <String>['value']),
    );
  });

  test('builds custom method capability groups with minimal injection API', () {
    final group = QuickjsUiCapabilityGroup.methods(
      name: 'app-math',
      namespace: 'app',
      globalName: 'quickjsUiApp',
      methods: <QuickjsUiHostMethod>[
        QuickjsUiHostMethod(
          name: 'add',
          inputSchema: const <String, Object?>{'type': 'object'},
          outputSchema: const <String, Object?>{'type': 'number'},
          callback: (args, _) => (args[0] as num) + (args[1] as num),
        ),
      ],
    );
    final capabilities = QuickjsUiHostCapabilities(
      groups: <QuickjsUiCapabilityGroup>[group],
    );

    expect(capabilities.permissions, contains('app.add'));
    expect(capabilities.methods.single.name, 'quickjsUiApp.add');
    expect(capabilities.methods.single.providerName, 'app.add');
    expect(capabilities.mounts.single.providers.single.name, 'app.add');
    expect(
      capabilities.mounts.single.environmentPatches.single.source,
      contains('quickjsUiApp'),
    );
    expect(
      capabilities.mounts.single.environmentPatches.single.source,
      contains('"add"'),
    );
  });

  test('builds custom function capability groups from names and bodies', () {
    final group = QuickjsUiCapabilityGroup.functions(
      name: 'app-functions',
      namespace: 'app',
      globalName: 'quickjsUiApp',
      functions: <String, Function>{
        'add': (num a, num b) => a + b,
        'echo': (Object? value) => 'echo:$value',
      },
    );
    final capabilities = QuickjsUiHostCapabilities(
      groups: <QuickjsUiCapabilityGroup>[group],
    );

    expect(
      capabilities.permissions,
      containsAll(<String>['app.add', 'app.echo']),
    );
    expect(
      capabilities.methods.map((method) => method.name),
      containsAll(<String>['quickjsUiApp.add', 'quickjsUiApp.echo']),
    );
    expect(
      capabilities.mounts.single.providers.map((provider) => provider.name),
      containsAll(<String>['app.add', 'app.echo']),
    );
    expect(
      capabilities.mounts.single.environmentPatches.single.source,
      contains('"add"'),
    );
  });

  test('requires method declarations for exposed host providers', () {
    QuickjsHostMount mountWithProvider(String providerName) {
      return QuickjsHostMount(
        name: providerName,
        providers: <QuickjsHostProvider>[
          QuickjsHostProvider.dart(
            name: providerName,
            callback: (_, _) => null,
          ),
        ],
      );
    }

    expect(
      () => QuickjsUiHostCapabilities(
        groups: <QuickjsUiCapabilityGroup>[
          QuickjsUiCapabilityGroup(
            name: 'missing-method',
            mounts: <QuickjsHostMount>[mountWithProvider('app.missing')],
          ),
        ],
      ).mounts,
      throwsStateError,
    );
    expect(
      () => QuickjsUiHostCapabilities(
        groups: <QuickjsUiCapabilityGroup>[
          QuickjsUiCapabilityGroup(
            name: 'unknown-provider',
            mounts: <QuickjsHostMount>[mountWithProvider('app.actual')],
            methods: const <QuickjsUiHostMethodDeclaration>[
              QuickjsUiHostMethodDeclaration(
                name: 'quickjsUiApp.actual',
                providerName: 'app.other',
              ),
            ],
          ),
        ],
      ).mounts,
      throwsStateError,
    );
    expect(
      QuickjsUiHostCapabilities(
        groups: <QuickjsUiCapabilityGroup>[
          QuickjsUiCapabilityGroup(
            name: 'declared-provider',
            mounts: <QuickjsHostMount>[mountWithProvider('app.declared')],
            methods: const <QuickjsUiHostMethodDeclaration>[
              QuickjsUiHostMethodDeclaration(
                name: 'quickjsUiApp.declared',
                providerName: 'app.declared',
                inputSchema: <String, Object?>{'type': 'object'},
                outputSchema: <String, Object?>{'type': 'null'},
              ),
            ],
          ),
        ],
      ).mounts,
      hasLength(1),
    );
  });

  test('merges host capability groups with explicit conflict policy', () {
    QuickjsUiCapabilityGroup group(String name) {
      return QuickjsUiCapabilityGroup(
        name: name,
        namespace: name,
        mounts: const <QuickjsHostMount>[QuickjsHostMount(name: 'same')],
      );
    }

    expect(
      () => QuickjsUiHostCapabilities(
        groups: <QuickjsUiCapabilityGroup>[group('first'), group('second')],
      ).mounts,
      throwsStateError,
    );
    expect(
      QuickjsUiHostCapabilities(
        groups: <QuickjsUiCapabilityGroup>[group('first'), group('second')],
        conflictPolicy: QuickjsUiCapabilityConflictPolicy.replace,
      ).mounts,
      hasLength(1),
    );
    expect(
      QuickjsUiHostCapabilities(
        groups: <QuickjsUiCapabilityGroup>[group('first'), group('second')],
        conflictPolicy: QuickjsUiCapabilityConflictPolicy.namespace,
      ).mounts.map((mount) => mount.name),
      <String>['same', 'second:same:1'],
    );
  });

  testWidgets('renders basic Flutter widgets and dispatches button event', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Column',
      'mainAxisAlignment': 'center',
      'children': <Object?>[
        <String, Object?>{'type': 'Text', 'data': 'Count: 0'},
        <String, Object?>{
          'type': 'ElevatedButton',
          'child': <String, Object?>{'type': 'Text', 'data': 'Add'},
          'onPressed': <String, Object?>{'action': 'increment'},
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiRenderer(onEvent: events.add).build(node)),
    );

    expect(find.text('Count: 0'), findsOneWidget);
    await tester.tap(find.text('Add'));
    expect(events.single, <String, Object?>{'action': 'increment'});
  });

  testWidgets('renders gap between flex children', (tester) async {
    final columnNode = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Column',
      'gap': 8,
      'children': <Object?>[
        <String, Object?>{'type': 'Text', 'data': 'A'},
        <String, Object?>{'type': 'Text', 'data': 'B'},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiRenderer(onEvent: (_) {}).build(columnNode)),
    );

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(tester.widget<Column>(find.byType(Column)).spacing, 8);

    final rowNode = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Row',
      'gap': 6,
      'children': <Object?>[
        <String, Object?>{'type': 'Text', 'data': 'C'},
        <String, Object?>{'type': 'Text', 'data': 'D'},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiRenderer(onEvent: (_) {}).build(rowNode)),
    );

    expect(tester.widget<Row>(find.byType(Row)).spacing, 6);
  });

  testWidgets('renders Container decoration props', (tester) async {
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Container',
      'width': 80,
      'height': 40,
      'padding': <String, Object?>{'horizontal': 8},
      'opacity': 0.5,
      'decoration': <String, Object?>{
        'color': '#112233',
        'borderRadius': 6,
        'border': <String, Object?>{'color': '#445566', 'width': 2},
      },
      'child': <String, Object?>{'type': 'Text', 'data': 'Box'},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: QuickjsUiRenderer(onEvent: (_) {}).build(node)),
      ),
    );

    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 0.5);
    final containerFinder = find.descendant(
      of: find.byType(Opacity),
      matching: find.byType(Container),
    );
    final container = tester.widget<Container>(containerFinder);
    expect(tester.getSize(containerFinder), const Size(80, 40));
    expect(container.padding, const EdgeInsets.symmetric(horizontal: 8));
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xff112233));
    expect(decoration.borderRadius, BorderRadius.circular(6));
    expect(
      decoration.border,
      Border.all(color: const Color(0xff445566), width: 2),
    );
    expect(find.text('Box'), findsOneWidget);
  });

  testWidgets('resolves ThemeData color and text style tokens', (tester) async {
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Container',
      'color': r'$primary',
      'child': <String, Object?>{
        'type': 'Column',
        'children': <Object?>[
          <String, Object?>{
            'type': 'Text',
            'data': 'Theme title',
            'style': r'$text.titleMedium',
          },
          <String, Object?>{
            'type': 'Text',
            'data': 'Theme color',
            'style': <String, Object?>{'color': r'$onPrimary'},
          },
        ],
      },
    });
    const primary = Color(0xff0057b8);
    const onPrimary = Color(0xffffffff);
    const titleStyle = TextStyle(fontSize: 19, fontWeight: FontWeight.w600);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: primary,
          ).copyWith(primary: primary, onPrimary: onPrimary),
          textTheme: const TextTheme(titleMedium: titleStyle),
        ),
        home: Builder(
          builder: (context) {
            return QuickjsUiRenderer(
              onEvent: (_) {},
            ).build(node, buildContext: context);
          },
        ),
      ),
    );

    final container = tester.widget<Container>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color == primary,
      ),
    );
    expect((container.decoration! as BoxDecoration).color, primary);
    final resolvedTitleStyle = tester
        .widget<Text>(find.text('Theme title'))
        .style;
    expect(resolvedTitleStyle?.fontSize, titleStyle.fontSize);
    expect(resolvedTitleStyle?.fontWeight, titleStyle.fontWeight);
    expect(
      tester.widget<Text>(find.text('Theme color')).style?.color,
      onPrimary,
    );
  });

  testWidgets('renders 0.2 layout and media widgets', (tester) async {
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'ListView',
      'padding': 8,
      'children': <Object?>[
        <String, Object?>{
          'type': 'Padding',
          'padding': <String, Object?>{'horizontal': 4},
          'child': <String, Object?>{
            'type': 'Center',
            'child': <String, Object?>{
              'type': 'SizedBox',
              'width': 100,
              'height': 40,
              'child': <String, Object?>{'type': 'Text', 'data': 'Sized'},
            },
          },
        },
        <String, Object?>{
          'type': 'Stack',
          'alignment': 'center',
          'children': <Object?>[
            <String, Object?>{
              'type': 'Container',
              'width': 32,
              'height': 24,
              'color': '#000000',
            },
            <String, Object?>{'type': 'Text', 'data': 'Overlay'},
          ],
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiRenderer(onEvent: (_) {}).build(node)),
    );

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.shrinkWrap, isTrue);
    expect(listView.padding, const EdgeInsets.all(8));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Padding &&
            widget.padding == const EdgeInsets.symmetric(horizontal: 4),
      ),
      findsOneWidget,
    );
    expect(find.byType(Center), findsOneWidget);
    expect(tester.getSize(find.byType(SizedBox).first), const Size(100, 40));
    final stack = tester.widget<Stack>(find.byType(Stack));
    expect(stack.alignment, Alignment.center);
    expect(find.text('Overlay'), findsOneWidget);
  });

  testWidgets('renders basic implicit animation widgets', (tester) async {
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Column',
      'children': <Object?>[
        <String, Object?>{
          'type': 'Container',
          'width': 80,
          'height': 40,
          'color': '#336699',
          'opacity': 0.5,
          'animationDurationMs': 180,
          'animationCurve': 'easeOut',
          'child': <String, Object?>{'type': 'Text', 'data': 'Animated box'},
        },
        <String, Object?>{
          'type': 'Padding',
          'padding': 12,
          'animationDurationMs': 120,
          'child': <String, Object?>{'type': 'Text', 'data': 'Animated pad'},
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiRenderer(onEvent: (_) {}).build(node)),
    );

    final animatedContainer = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(animatedContainer.duration, const Duration(milliseconds: 180));
    expect(animatedContainer.curve, Curves.easeOut);
    expect(find.byType(AnimatedOpacity), findsOneWidget);

    final animatedPadding = tester.widget<AnimatedPadding>(
      find.byType(AnimatedPadding),
    );
    expect(animatedPadding.duration, const Duration(milliseconds: 120));
  });

  test('builds Image widget props without loading image bytes', () {
    final registry = QuickjsUiComponentRegistry.defaults();
    final context = QuickjsUiRenderContext(
      buildNode: (_) => const SizedBox.shrink(),
      onUiEvent: (_) {},
      onEvent: (_) {},
    );
    final image =
        registry.build(
              context,
              QuickjsUiNode.fromMap(<String, Object?>{
                'type': 'Image',
                'src': 'assets/avatar.png',
                'width': 32,
                'height': 24,
                'fit': 'cover',
              }),
            )
            as Image;

    expect(image.image, isA<AssetImage>());
    expect(image.width, 32);
    expect(image.height, 24);
    expect(image.fit, BoxFit.cover);
  });

  testWidgets('renders TextField events and controlled value', (tester) async {
    final events = <Map<String, Object?>>[];
    QuickjsUiNode node(String value) {
      return QuickjsUiNode.fromMap(<String, Object?>{
        'type': 'TextField',
        'value': value,
        'labelText': 'Name',
        'hintText': 'Enter name',
        'textInputAction': 'done',
        'onChanged': <String, Object?>{'method': 'setName'},
        'onSubmitted': <String, Object?>{'method': 'submitName'},
      });
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickjsUiRenderer(onEvent: events.add).build(node('A')),
        ),
      ),
    );

    expect(find.text('A'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Ada');
    expect(events.single, <String, Object?>{
      'method': 'setName',
      'value': 'Ada',
    });

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(events.last, <String, Object?>{
      'method': 'submitName',
      'value': 'Ada',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickjsUiRenderer(onEvent: events.add).build(node('Grace')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Grace'), findsOneWidget);
  });

  testWidgets('renders TextField focus and blur events', (tester) async {
    final events = <Map<String, Object?>>[];
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'TextField',
      'value': 'Ada',
      'onFocus': <String, Object?>{'method': 'focusName'},
      'onBlur': <String, Object?>{'method': 'blurName'},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickjsUiRenderer(onEvent: events.add).build(node),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(events.single, <String, Object?>{
      'method': 'focusName',
      'value': 'Ada',
    });

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(events.last, <String, Object?>{
      'method': 'blurName',
      'value': 'Ada',
    });
  });

  testWidgets('renders controlled checkbox and switch events', (tester) async {
    final events = <Map<String, Object?>>[];
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Column',
      'children': <Object?>[
        <String, Object?>{
          'type': 'Checkbox',
          'value': false,
          'onChanged': <String, Object?>{'method': 'setChecked'},
        },
        <String, Object?>{
          'type': 'Switch',
          'value': true,
          'onChanged': <String, Object?>{'method': 'setEnabled'},
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickjsUiRenderer(onEvent: events.add).build(node),
        ),
      ),
    );

    await tester.tap(find.byType(Checkbox));
    expect(events.single, <String, Object?>{
      'method': 'setChecked',
      'value': true,
    });

    await tester.tap(find.byType(Switch));
    expect(events.last, <String, Object?>{
      'method': 'setEnabled',
      'value': false,
    });
  });

  testWidgets('renders controlled radio and dropdown events', (tester) async {
    final events = <Map<String, Object?>>[];
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Column',
      'children': <Object?>[
        <String, Object?>{
          'type': 'Radio',
          'value': 'email',
          'groupValue': 'phone',
          'onChanged': <String, Object?>{'method': 'setContact'},
        },
        <String, Object?>{
          'type': 'DropdownButton',
          'value': 'small',
          'onChanged': <String, Object?>{'method': 'setSize'},
          'items': <Object?>[
            <String, Object?>{'value': 'small', 'label': 'Small'},
            <String, Object?>{'value': 'large', 'label': 'Large'},
          ],
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickjsUiRenderer(onEvent: events.add).build(node),
        ),
      ),
    );

    await tester.tap(find.byType(Radio<Object?>));
    expect(events.single, <String, Object?>{
      'method': 'setContact',
      'value': 'email',
    });

    await tester.tap(find.byType(DropdownButton<Object?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large').last);
    await tester.pumpAndSettle();

    expect(events.last, <String, Object?>{
      'method': 'setSize',
      'value': 'large',
    });
  });

  testWidgets('renders tap and long press gesture events', (tester) async {
    final events = <Map<String, Object?>>[];
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Container',
      'width': 120,
      'height': 80,
      'onTap': <String, Object?>{'method': 'tapCard'},
      'onLongPress': <String, Object?>{'method': 'holdCard'},
      'child': <String, Object?>{'type': 'Text', 'data': 'Gesture card'},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickjsUiRenderer(onEvent: events.add).build(node),
        ),
      ),
    );

    await tester.tap(find.text('Gesture card'));
    expect(events.single, <String, Object?>{'method': 'tapCard'});

    await tester.longPress(find.text('Gesture card'));
    expect(events.last, <String, Object?>{'method': 'holdCard'});
  });

  testWidgets('renders ListView scroll events', (tester) async {
    final events = <Map<String, Object?>>[];
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'ListView',
      'onScroll': <String, Object?>{'method': 'scrollList'},
      'children': <Object?>[
        for (var index = 0; index < 20; index++)
          <String, Object?>{
            'type': 'SizedBox',
            'height': 40,
            'child': <String, Object?>{'type': 'Text', 'data': 'Row $index'},
          },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 160,
            child: QuickjsUiRenderer(onEvent: events.add).build(node),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pump();

    expect(events, isNotEmpty);
    expect(events.last['method'], 'scrollList');
    expect(events.last['pixels'], isA<double>());
    expect(events.last['maxScrollExtent'], greaterThan(0));
    expect(events.last['axis'], 'vertical');
  });

  test('coalesces throttled renderer events by key', () async {
    final events = <Map<String, Object?>>[];
    final dispatcher = QuickjsUiEventDispatcher((event) {
      events.add(event.event);
    });
    addTearDown(dispatcher.dispose);
    final event = <String, Object?>{
      'method': 'scrollList',
      'throttleMs': 40,
      'coalesceKey': 'list:main:onScroll',
    };

    dispatcher.dispatch(event, payload: const <String, Object?>{'pixels': 1});
    dispatcher.dispatch(event, payload: const <String, Object?>{'pixels': 2});
    dispatcher.dispatch(event, payload: const <String, Object?>{'pixels': 3});

    expect(events, hasLength(1));
    expect(events.single['pixels'], 1);

    await Future<void>.delayed(const Duration(milliseconds: 70));

    expect(events, hasLength(2));
    expect(events.last['pixels'], 3);
  });

  test('debounces renderer events by key', () async {
    final events = <Map<String, Object?>>[];
    final dispatcher = QuickjsUiEventDispatcher((event) {
      events.add(event.event);
    });
    addTearDown(dispatcher.dispose);
    final event = <String, Object?>{
      'method': 'videoProgress',
      'debounceMs': 30,
      'coalesceKey': 'video:hero:progress',
    };

    dispatcher.dispatch(
      event,
      payload: const <String, Object?>{'positionMs': 1},
    );
    dispatcher.dispatch(
      event,
      payload: const <String, Object?>{'positionMs': 2},
    );
    dispatcher.dispatch(
      event,
      payload: const <String, Object?>{'positionMs': 3},
    );

    expect(events, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(events, hasLength(1));
    expect(events.single['positionMs'], 3);
  });

  test('drops renderer events inside drop window', () async {
    final events = <Map<String, Object?>>[];
    final dispatcher = QuickjsUiEventDispatcher((event) {
      events.add(event.event);
    });
    addTearDown(dispatcher.dispose);
    final event = <String, Object?>{
      'method': 'videoProgress',
      'dropMs': 40,
      'coalesceKey': 'video:hero:progress',
    };

    dispatcher.dispatch(
      event,
      payload: const <String, Object?>{'positionMs': 1},
    );
    dispatcher.dispatch(
      event,
      payload: const <String, Object?>{'positionMs': 2},
    );
    dispatcher.dispatch(
      event,
      payload: const <String, Object?>{'positionMs': 3},
    );

    expect(events, hasLength(1));
    expect(events.single['positionMs'], 1);

    await Future<void>.delayed(const Duration(milliseconds: 70));
    dispatcher.dispatch(
      event,
      payload: const <String, Object?>{'positionMs': 4},
    );

    expect(events, hasLength(2));
    expect(events.last['positionMs'], 4);
  });

  test('does not queue timing events without coalesce key', () async {
    final events = <Map<String, Object?>>[];
    final dispatcher = QuickjsUiEventDispatcher((event) {
      events.add(event.event);
    });
    addTearDown(dispatcher.dispose);
    final event = <String, Object?>{
      'method': 'anonymousProgress',
      'throttleMs': 40,
    };

    dispatcher.dispatch(event, payload: const <String, Object?>{'value': 1});
    dispatcher.dispatch(event, payload: const <String, Object?>{'value': 2});

    expect(events, hasLength(2));
    expect(events.last['value'], 2);
  });

  test('attaches default coalesce key to payload events', () {
    final events = <QuickjsUiEventEnvelope>[];
    final dispatcher = QuickjsUiEventDispatcher((event) {
      events.add(event);
    });
    addTearDown(dispatcher.dispose);

    dispatcher.dispatch(
      const <String, Object?>{'method': 'scrub'},
      payload: const <String, Object?>{'value': 12},
      defaultCoalesceKey: 'Slider:progress:onChanged',
      kind: QuickjsUiEventKind.sample,
    );

    expect(events, hasLength(1));
    expect(events.single.coalesceKey, 'Slider:progress:onChanged');
    expect(events.single.event['coalesceKey'], isNull);
    expect(events.single.event['value'], 12);
  });

  test('drops oldest pending renderer event above queue limit', () async {
    final events = <Map<String, Object?>>[];
    final dispatcher = QuickjsUiEventDispatcher((event) {
      events.add(event.event);
    }, maxPendingEvents: 2);
    addTearDown(dispatcher.dispose);

    dispatcher.dispatch(
      const <String, Object?>{
        'method': 'one',
        'debounceMs': 40,
        'coalesceKey': 'one',
      },
      payload: const <String, Object?>{'value': 1},
    );
    dispatcher.dispatch(
      const <String, Object?>{
        'method': 'two',
        'debounceMs': 40,
        'coalesceKey': 'two',
      },
      payload: const <String, Object?>{'value': 2},
    );
    dispatcher.dispatch(
      const <String, Object?>{
        'method': 'three',
        'debounceMs': 40,
        'coalesceKey': 'three',
      },
      payload: const <String, Object?>{'value': 3},
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(events.map((event) => event['method']), <Object?>['two', 'three']);
  });

  testWidgets('event ingress defers events submitted during build', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final ingress = QuickjsUiEventIngress((event) async {
      events.add(event);
    });
    addTearDown(ingress.dispose);
    var deferredDuringBuild = false;

    await tester.pumpWidget(
      _QuickjsUiIngressProbe(
        ingress: ingress,
        action: 'during-build',
        onSubmitted: () {
          deferredDuringBuild = events.isEmpty;
        },
      ),
    );

    expect(deferredDuringBuild, isTrue);
    expect(events, hasLength(1));
    expect(events.single['action'], 'during-build');
  });

  testWidgets('event ingress preserves event order across frames', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final ingress = QuickjsUiEventIngress((event) async {
      events.add(event);
    });
    addTearDown(ingress.dispose);

    await tester.pumpWidget(const SizedBox.shrink());
    ingress.submit(<String, Object?>{'action': 'first'});
    ingress.submit(<String, Object?>{'action': 'second'});
    await tester.pump();
    await tester.pump();

    expect(events.map((event) => event['action']), <Object?>[
      'first',
      'second',
    ]);
  });

  testWidgets('event ingress coalesces pending events by key', (tester) async {
    final events = <Map<String, Object?>>[];
    final ingress = QuickjsUiEventIngress((event) async {
      events.add(event);
    });
    addTearDown(ingress.dispose);

    await tester.pumpWidget(const SizedBox.shrink());
    ingress.submitEnvelope(
      QuickjsUiEventEnvelope.sample(<String, Object?>{
        'method': 'scrub',
        'value': 1,
      }, coalesceKey: 'Slider:main:onChanged'),
    );
    ingress.submitEnvelope(
      QuickjsUiEventEnvelope.sample(<String, Object?>{
        'method': 'scrub',
        'value': 2,
      }, coalesceKey: 'Slider:main:onChanged'),
    );
    ingress.submitEnvelope(
      QuickjsUiEventEnvelope.sample(<String, Object?>{
        'method': 'scrub',
        'value': 3,
      }, coalesceKey: 'Slider:main:onChanged'),
    );
    await tester.pump();

    expect(events, hasLength(1));
    expect(events.single['value'], 3);
  });

  testWidgets('event ingress preserves sample and command order', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final ingress = QuickjsUiEventIngress((event) async {
      events.add(event);
    });
    addTearDown(ingress.dispose);

    await tester.pumpWidget(const SizedBox.shrink());
    ingress.submitEnvelope(
      QuickjsUiEventEnvelope.sample(<String, Object?>{
        'method': 'scrub',
        'value': 10,
      }, coalesceKey: 'Slider:main:onChanged'),
    );
    ingress.submitEnvelope(
      QuickjsUiEventEnvelope.sample(<String, Object?>{
        'method': 'onProgress',
        'positionMs': 11,
      }, coalesceKey: 'video:progress'),
    );
    ingress.submit(<String, Object?>{'method': 'togglePlay'});
    await tester.pump();

    expect(events.map((event) => event['method']), <Object?>[
      'scrub',
      'onProgress',
      'togglePlay',
    ]);
  });

  testWidgets('event ingress does not coalesce samples across commands', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final ingress = QuickjsUiEventIngress((event) async {
      events.add(event);
    });
    addTearDown(ingress.dispose);

    await tester.pumpWidget(const SizedBox.shrink());
    ingress.submitEnvelope(
      QuickjsUiEventEnvelope.sample(<String, Object?>{
        'method': 'scrub',
        'value': 10,
      }, coalesceKey: 'Slider:main:onChanged'),
    );
    ingress.submit(<String, Object?>{'method': 'seek'});
    ingress.submitEnvelope(
      QuickjsUiEventEnvelope.sample(<String, Object?>{
        'method': 'scrub',
        'value': 20,
      }, coalesceKey: 'Slider:main:onChanged'),
    );
    await tester.pump();

    expect(events.map((event) => event['method']), <Object?>[
      'scrub',
      'seek',
      'scrub',
    ]);
    expect(events.map((event) => event['value']), <Object?>[10, null, 20]);
  });

  testWidgets('event ingress leaves reentrant submissions for next frame', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    late final QuickjsUiEventIngress ingress;
    ingress = QuickjsUiEventIngress((event) async {
      events.add(event);
      if (event['action'] == 'first') {
        ingress.submit(<String, Object?>{'action': 'second'});
      }
    });
    addTearDown(ingress.dispose);

    await tester.pumpWidget(const SizedBox.shrink());
    ingress.submit(<String, Object?>{'action': 'first'});
    await tester.pump();

    expect(events.map((event) => event['action']), <Object?>['first']);

    await tester.pump();

    expect(events.map((event) => event['action']), <Object?>[
      'first',
      'second',
    ]);
  });

  testWidgets('renders custom registry component', (tester) async {
    final registry = QuickjsUiComponentRegistry.defaults()
      ..register('Badge', (context, node) {
        return DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xffeeeeee)),
          child: context.child(node) ?? const SizedBox.shrink(),
        );
      });
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Badge',
      'child': <String, Object?>{'type': 'Text', 'data': 'Custom'},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: QuickjsUiRenderer(
          registry: registry,
          onEvent: (_) {},
        ).build(node),
      ),
    );

    expect(find.byType(DecoratedBox), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
  });

  test('QuickjsUiView accepts custom registry', () {
    final registry = QuickjsUiComponentRegistry.defaults()
      ..register('Badge', (context, node) {
        return DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xffeeeeee)),
          child: context.child(node) ?? const SizedBox.shrink(),
        );
      });
    final plugin = QuickjsUiPagePlugin.singleFile(
      id: 'quickjs_ui_custom_registry_view',
      version: '0.4.0',
      source: '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  build() {
    return {
      type: 'Badge',
      child: Text('Custom from view')
    };
  }
});
''',
    );
    final view = QuickjsUiView.plugin(plugin, registry: registry);

    expect(view.registry, same(registry));
  });

  test('renderer skips unchanged keyed nodes', () {
    final builds = <String, int>{};
    final registry = QuickjsUiComponentRegistry.defaults()
      ..register('Probe', (context, node) {
        final id = '${node.props['id']}';
        builds[id] = (builds[id] ?? 0) + 1;
        return Text('$id:${node.props['label']}');
      });
    final renderer = QuickjsUiRenderer(registry: registry, onEvent: (_) {});

    QuickjsUiNode tree(String changedLabel) {
      return QuickjsUiNode.fromMap(<String, Object?>{
        'type': 'Column',
        'children': <Object?>[
          <String, Object?>{
            'type': 'Probe',
            'key': 'stable-probe',
            'id': 'stable',
            'label': 'same',
          },
          <String, Object?>{
            'type': 'Probe',
            'key': 'changed-probe',
            'id': 'changed',
            'label': changedLabel,
          },
        ],
      });
    }

    renderer.build(tree('first'));
    renderer.build(tree('second'));

    expect(builds, <String, int>{'stable': 1, 'changed': 2});
  });

  test('renderer guards recursive custom registry components', () {
    final registry = QuickjsUiComponentRegistry.defaults()
      ..register('Loop', (context, node) => context.build(node));
    final renderer = QuickjsUiRenderer(registry: registry, onEvent: (_) {});
    final node = QuickjsUiNode.fromMap(<String, Object?>{'type': 'Loop'});

    expect(
      () => renderer.build(node),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'quickjs_ui render tree is too deep',
        ),
      ),
    );
  });

  test('throws for unknown registry component', () {
    final node = QuickjsUiNode.fromMap(<String, Object?>{'type': 'Missing'});
    final renderer = QuickjsUiRenderer(onEvent: (_) {});

    expect(
      () => renderer.build(node),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Unknown quickjs_ui node type: Missing',
        ),
      ),
    );
  });

  testWidgets('QuickjsUiView catches renderer errors with errorBuilder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuickjsUiView.plugin(
          _unknownComponentPlugin(),
          errorBuilder: (context, error) {
            return Text('Render error: $error');
          },
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.textContaining('Unknown quickjs_ui node type'),
    );

    expect(find.textContaining('Unknown quickjs_ui node type'), findsOneWidget);
  });

  testWidgets('QuickjsUiView shows default error overlay with resource', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuickjsUiView.asset(path: 'assets/quickjs_ui/missing_page.mjs'),
      ),
    );
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('quickjs_ui error').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('quickjs_ui error'), findsOneWidget);
    expect(find.textContaining('schema path: root'), findsOneWidget);
    expect(find.text('source: asset'), findsOneWidget);
    expect(
      find.textContaining('resource: assets/quickjs_ui/missing_page.mjs'),
      findsOneWidget,
    );
  });

  testWidgets('QuickjsUiErrorOverlay renders schema and resource details', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: QuickjsUiErrorOverlay(
          error: FormatException('bad node', 'preview.json', 7),
          details: QuickjsUiErrorDetails(
            source: 'asset',
            resourceKey: 'assets/quickjs_ui/schema_preview.json',
            schemaPath: 'root.children[0]',
            routeName: 'schema_preview',
            action: 'render',
          ),
        ),
      ),
    );

    expect(find.text('quickjs_ui error'), findsOneWidget);
    expect(find.textContaining('message: bad node'), findsOneWidget);
    expect(
      find.textContaining('resource: assets/quickjs_ui/schema_preview.json'),
      findsOneWidget,
    );
    expect(
      find.textContaining('schema path: root.children[0]'),
      findsOneWidget,
    );
    expect(find.textContaining('route: schema_preview'), findsOneWidget);
    expect(find.textContaining('schema offset: 7'), findsOneWidget);
  });

  testWidgets('QuickjsUiView uses emptyBuilder before first node', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuickjsUiView.plugin(
          _counterPlugin(),
          placeholder: const Text('Placeholder state'),
          emptyBuilder: (_) => const Text('Empty state'),
        ),
      ),
    );

    expect(find.text('Empty state'), findsOneWidget);
    expect(find.text('Placeholder state'), findsNothing);
  });

  testWidgets('QuickjsUiView dispatches mount lifecycle after first render', (
    tester,
  ) async {
    final plugin = QuickjsUiPagePlugin.singleFile(
      id: 'quickjs_ui_view_lifecycle_test',
      version: '0.3.0',
      source: '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  createState() {
    return { event: 'waiting' };
  },
  build(state) {
    return Text(state.event);
  },
  onMount(state) {
    return { event: 'mount' };
  }
});
''',
    );

    await tester.pumpWidget(MaterialApp(home: QuickjsUiView.plugin(plugin)));
    await _pumpUntilFound(tester, find.text('mount'));

    expect(find.text('mount'), findsOneWidget);
  });

  test('bundle plugins expose lifecycle export', () async {
    final bundle = QuickjsUiBundle(
      id: 'quickjs_ui_bundle_lifecycle_test',
      version: '0.3.0',
      entry: 'main.mjs',
      modules: const <String, String>{
        'main.mjs': '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  createState() {
    return { event: 'waiting' };
  },
  build(state) {
    return Text(state.event);
  },
  onMount(state) {
    return { event: 'mount' };
  }
});
''',
      },
    );
    final controller = QuickjsUiController();
    addTearDown(controller.dispose);

    await controller.loadPlugin(bundle.toPlugin());
    await controller.lifecycle('mount');

    expect(controller.node?.props['data'], 'mount');
  });

  test('bundle plugins skip undeclared lifecycle hooks', () async {
    final bundle = QuickjsUiBundle(
      id: 'quickjs_ui_bundle_no_lifecycle_hooks_test',
      version: '0.3.0',
      entry: 'main.mjs',
      modules: const <String, String>{
        'main.mjs': '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  createState() {
    return { event: 'waiting' };
  },
  build(state) {
    return Text(state.event);
  }
});
''',
      },
    );
    final session = QuickjsUiSession();
    addTearDown(session.dispose);

    await session.loadPlugin(bundle.toPlugin());

    expect(await session.lifecycle('mount'), isFalse);
    expect(await session.routeLifecycle('show'), isFalse);
    expect(session.state, <String, Object?>{'event': 'waiting'});
  });

  test('custom components setExpanded dispatch stays shallow', () async {
    final bundle = await QuickjsUiBundle.fromEntry(
      id: 'quickjs_ui_custom_components_repro',
      version: '0.4.0',
      entry: 'custom_components_page.mjs',
      resolver: QuickjsUiResourceResolver.file(
        basePath: '../../example/assets/quickjs_ui',
      ),
    );
    final session = QuickjsUiSession();
    addTearDown(session.dispose);

    await session.loadPlugin(
      bundle.toPlugin(),
      initialProps: const <String, Object?>{'title': 'Custom components'},
    );

    for (var index = 0; index < 5000; index += 1) {
      await session.dispatch(<String, Object?>{
        'method': 'setExpanded',
        'value': index.isEven,
      });
      if (index % 5 == 0) {
        await session.dispatch(<String, Object?>{
          'method': 'setEnabled',
          'value': index.isOdd,
        });
      }
      if (index % 7 == 0) {
        await session.dispatch(<String, Object?>{
          'method': 'setSize',
          'value': index.isEven ? 'large' : 'small',
        });
      }
      if (index % 97 == 0) {
        await session.dispatch(<String, Object?>{'method': 'reset'});
      }
    }

    expect((session.state! as Map)['expanded'], isFalse);
  });

  testWidgets('QuickjsUiView.asset creates a multi-file asset view', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuickjsUiView.asset(
          path: 'assets/quickjs_ui/bundle_counter/pages/main.mjs',
          loadingBuilder: (_) => const Text('Loading bundle'),
        ),
      ),
    );

    expect(find.text('Loading bundle'), findsOneWidget);
  });

  test('runs init/render/dispatch page protocol', () async {
    final engine = await Quickjs.create();
    final controller = QuickjsUiController(engine: engine);
    addTearDown(controller.dispose);

    await controller.loadPlugin(_counterPlugin());

    expect(controller.state, <String, Object?>{'count': 0});
    expect(controller.node?.type, 'Column');
    expect(controller.node?.children.first.props['data'], 'Count: 0');

    await controller.dispatch(<String, Object?>{'action': 'increment'});

    expect(controller.state, <String, Object?>{'count': 1});
    expect(controller.node?.children.first.props['data'], 'Count: 1');
  });

  test('runs page protocol through QuickjsUiSession', () async {
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);

    await session.loadPlugin(
      _counterPlugin(),
      initialProps: const <String, Object?>{'initialCount': 2},
    );

    expect(session.state, <String, Object?>{'count': 2});
    expect(session.node?.children.first.props['data'], 'Count: 2');

    await session.dispatch(<String, Object?>{'action': 'increment'});

    expect(session.state, <String, Object?>{'count': 3});
    expect(session.node?.children.first.props['data'], 'Count: 3');

    await session.setState(<String, Object?>{'count': 9});

    expect(session.state, <String, Object?>{'count': 9});
    expect(session.node?.children.first.props['data'], 'Count: 9');
  });

  test('supports async init and dispatch state updates', () async {
    final engine = await Quickjs.create();
    final controller = QuickjsUiController(engine: engine);
    addTearDown(controller.dispose);

    await controller.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'quickjs_ui_async_state',
        version: '0.3.0',
        source: '''
import { Column, Page, Text } from 'quickjs_ui';

export default Page({
  async createState() {
    await Promise.resolve();
    return { count: 1 };
  },
  build(state) {
    return Column({
      children: [
        Text(`Count: \${state.count}`)
      ]
    });
  },
  async increment(state) {
    await Promise.resolve();
    return { count: state.count + 1 };
  }
});
''',
      ),
    );

    expect(controller.state, <String, Object?>{'count': 1});
    expect(controller.node?.children.first.props['data'], 'Count: 1');

    await controller.dispatch(<String, Object?>{'action': 'increment'});

    expect(controller.state, <String, Object?>{'count': 2});
    expect(controller.node?.children.first.props['data'], 'Count: 2');
  });

  test('ignores pending async dispatch result after dispose', () async {
    final pending = Completer<Object?>();
    final engine = await Quickjs.create(
      options: QuickjsRuntimeOptions(
        mounts: <QuickjsHostMount>[
          QuickjsHostMount(
            name: 'quickjs_ui:test:wait',
            providers: <QuickjsHostProvider>[
              QuickjsHostProvider.dart(
                name: 'quickjs_ui.test.wait',
                callback: (_, _) => pending.future,
              ),
            ],
            environmentPatches: const <QuickjsHostScript>[
              QuickjsHostScript.js(
                name: 'quickjs_ui:test:wait.js',
                globals: <String>['quickjsUiTestWait'],
                source: '''
globalThis.quickjsUiTestWait = function quickjsUiTestWait() {
  return globalThis.__quickjsHostProviders['quickjs_ui.test.wait']();
};
''',
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(engine.dispose);
    final controller = QuickjsUiController(engine: engine);

    await controller.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'quickjs_ui_pending_dispatch',
        version: '0.3.0',
        source: '''
import { Column, Page, Text } from 'quickjs_ui';

export default Page({
  createState() {
    return { count: 0 };
  },
  build(state) {
    return Column({
      children: [
        Text(`Count: \${state.count}`)
      ]
    });
  },
  async increment(state) {
    await quickjsUiTestWait();
    return { count: state.count + 1 };
  }
});
''',
      ),
    );
    final dispatch = controller.dispatch(<String, Object?>{
      'action': 'increment',
    });
    controller.dispose();
    pending.complete(null);

    await dispatch;

    expect(controller.state, <String, Object?>{'count': 0});
  });

  test('cancels pending navigation provider after dispose', () async {
    final invoked = Completer<QuickjsHostProviderContext>();
    final capabilities = QuickjsUiHostCapabilities(
      groups: <QuickjsUiCapabilityGroup>[
        QuickjsUiCapabilityGroup.methods(
          name: 'quickjs_ui:test:navigation',
          namespace: 'quickjs_ui.host',
          globalName: 'quickjsUiHost',
          methods: <QuickjsUiHostMethod>[
            QuickjsUiHostMethod(
              name: 'navigationIntent',
              permission: 'navigation',
              callback: (_, context) async {
                invoked.complete(context);
                await context.cancelled;
                context.throwIfCancelled();
                return <String, Object?>{'unexpected': true};
              },
            ),
          ],
        ),
      ],
    );
    final controller = QuickjsUiController();

    await controller.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'quickjs_ui_pending_navigation',
        version: '0.3.1',
        source: '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  createState() {
    return { status: 'idle' };
  },
  build(state) {
    return Text(state.status);
  },
  async openRoute(state) {
    await quickjsUiHost.navigationIntent({
      route: 'quickjs-ui.pending',
      params: { source: 'test' }
    });
    return { status: 'returned' };
  }
});
''',
      ),
      mounts: capabilities.mounts,
    );

    final dispatch = controller.dispatch(<String, Object?>{
      'action': 'openRoute',
    });
    final context = await invoked.future.timeout(const Duration(seconds: 2));

    controller.dispose();
    await context.cancelled.timeout(const Duration(seconds: 2));
    await dispatch;

    expect(context.isCancelled, isTrue);
    expect(context.cancellationReason, isA<JsRuntimeClosedException>());
  });

  testWidgets('maps navigation transition intent to Flutter route', (
    WidgetTester tester,
  ) async {
    final observer = _RouteCaptureObserver();
    final registry = QuickjsUiRouteRegistry(
      nativeRoutes: <String, QuickjsUiNativeRouteBuilder>{
        'native.detail': (context, params) =>
            const Scaffold(body: Text('native detail')),
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                unawaited(
                  QuickjsUiNavigator.pushIntent(
                    context,
                    registry: registry,
                    intent: const <String, Object?>{
                      'route': 'native.detail',
                      'transition': <String, Object?>{
                        'type': 'fade',
                        'durationMs': 120,
                        'curve': 'easeOut',
                      },
                    },
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    observer.pushed.clear();

    await tester.tap(find.text('open'));
    await tester.pump();

    expect(observer.pushed, hasLength(1));
    expect(observer.pushed.single, isA<PageRouteBuilder<Object?>>());
    expect(observer.pushed.single.settings.name, 'native.detail');
  });

  test('applies JSUI route policy allowlist and guard', () async {
    final requests = <QuickjsUiJsRouteRequest>[];
    var allowFromGuard = true;
    final policy = QuickjsUiJsRoutePolicy(
      allowedPaths: const <String>{'assets/quickjs_ui/allowed_page.mjs'},
      onRequest: (request) {
        requests.add(request);
        return allowFromGuard;
      },
    );
    const allowedRequest = QuickjsUiJsRouteRequest(
      route: 'quickjs-ui.allowed',
      path: './allowed_page.mjs',
      resolvedPath: 'assets/quickjs_ui/allowed_page.mjs',
      from: 'assets/quickjs_ui/main.mjs',
      action: 'push',
      params: <String, Object?>{'id': 1},
      isRegistered: false,
    );
    const deniedByAllowlist = QuickjsUiJsRouteRequest(
      route: 'quickjs-ui.denied',
      path: './denied_page.mjs',
      resolvedPath: 'assets/quickjs_ui/denied_page.mjs',
      from: 'assets/quickjs_ui/main.mjs',
      action: 'push',
      params: <String, Object?>{},
      isRegistered: false,
    );

    expect(await policy.allows(allowedRequest), isTrue);
    expect(requests, <QuickjsUiJsRouteRequest>[allowedRequest]);

    expect(await policy.allows(deniedByAllowlist), isFalse);
    expect(requests, <QuickjsUiJsRouteRequest>[allowedRequest]);

    allowFromGuard = false;
    expect(await policy.allows(allowedRequest), isFalse);
    expect(requests, <QuickjsUiJsRouteRequest>[allowedRequest, allowedRequest]);
  });

  test('controller refresh, restart and reload use distinct paths', () async {
    final engine = await Quickjs.create();
    final controller = QuickjsUiController(engine: engine);
    addTearDown(controller.dispose);
    var version = 0;

    Future<QuickjsPlugin> loadVersionedPlugin() async {
      version += 1;
      return QuickjsUiPagePlugin.singleFile(
        id: 'quickjs_ui_reload_source',
        version: '0.2.0',
        source:
            '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  build() {
    return Text('Version $version');
  }
});
''',
      );
    }

    await controller.load(loadVersionedPlugin);

    expect(controller.node?.props['data'], 'Version 1');

    await controller.refresh();

    expect(controller.node?.props['data'], 'Version 1');

    await controller.restart();

    expect(controller.node?.props['data'], 'Version 1');

    await controller.reload();

    expect(controller.node?.props['data'], 'Version 2');
  });

  test('runs multi-file entry bundle page protocol', () async {
    final bundle = await QuickjsUiBundle.fromEntry(
      id: 'quickjs_ui_bundle_page',
      version: '0.2.0',
      entry: 'pages/counter.mjs',
      resolver: QuickjsUiResourceResolver.memory(const <String, String>{
        'pages/counter.mjs': '''
import { Column, Page } from 'quickjs_ui';
import { countLabel } from '../components/label.mjs';

export default Page({
  createState(props) {
    return { count: props.initialCount ?? 0 };
  },
  build(state) {
    return Column({
      children: [
        countLabel(state.count)
      ]
    });
  }
});
''',
        'components/label.mjs': '''
import { Text } from 'quickjs_ui';

export function countLabel(count) {
  return Text(`Bundle count: \${count}`);
}
''',
      }),
    );
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);

    await session.loadPlugin(
      bundle.toPlugin(),
      initialProps: const <String, Object?>{'initialCount': 5},
    );

    expect(session.state, <String, Object?>{'count': 5});
    expect(session.node?.children.first.props['data'], 'Bundle count: 5');
  });

  test('runs JS component props and event protocol', () async {
    final bundle = await QuickjsUiBundle.fromEntry(
      id: 'quickjs_ui_component_protocol',
      version: '0.4.0',
      entry: 'pages/main.mjs',
      resolver: QuickjsUiResourceResolver.memory(const <String, String>{
        'pages/main.mjs': '''
import { Page } from 'quickjs_ui';
import { CounterCard } from '../components/counter_card.mjs';

export default Page({
  createState() {
    return { count: 2 };
  },
  build(state, props, actions) {
    return CounterCard({
      title: props.title,
      count: state.count,
      onIncrement: actions.increment({ step: 3 })
    });
  },
  increment(state, payload) {
    return { count: state.count + payload.step };
  }
});
''',
        'components/counter_card.mjs': '''
import { Column, Component, ElevatedButton, Text } from 'quickjs_ui';

export const CounterCard = Component((props) => {
  return Column({
    children: [
      Text(props.title),
      ElevatedButton({
        onPressed: props.onIncrement,
        child: Text(`Count: \${props.count}`)
      })
    ]
  });
});
''',
      }),
    );
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);

    await session.loadPlugin(
      bundle.toPlugin(),
      initialProps: const <String, Object?>{'title': 'Counter'},
    );

    expect(session.node?.children.first.props['data'], 'Counter');
    expect(
      session.node?.children.last.children.single.props['data'],
      'Count: 2',
    );
    expect(session.node?.children.last.props['onPressed'], <String, Object?>{
      'method': 'increment',
      'payload': <String, Object?>{'step': 3},
    });

    await session.dispatch(
      session.node?.children.last.props['onPressed']! as Map<String, Object?>,
    );

    expect(session.state, <String, Object?>{'count': 5});
    expect(
      session.node?.children.last.children.single.props['data'],
      'Count: 5',
    );
  });

  test(
    'guards recursive JS components before QuickJS stack overflow',
    () async {
      final engine = await Quickjs.create();
      final session = QuickjsUiSession(engine: engine);
      addTearDown(session.dispose);

      await expectLater(
        session.loadPlugin(
          QuickjsUiPagePlugin.singleFile(
            id: 'quickjs_ui_recursive_component',
            version: '0.4.0',
            source: '''
import { Component, Page } from 'quickjs_ui';

const Loop = Component(() => Loop());

export default Page({
  build() {
    return Loop();
  }
});
''',
          ),
        ),
        throwsA(
          isA<QuickjsUiRuntimeException>().having(
            (error) => '$error',
            'error',
            contains('quickjs_ui component render recursion limit exceeded'),
          ),
        ),
      );
    },
  );

  test('runs multi-file file bundle page protocol', () async {
    final directory = await Directory.systemTemp.createTemp(
      'quickjs_ui_bundle_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final pages = Directory('${directory.path}/pages')..createSync();
    final components = Directory('${directory.path}/components')..createSync();
    File('${pages.path}/counter.mjs').writeAsStringSync('''
import { Column, Page } from 'quickjs_ui';
import { countLabel } from '../components/label.mjs';

export default Page({
  createState(props) {
    return { count: props.initialCount ?? 0 };
  },
  build(state) {
    return Column({ children: [countLabel(state.count)] });
  }
});
''');
    File('${components.path}/label.mjs').writeAsStringSync('''
import { Text } from 'quickjs_ui';

export function countLabel(count) {
  return Text(`File count: \${count}`);
}
''');
    final bundle = await QuickjsUiBundle.file(
      path: '${pages.path}/counter.mjs',
    );
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);

    await session.loadPlugin(
      bundle.toPlugin(),
      initialProps: const <String, Object?>{'initialCount': 6},
    );

    expect(session.state, <String, Object?>{'count': 6});
    expect(session.node?.children.first.props['data'], 'File count: 6');
  });

  test('runs multi-file network bundle page protocol', () async {
    final resources = <String, String>{
      'https://example.com/ui/pages/counter.mjs': '''
import { Column, Page } from 'quickjs_ui';
import { countLabel } from '../components/label.mjs';

export default Page({
  createState(props) {
    return { count: props.initialCount ?? 0 };
  },
  build(state) {
    return Column({ children: [countLabel(state.count)] });
  }
});
''',
      'https://example.com/ui/components/label.mjs': '''
import { Text } from 'quickjs_ui';

export function countLabel(count) {
  return Text(`Network count: \${count}`);
}
''',
    };
    final bundle = await QuickjsUiBundle.network(
      url: Uri.parse('https://example.com/ui/pages/counter.mjs'),
      fetch: (request) async {
        final body = resources[request.uri.toString()];
        if (body == null) {
          return const QuickjsUiNetworkResponse(body: '', statusCode: 404);
        }
        return QuickjsUiNetworkResponse(body: body);
      },
    );
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);

    await session.loadPlugin(
      bundle.toPlugin(),
      initialProps: const <String, Object?>{'initialCount': 8},
    );

    expect(session.state, <String, Object?>{'count': 8});
    expect(session.node?.children.first.props['data'], 'Network count: 8');
  });

  test('network loader reuses cached modules on 304', () async {
    final requests = <QuickjsUiNetworkRequest>[];
    final events = <QuickjsUiNetworkLogEvent>[];
    final loader = QuickjsUiNetworkLoader(
      onLog: events.add,
      fetch: (request) async {
        requests.add(request);
        if (request.headers['if-none-match'] == '"v1"') {
          return const QuickjsUiNetworkResponse(
            body: '',
            statusCode: HttpStatus.notModified,
          );
        }
        return const QuickjsUiNetworkResponse(
          body: '''
import { Text, Page } from 'quickjs_ui';

export default Page({
  build() {
    return Text('Cached network page');
  }
});
''',
          headers: <String, String>{'etag': '"v1"'},
        );
      },
    );

    final url = Uri.parse('https://example.com/ui/pages/cached.mjs');
    final first = await loader.load(url: url);
    final second = await loader.load(url: url);

    expect(first.modules, second.modules);
    expect(requests, hasLength(2));
    expect(requests.last.headers, <String, String>{'if-none-match': '"v1"'});
    expect(events.map((event) => event.type), <String>[
      'network.request',
      'network.response',
      'network.cacheStore',
      'network.request',
      'network.response',
      'network.cacheHit',
    ]);
    expect(events.last.fromCache, isTrue);
  });

  test('network loader revalidates changed bundle resources', () async {
    var version = 1;
    final requests = <QuickjsUiNetworkRequest>[];
    final loader = QuickjsUiNetworkLoader(
      fetch: (request) async {
        requests.add(request);
        final uri = request.uri.toString();
        if (uri == 'https://example.com/ui/pages/main.mjs') {
          return QuickjsUiNetworkResponse(
            body: '''
import { Page } from 'quickjs_ui';
import { title } from '../components/title.mjs';

export default Page({
  build() {
    return title();
  }
});
''',
            headers: <String, String>{'etag': '"entry-v$version"'},
          );
        }
        if (uri == 'https://example.com/ui/components/title.mjs') {
          return QuickjsUiNetworkResponse(
            body:
                '''
import { Text } from 'quickjs_ui';

export function title() {
  return Text('Remote version $version');
}
''',
            headers: <String, String>{'etag': '"title-v$version"'},
          );
        }
        return const QuickjsUiNetworkResponse(body: '', statusCode: 404);
      },
    );
    final url = Uri.parse('https://example.com/ui/pages/main.mjs');

    final first = await loader.load(url: url);

    expect(first.modules['components/title.mjs'], contains('Remote version 1'));
    expect(requests, hasLength(2));

    version = 2;
    final second = await loader.load(url: url);

    expect(
      second.modules['components/title.mjs'],
      contains('Remote version 2'),
    );
    expect(requests, hasLength(4));
    expect(requests[2].headers, <String, String>{
      'if-none-match': '"entry-v1"',
    });
    expect(requests[3].headers, <String, String>{
      'if-none-match': '"title-v1"',
    });
  });

  test('setState updates JS-owned state and refreshes rendered node', () async {
    final engine = await Quickjs.create();
    final controller = QuickjsUiController(engine: engine);
    addTearDown(controller.dispose);

    await controller.loadPlugin(_counterPlugin());
    await controller.setState(<String, Object?>{'count': 7});

    expect(controller.state, <String, Object?>{'count': 7});
    expect(controller.node?.children.first.props['data'], 'Count: 7');
  });

  test('setState patch merge survives progress storms', () async {
    final bundle = await QuickjsUiBundle.fromEntry(
      id: 'video_scrub_repro',
      version: '0.1.0',
      entry: 'pages/video.mjs',
      resolver: QuickjsUiResourceResolver.memory(const <String, String>{
        'pages/video.mjs': '''
import { Page, Slider, eventField } from 'quickjs_ui';

export default Page({
  createState() {
    return {
      ready: true,
      autoplay: true,
      loop: true,
      playing: false,
      scrubbing: false,
      wasPlayingBeforeScrub: false,
      scrubPlayIntentVersion: 0,
      playIntentVersion: 0,
      positionMs: 0,
      scrubPositionMs: 0,
      durationMs: 60000,
      seekToken: 0,
      seekPositionMs: 0,
      status: 'ready'
    };
  },
  build(state, _props, actions) {
    const sliderValue = state.scrubbing ? state.scrubPositionMs : state.positionMs;
    const sliderMax = Math.max(state.durationMs, 1);
    return Slider({
      min: 0,
      max: sliderMax,
      value: Math.min(sliderValue, sliderMax),
      onChanged: actions.scrub(),
      onChangeEnd: actions.seek()
    });
  },
  onProgress(state, _payload, _props, event) {
    if (state.scrubbing) {
      return {
        durationMs: eventField(event, 'durationMs', state.durationMs)
      };
    }
    return {
      positionMs: eventField(event, 'positionMs', state.positionMs),
      durationMs: eventField(event, 'durationMs', state.durationMs)
    };
  },
  onReady(state, _payload, _props, event) {
    const playing =
      state.playIntentVersion > 0 ? state.playing : state.autoplay ? true : state.playing;
    return {
      ready: true,
      playing,
      durationMs: eventField(event, 'durationMs', state.durationMs)
    };
  },
  onEnded(state) {
    if (state.loop && state.playing) {
      return {
        playing: true,
        positionMs: 0
      };
    }
    return {
      playing: false
    };
  },
  scrub(state, payload, _props, event) {
    const value = Math.max(
      0,
      eventField(event, 'value', payload?.value ?? state.positionMs)
    );
    if (!state.scrubbing) {
      return {
        scrubbing: true,
        wasPlayingBeforeScrub: state.playing,
        scrubPlayIntentVersion: state.playIntentVersion,
        playing: false,
        scrubPositionMs: value,
        status: 'scrubbing'
      };
    }
    return { scrubPositionMs: value };
  },
  seek(state, payload, _props, event) {
    const value = Math.max(
      0,
      eventField(event, 'value', payload?.value ?? state.scrubPositionMs)
    );
    const playing =
      state.scrubPlayIntentVersion === state.playIntentVersion
        ? state.wasPlayingBeforeScrub
        : state.playing;
    return {
      scrubbing: false,
      wasPlayingBeforeScrub: false,
      scrubPlayIntentVersion: state.playIntentVersion,
      seekToken: state.seekToken + 1,
      seekPositionMs: value,
      positionMs: value,
      scrubPositionMs: value,
      playing,
      status: playing ? 'playing' : 'seeked'
    };
  },
  setPlaying(state, payload, _props, event) {
    const playing = eventField(event, 'playing', payload?.playing ?? !state.playing) === true;
    return {
      playing,
      playIntentVersion: state.playIntentVersion + 1
    };
  },
  togglePlay(state) {
    return {
      playing: !state.playing,
      playIntentVersion: state.playIntentVersion + 1
    };
  }
});
''',
      }),
    );
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);

    await session.loadPlugin(bundle.toPlugin());

    for (var i = 0; i < 5000; i++) {
      await session.dispatch(<String, Object?>{
        'method': 'onProgress',
        'positionMs': i * 10,
        'durationMs': 60000,
        'isPlaying': false,
      });
    }

    await session.dispatch(<String, Object?>{
      'method': 'scrub',
      'value': 12000.0,
    });
    expect(session.state, isA<Map>());
    final state = session.state! as Map<String, Object?>;
    expect(state['scrubbing'], isTrue);
    expect(state['scrubPositionMs'], 12000.0);

    await session.dispatch(<String, Object?>{
      'method': 'seek',
      'value': 12000.0,
    });
    expect(session.state, isA<Map>());
    final seeked = session.state! as Map<String, Object?>;
    expect(seeked['scrubbing'], isFalse);
    expect(seeked['positionMs'], 12000.0);
    expect(seeked['seekToken'], 1);

    await session.dispatch(<String, Object?>{
      'method': 'setPlaying',
      'playing': true,
    });
    await session.dispatch(<String, Object?>{
      'method': 'scrub',
      'value': 20000.0,
    });
    await session.dispatch(<String, Object?>{
      'method': 'setPlaying',
      'playing': false,
    });
    await session.dispatch(<String, Object?>{
      'method': 'seek',
      'value': 20000.0,
    });
    final pausedAfterSeek = session.state! as Map<String, Object?>;
    expect(pausedAfterSeek['playing'], isFalse);
    expect(pausedAfterSeek['positionMs'], 20000.0);

    await session.dispatch(<String, Object?>{
      'method': 'onReady',
      'durationMs': 60000,
    });
    final pausedAfterReady = session.state! as Map<String, Object?>;
    expect(pausedAfterReady['playing'], isFalse);

    await session.dispatch(<String, Object?>{'method': 'onEnded'});
    final pausedAfterEnded = session.state! as Map<String, Object?>;
    expect(pausedAfterEnded['playing'], isFalse);

    await session.dispatch(<String, Object?>{'method': 'togglePlay'});
    await session.dispatch(<String, Object?>{'method': 'togglePlay'});
    final toggledTwice = session.state! as Map<String, Object?>;
    expect(toggledTwice['playing'], isFalse);
  });

  test('dispatch normalizes payload fields for handlers', () async {
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);

    await session.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'payload_normalization',
        version: '0.1.0',
        source: '''
import { Page } from 'quickjs_ui';

export default Page({
  createState() {
    return { value: 0 };
  },
  build(state, _props, actions) {
    return { type: 'Text', data: String(state.value) };
  },
  setValue(state, payload, _props, event) {
    return {
      value: payload?.value ?? event?.value ?? state.value
    };
  }
});
''',
      ),
    );

    await session.dispatch(<String, Object?>{
      'method': 'setValue',
      'payload': <String, Object?>{'value': 42},
    });
    expect(session.state, <String, Object?>{'value': 42});

    await session.dispatch(<String, Object?>{'method': 'setValue', 'value': 7});
    expect(session.state, <String, Object?>{'value': 7});
  });
}

QuickjsPlugin _unknownComponentPlugin() {
  return QuickjsUiPagePlugin.singleFile(
    id: 'quickjs_ui_unknown_component',
    version: '0.1.0',
    source: '''
import { Page } from 'quickjs_ui';

export default Page({
  build() {
    return { type: 'MissingComponent' };
  }
});
''',
  );
}

QuickjsPlugin _counterPlugin() {
  return QuickjsUiPagePlugin.singleFile(
    id: 'quickjs_ui_counter',
    version: '0.1.0',
    source: '''
import { Column, ElevatedButton, Page, Text } from 'quickjs_ui';

function build(state, props, page) {
  return Column({
    mainAxisAlignment: 'center',
    children: [
      Text(`Count: \${state.count}`),
      ElevatedButton({
        child: Text('Add'),
        onPressed: page.increment()
      })
    ]
  });
}

export default Page({
  createState(props) {
    return { count: props.initialCount ?? 0 };
  },
  build,
  increment(state) {
    return { count: state.count + 1 };
  }
});
''',
  );
}

class _QuickjsUiIngressProbe extends StatelessWidget {
  const _QuickjsUiIngressProbe({
    required this.ingress,
    required this.action,
    required this.onSubmitted,
  });

  final QuickjsUiEventIngress ingress;
  final String action;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    ingress.submit(<String, Object?>{'action': action});
    onSubmitted();
    return const SizedBox.shrink();
  }
}
