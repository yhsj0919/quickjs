import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_ui/lemon_js_ui_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in const <String, String>{
    'assets/quickjs_ui/anchored_overlay_demo_page.mjs': 'Container',
    'assets/quickjs_ui/decoration_effects_page.mjs': 'Container',
    'assets/quickjs_ui/pointer_keyboard_events_page.mjs': 'Container',
    'assets/quickjs_ui/widgets_demo_page.mjs': 'Scaffold',
    'assets/quickjs_ui/form_controls_page.mjs': 'SingleChildScrollView',
    'assets/quickjs_ui/feedback_overlays_page.mjs': 'ListView',
    'assets/quickjs_ui/controls_page.mjs': 'ListView',
    'assets/quickjs_ui/implicit_animations_page.mjs': 'SingleChildScrollView',
    'assets/quickjs_ui/scroll_transition_page.mjs': 'ListView',
    'assets/quickjs_ui/keyed_list_transitions_page.mjs': 'Column',
  }.entries) {
    final path = entry.key;
    test('$path builds as an independent foundation demo', () async {
      final source = await rootBundle.loadString(path);
      final engine = await JsEngine.create();
      final session = JsUiSession(engine: engine);
      addTearDown(session.dispose);

      await session.loadPlugin(
        JsUiPagePlugin.source(
          id: path.split('/').last.replaceAll('.mjs', ''),
          version: '1.0.0',
          source: source,
        ),
      );

      expect(session.node, isNotNull);
      expect(session.node!.type, entry.value);
      if (path.endsWith('keyed_list_transitions_page.mjs')) {
        final animatedLists = _nodes(session.node!).where(
          (node) =>
              node.type == 'ListView' && node.props['animateItems'] == true,
        );
        expect(animatedLists, hasLength(1));
        expect(
          animatedLists.single.children,
          everyElement(predicate<JsUiNode>((node) => node.key != null)),
        );
      }
    });
  }
}

Iterable<JsUiNode> _nodes(JsUiNode root) sync* {
  yield root;
  for (final child in root.children) {
    yield* _nodes(child);
  }
}
