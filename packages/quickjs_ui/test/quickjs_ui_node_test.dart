import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

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
  return { ...state, events: [...state.events, value] };
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
    return state;
  }
});
''',
    );

    await controller.loadPlugin(plugin);
    await controller.lifecycle('mount');
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
      'pause',
      'resume',
      'enter:detail',
      'leave:child',
      'result:child:ok',
    ]);
    expect(
      controller.node?.props['data'],
      'mount|pause|resume|enter:detail|leave:child|result:child:ok',
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
    return state;
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
    return state;
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

  test('builds Image widget props without loading image bytes', () {
    final registry = QuickjsUiComponentRegistry.defaults();
    final context = QuickjsUiRenderContext(
      buildNode: (_) => const SizedBox.shrink(),
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

  testWidgets('QuickjsUiView renders custom registry component', (
    tester,
  ) async {
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

    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiView.plugin(plugin, registry: registry)),
    );
    await _pumpUntilFound(tester, find.text('Custom from view'));

    expect(find.byType(DecoratedBox), findsOneWidget);
    expect(find.text('Custom from view'), findsOneWidget);
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
    await tester.pump();
    await tester.pump();

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
    return { ...state, event: 'mount' };
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
    return { ...state, event: 'mount' };
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
    return { ...state, count: state.count + 1 };
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
    return { ...state, count: state.count + 1 };
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
    return { ...state, status: 'returned' };
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
    return { ...state, count: state.count + 1 };
  }
});
''',
  );
}
