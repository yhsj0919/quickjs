import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

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
  });

  test('runtime helper is generated from JS helper source', () {
    final source = File('js/quickjs_ui.js').readAsStringSync();

    expect(quickjsUiHelperModuleSource, source);
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
