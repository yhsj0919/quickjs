import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_example/example_page_spec.dart';
import 'package:quickjs_example/quickjs_ui_example_pages.dart';

void main() {
  test('quickjs_ui catalog has complete and unique category metadata', () {
    final groups = <ExampleCategory, List<ExamplePageSpec>>{
      ExampleCategory.gettingStarted: quickjsUiGettingStartedExamplePages,
      ExampleCategory.uiFoundation: quickjsUiFoundationExamplePages,
      ExampleCategory.platform: quickjsUiPlatformExamplePages,
      ExampleCategory.scenario: quickjsUiScenarioExamplePages,
      ExampleCategory.lab: quickjsUiLabExamplePages,
    };
    final groupedPages = groups.entries
        .expand((entry) {
          expect(entry.value, isNotEmpty, reason: '${entry.key} is empty');
          for (final page in entry.value) {
            expect(page.category, entry.key, reason: page.title);
            expect(page.tags, isNotEmpty, reason: page.title);
          }
          return entry.value;
        })
        .toList(growable: false);

    expect(groupedPages, quickjsUiExamplePages);
    expect(
      groupedPages.map((page) => page.title).toSet().length,
      groupedPages.length,
      reason: 'Every catalog title must be unique.',
    );
    expect(
      quickjsUiLabExamplePages.every(
        (page) =>
            page.kind == ExampleKind.benchmark &&
            page.status == ExampleStatus.experimental,
      ),
      isTrue,
    );
  });
}
