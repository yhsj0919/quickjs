import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs_ui/quickjs_ui.dart';
import 'package:quickjs_ui/src/renderer/quickjs_ui_event_ingress.dart';

final class _ProbeComponentController extends QuickjsUiComponentController {
  _ProbeComponentController(this.events);

  final List<String> events;

  @override
  void mount(QuickjsUiNode node) {
    events.add('mount:${node.props['label']}');
  }

  @override
  void update(QuickjsUiNode previous, QuickjsUiNode next) {
    events.add('update:${previous.props['label']}->${next.props['label']}');
  }

  @override
  void show() {
    events.add('show');
  }

  @override
  void hide() {
    events.add('hide');
  }

  @override
  void pause() {
    events.add('pause');
  }

  @override
  void resume() {
    events.add('resume');
  }

  @override
  void dispose() {
    events.add('dispose');
  }
}

void main() {
  group('quickjs_ui 0.4.1 cross-cutting', () {
    group('schema versioning / compatibility', () {
      test('accepts current quickjs_ui compatibility metadata', () async {
        final engine = await Quickjs.create();
        final session = QuickjsUiSession(engine: engine);
        addTearDown(session.dispose);

        await session.loadPlugin(
          QuickjsUiPagePlugin.singleFile(
            id: 'quickjs_ui_compatibility_accept',
            version: '0.4.1',
            source: '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  schemaVersion: 1,
  minimumQuickjsUiVersion: 1,
  unknownProps: 'warn',
  deprecatedProps: {
    oldText: 'Use data instead.'
  },
  createState() {
    return { label: 'compatible' };
  },
  build(state) {
    return Text(state.label);
  }
});
''',
          ),
        );

        expect(session.node?.props['data'], 'compatible');
      });

      test('rejects unsupported quickjs_ui schema version', () async {
        final engine = await Quickjs.create();
        final session = QuickjsUiSession(engine: engine);
        addTearDown(session.dispose);

        await expectLater(
          session.loadPlugin(
            QuickjsUiPagePlugin.singleFile(
              id: 'quickjs_ui_compatibility_schema_reject',
              version: '0.4.1',
              source: '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  schemaVersion: 2,
  build() {
    return Text('future schema');
  }
});
''',
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => '$error',
              'message',
              contains('unsupported schema version'),
            ),
          ),
        );
      });

      test('rejects pages requiring newer quickjs_ui runtime', () async {
        final engine = await Quickjs.create();
        final session = QuickjsUiSession(engine: engine);
        addTearDown(session.dispose);

        await expectLater(
          session.loadPlugin(
            QuickjsUiPagePlugin.singleFile(
              id: 'quickjs_ui_compatibility_runtime_reject',
              version: '0.4.1',
              source: '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  minimumQuickjsUiVersion: 2,
  build() {
    return Text('future runtime');
  }
});
''',
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => '$error',
              'message',
              contains('requires runtime version'),
            ),
          ),
        );
      });
    });

    test('schema fixtures stay serializable and replayable', () {
      final fixture = <String, Object?>{
        'type': 'Column',
        'mainAxisAlignment': 'center',
        'children': <Object?>[
          <String, Object?>{'type': 'Text', 'data': 'Title'},
          <String, Object?>{
            'type': 'ElevatedButton',
            'onPressed': <String, Object?>{'method': 'increment'},
            'child': <String, Object?>{'type': 'Text', 'data': 'Add'},
          },
        ],
      };

      final node = QuickjsUiNode.fromMap(fixture);

      expect(node.toMap(), <String, Object?>{
        'type': 'Column',
        'mainAxisAlignment': 'center',
        'children': <Object?>[
          <String, Object?>{'type': 'Text', 'data': 'Title'},
          <String, Object?>{
            'type': 'ElevatedButton',
            'onPressed': <String, Object?>{'method': 'increment'},
            'children': <Object?>[
              <String, Object?>{'type': 'Text', 'data': 'Add'},
            ],
          },
        ],
      });
      expect(node.children.last.children.single.props['data'], 'Add');
    });

    testWidgets('renderer smoke maps schema to widgets and events', (
      tester,
    ) async {
      final events = <Map<String, Object?>>[];
      final node = QuickjsUiNode.fromMap(<String, Object?>{
        'type': 'Column',
        'children': <Object?>[
          <String, Object?>{'type': 'Text', 'data': 'Counter'},
          <String, Object?>{
            'type': 'ElevatedButton',
            'onPressed': <String, Object?>{'method': 'increment', 'step': 1},
            'child': <String, Object?>{'type': 'Text', 'data': 'Add'},
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
      await tester.tap(find.text('Add'));

      expect(find.text('Counter'), findsOneWidget);
      expect(events, hasLength(1));
      expect(events.single, <String, Object?>{
        'method': 'increment',
        'step': 1,
      });
    });

    testWidgets('accessibility props map to semantics and tooltip', (
      tester,
    ) async {
      final node = QuickjsUiNode.fromMap(<String, Object?>{
        'type': 'ElevatedButton',
        'semanticLabel': 'Save changes',
        'semanticHint': 'Stores the current form',
        'tooltip': 'Save',
        'role': 'button',
        'enabled': true,
        'focusOrder': 2,
        'child': <String, Object?>{'type': 'Text', 'data': 'Save'},
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: QuickjsUiRenderer(onEvent: (_) {}).build(node)),
        ),
      );

      expect(find.byType(Tooltip), findsOneWidget);
      expect(find.bySemanticsLabel('Save changes'), findsOneWidget);
    });

    testWidgets(
      'design tokens resolve theme colors, spacing, radius, elevation',
      (tester) async {
        const brand = Color(0xff123456);
        const titleStyle = TextStyle(fontSize: 21, fontWeight: FontWeight.w700);
        final node = QuickjsUiNode.fromMap(<String, Object?>{
          'type': 'Container',
          'color': r'$brand.primary',
          'padding': <String, Object?>{
            'horizontal': r'$space.lg',
            'vertical': r'$content.gap',
          },
          'borderRadius': r'$radius.card',
          'borderWidth': r'$space.xs',
          'borderColor': r'$brand.primary',
          'elevation': r'$elevation.overlay',
          'child': <String, Object?>{
            'type': 'Column',
            'gap': r'$space.sm',
            'children': <Object?>[
              <String, Object?>{
                'type': 'Text',
                'data': 'Token title',
                'style': r'$display.card',
              },
              <String, Object?>{'type': 'Text', 'data': 'Token body'},
            ],
          },
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              extensions: <ThemeExtension<dynamic>>[
                QuickjsUiDesignTokens(
                  colors: const <String, Color>{'brand.primary': brand},
                  textStyles: const <String, TextStyle>{
                    'display.card': titleStyle,
                  },
                  spacing: const <String, double>{'content.gap': 20},
                  radius: const <String, double>{'card': 14},
                  elevation: const <String, double>{'overlay': 6},
                ),
              ],
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

        expect(
          tester.widget<Material>(find.byType(Material).last).elevation,
          6,
        );
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(Material).last,
            matching: find.byType(Container),
          ),
        );
        expect(
          container.padding,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, brand);
        expect(decoration.borderRadius, BorderRadius.circular(14));
        expect(decoration.border, Border.all(color: brand, width: 4));
        expect(tester.widget<Column>(find.byType(Column)).spacing, 8);
        expect(tester.widget<Text>(find.text('Token title')).style, titleStyle);
      },
    );

    testWidgets('text fields emit focus snapshots and move to next field', (
      tester,
    ) async {
      final events = <Map<String, Object?>>[];
      final node = QuickjsUiNode.fromMap(<String, Object?>{
        'type': 'Column',
        'children': <Object?>[
          <String, Object?>{
            'type': 'TextField',
            'key': 'first',
            'focusId': 'first-name',
            'value': 'Ada',
            'textInputAction': 'next',
            'onFocus': <String, Object?>{'method': 'focusFirst'},
            'onBlur': <String, Object?>{'method': 'blurFirst'},
            'onEditingComplete': <String, Object?>{'method': 'completeFirst'},
            'onSelectionChanged': <String, Object?>{'method': 'selectFirst'},
          },
          <String, Object?>{
            'type': 'TextField',
            'key': 'second',
            'focusId': 'last-name',
            'value': 'Lovelace',
            'onFocus': <String, Object?>{'method': 'focusSecond'},
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

      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Ada',
          selection: TextSelection(baseOffset: 0, extentOffset: 3),
        ),
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      expect(
        events.map((event) => event['method']),
        containsAll(<Object?>[
          'focusFirst',
          'selectFirst',
          'completeFirst',
          'blurFirst',
          'focusSecond',
        ]),
      );
      final selectionEvent = events.lastWhere(
        (event) => event['method'] == 'selectFirst',
      );
      expect(selectionEvent, containsPair('focusId', 'first-name'));
      expect(selectionEvent, containsPair('selectionStart', 0));
      expect(selectionEvent, containsPair('selectionEnd', 3));
      final secondFocus = events.firstWhere(
        (event) => event['method'] == 'focusSecond',
      );
      expect(secondFocus, containsPair('focusId', 'last-name'));
    });

    testWidgets('text field focus can be driven by schema updates', (
      tester,
    ) async {
      final events = <Map<String, Object?>>[];
      final renderer = QuickjsUiRenderer(onEvent: events.add);

      QuickjsUiNode field({
        required bool requestFocus,
        required bool clearFocus,
      }) {
        return QuickjsUiNode.fromMap(<String, Object?>{
          'type': 'TextField',
          'key': 'controlled',
          'focusId': 'controlled',
          'value': 'Ada',
          'requestFocus': requestFocus,
          'clearFocus': clearFocus,
          'onFocus': <String, Object?>{'method': 'focused'},
          'onBlur': <String, Object?>{'method': 'blurred'},
        });
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: renderer.build(field(requestFocus: false, clearFocus: false)),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: renderer.build(field(requestFocus: true, clearFocus: false)),
          ),
        ),
      );
      await tester.pump();

      expect(events.last, containsPair('method', 'focused'));
      expect(events.last, containsPair('focusId', 'controlled'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: renderer.build(field(requestFocus: true, clearFocus: true)),
          ),
        ),
      );
      await tester.pump();

      expect(events.last, containsPair('method', 'blurred'));
      expect(events.last, containsPair('focusId', 'controlled'));
    });

    test('custom renderer lifecycle owns keyed component controllers', () {
      final events = <String>[];
      final registry = QuickjsUiComponentRegistry.defaults()
        ..registerLifecycle<_ProbeComponentController>(
          'Probe',
          createController: (node) => _ProbeComponentController(events),
          build: (context, node, controller) {
            events.add('build:${node.props['label']}');
            return Text('${node.props['label']}');
          },
        );
      final renderer = QuickjsUiRenderer(registry: registry, onEvent: (_) {});

      QuickjsUiNode probe(String label) {
        return QuickjsUiNode.fromMap(<String, Object?>{
          'type': 'Probe',
          'key': 'main',
          'label': label,
        });
      }

      renderer.build(probe('one'));
      renderer.show();
      renderer.pause();
      renderer.resume();
      renderer.build(probe('two'));
      renderer.hide();
      renderer.build(
        QuickjsUiNode.fromMap(<String, Object?>{
          'type': 'Column',
          'children': const <Object?>[],
        }),
      );

      expect(events, <String>[
        'mount:one',
        'build:one',
        'show',
        'pause',
        'resume',
        'update:one->two',
        'build:two',
        'hide',
        'dispose',
      ]);
    });

    test('custom renderer lifecycle components require stable keys', () {
      final registry = QuickjsUiComponentRegistry.defaults()
        ..registerLifecycle<_ProbeComponentController>(
          'Probe',
          createController: (node) => _ProbeComponentController(<String>[]),
          build: (context, node, controller) => const SizedBox.shrink(),
        );
      final renderer = QuickjsUiRenderer(registry: registry, onEvent: (_) {});
      final node = QuickjsUiNode.fromMap(<String, Object?>{'type': 'Probe'});

      expect(
        () => renderer.build(node),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('requires a stable string key'),
          ),
        ),
      );
    });

    test('lifecycle sequence is applied through the session queue', () async {
      final engine = await Quickjs.create();
      final session = QuickjsUiSession(engine: engine);
      addTearDown(session.dispose);

      await session.loadPlugin(
        QuickjsUiPagePlugin.singleFile(
          id: 'quickjs_ui_conformance_lifecycle',
          version: '0.4.1',
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
  }
});
''',
        ),
      );

      await session.lifecycle('mount');
      await session.lifecycle('show');
      await session.lifecycle('hide');
      await session.lifecycle('pause');
      await session.lifecycle('resume');
      await session.lifecycle(
        'routeEnter',
        payload: const <String, Object?>{'route': 'detail'},
      );
      await session.lifecycle(
        'routeLeave',
        payload: const <String, Object?>{'to': 'child'},
      );
      await session.lifecycle(
        'routeResult',
        payload: const <String, Object?>{
          'from': 'child',
          'result': <String, Object?>{'value': 'ok'},
        },
      );

      expect((session.state! as Map<Object?, Object?>)['events'], <Object?>[
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
        session.node?.props['data'],
        'mount|show|hide|pause|resume|enter:detail|leave:child|result:child:ok',
      );
    });

    testWidgets(
      'event backpressure coalesces samples and defers reentrant work',
      (tester) async {
        final events = <Map<String, Object?>>[];
        late final QuickjsUiEventIngress ingress;
        ingress = QuickjsUiEventIngress((event) async {
          events.add(event);
          if (event['method'] == 'toggle') {
            ingress.submit(<String, Object?>{'method': 'afterToggle'});
          }
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
        ingress.submit(<String, Object?>{'method': 'toggle'});

        await tester.pump();

        expect(events.map((event) => event['method']), <Object?>[
          'scrub',
          'toggle',
        ]);
        expect(events.first['value'], 2);

        await tester.pump();

        expect(events.map((event) => event['method']), <Object?>[
          'scrub',
          'toggle',
          'afterToggle',
        ]);
      },
    );

    test('navigation sequence returns host result to JS state', () async {
      final intents = <Map<String, Object?>>[];
      final capabilities = QuickjsUiCapabilityGroup.system(
        options: const QuickjsUiHostCapabilityOptions(
          enabled: <QuickjsUiHostCapability>{
            QuickjsUiHostCapability.navigation,
          },
        ),
        handlers: QuickjsUiHostApiHandlers(
          onNavigationIntent: (intent) {
            intents.add(intent);
            return <String, Object?>{'value': 'native-result'};
          },
        ),
      );
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(mounts: capabilities.mounts),
      );
      final session = QuickjsUiSession(engine: engine);
      addTearDown(session.dispose);

      await session.loadPlugin(
        QuickjsUiPagePlugin.singleFile(
          id: 'quickjs_ui_conformance_navigation',
          version: '0.4.1',
          source: '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  createState() {
    return { result: 'none' };
  },
  build(state) {
    return Text(state.result);
  },
  async openNative() {
    const result = await quickjsUiHost.navigationIntent({
      route: 'native.detail',
      params: { id: 7 }
    });
    return { result: result.value };
  }
});
''',
        ),
      );

      await session.dispatch(<String, Object?>{'method': 'openNative'});

      expect(intents, <Map<String, Object?>>[
        <String, Object?>{
          'route': 'native.detail',
          'params': <String, Object?>{'id': 7},
        },
      ]);
      expect(session.state, <String, Object?>{'result': 'native-result'});
      expect(session.node?.props['data'], 'native-result');
    });

    group('resource / media model', () {
      test('resource references classify schemes and validate metadata', () {
        final asset = QuickjsUiResourceReference.parse('assets/avatar.png');
        expect(asset.kind, QuickjsUiResourceKind.asset);
        expect(asset.location, 'assets/avatar.png');

        final network = QuickjsUiResourceReference.parse(<String, Object?>{
          'url': 'https://example.com/avatar.png',
          'mimeType': 'image/png',
          'sha256':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'headers': <String, Object?>{'Authorization': 'Bearer token'},
        });
        expect(network.kind, QuickjsUiResourceKind.network);
        expect(network.mimeType, 'image/png');
        expect(
          network.headers,
          <String, String>{'Authorization': 'Bearer token'},
        );
        expect(network.isCacheable, isTrue);

        expect(
          () => QuickjsUiResourceReference.parse('ftp://example.com/file.png'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => QuickjsUiResourceReference.parse(<String, Object?>{
            'uri': 'https://example.com/file.png',
            'sha256': 'not-a-checksum',
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('Image accepts resource objects and data resources', () {
        final registry = QuickjsUiComponentRegistry.defaults();
        final context = QuickjsUiRenderContext(
          buildNode: (_) => const SizedBox.shrink(),
          onUiEvent: (_) {},
          onEvent: (_) {},
        );
        final networkImage =
            registry.build(
                  context,
                  QuickjsUiNode.fromMap(<String, Object?>{
                    'type': 'Image',
                    'src': <String, Object?>{
                      'url': 'https://example.com/avatar.png',
                      'headers': <String, Object?>{'X-Test': 'yes'},
                    },
                    'width': 32,
                  }),
                )
                as Image;
        expect(networkImage.image, isA<NetworkImage>());
        expect((networkImage.image as NetworkImage).headers, <String, String>{
          'X-Test': 'yes',
        });

        final dataImage =
            registry.build(
                  context,
                  QuickjsUiNode.fromMap(<String, Object?>{
                    'type': 'Image',
                    'src': 'data:image/png;base64,AA==',
                  }),
                )
                as Image;
        expect(dataImage.image, isA<MemoryImage>());
      });

      test('bundle manifest resources stay metadata-only', () async {
        final bundle = await QuickjsUiBundle.fromManifestSource(
          '''
{
  "id": "quickjs_ui_conformance_resources",
  "version": "0.4.1",
  "entry": "pages/main.mjs",
  "resources": {
    "images/avatar.png": {
      "mimeType": "image/png",
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "cacheKey": "avatar-v1"
    }
  },
  "modules": [
    "pages/main.mjs"
  ]
}
''',
          resolver: QuickjsUiResourceResolver.memory(const <String, String>{
            'pages/main.mjs': '''
import { Page, Text } from 'quickjs_ui';

export default Page({
  build() {
    return Text('resource metadata ok');
  }
});
''',
          }),
        );

        expect(bundle.resources.keys, <String>['images/avatar.png']);
        expect(bundle.resources['images/avatar.png']?.mimeType, 'image/png');
        expect(bundle.resources['images/avatar.png']?.cacheKey, 'avatar-v1');
        expect(
          bundle.resources['images/avatar.png']?.sha256,
          '0000000000000000000000000000000000000000000000000000000000000000',
        );
      });
    });

    test('bundle compatibility loads a multi-module page', () async {
      final bundle = await QuickjsUiBundle.fromManifestSource(
        '''
{
  "id": "quickjs_ui_conformance_bundle",
  "version": "0.4.1",
  "entry": "pages/main.mjs",
  "resources": {
    "images/logo.png": {
      "mimeType": "image/png",
      "cacheKey": "logo-v1"
    }
  },
  "modules": [
    "pages/main.mjs",
    "components/title.mjs"
  ]
}
''',
        resolver: QuickjsUiResourceResolver.memory(const <String, String>{
          'pages/main.mjs': '''
import { Page } from 'quickjs_ui';
import { title } from '../components/title.mjs';

export default Page({
  build() {
    return title('bundle ok');
  }
});
''',
          'components/title.mjs': '''
import { Text } from 'quickjs_ui';

export function title(value) {
  return Text(value);
}
''',
        }),
      );
      final engine = await Quickjs.create();
      final session = QuickjsUiSession(engine: engine);
      addTearDown(session.dispose);

      await session.loadPlugin(bundle.toPlugin());

      expect(bundle.resources['images/logo.png']?.cacheKey, 'logo-v1');
      expect(session.node?.props['data'], 'bundle ok');
    });
  });
}
