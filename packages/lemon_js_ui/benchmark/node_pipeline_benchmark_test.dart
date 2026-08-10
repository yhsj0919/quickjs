import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

void main() {
  test('benchmarks large schema preparation and keyed diff identity', () {
    final schema = _largeSchema(sections: 20, itemsPerSection: 50);

    final parse = _measure(30, () => QuickjsUiNode.fromMap(schema));
    final node = QuickjsUiNode.fromMap(schema);
    final cachedDiff = _measure(5000, () => node.structuralSignature);
    final recursiveDiff = _measure(100, () => _legacySignature(node));

    // ignore: avoid_print
    print(
      'nodePipeline nodes=1021 '
      'parseMedian=${_ms(parse.median)}ms '
      'cachedDiffMedian=${_ms(cachedDiff.median)}ms '
      'recursiveDiffMedian=${_ms(recursiveDiff.median)}ms',
    );

    expect(node.children, hasLength(20));
    expect(node.structuralSignature, hasLength(64));
    expect(cachedDiff.median, lessThan(recursiveDiff.median));
  });

  test('benchmarks one-leaf update with immutable keyed subtree reuse', () {
    final initialSchema = _largeSchema(sections: 20, itemsPerSection: 50);
    final updatedSchema = _largeSchema(sections: 20, itemsPerSection: 50);
    final sections = updatedSchema['children']! as List<Object?>;
    final section = sections[10]! as Map<String, Object?>;
    final items = section['children']! as List<Object?>;
    (items[25]! as Map<String, Object?>)['data'] = 'Updated leaf';

    QuickjsUiDiffStats? stats;
    final renderer = QuickjsUiRenderer(
      onEvent: (_) {},
      onDiffStats: (value) => stats = value,
    );
    addTearDown(renderer.dispose);
    renderer.build(QuickjsUiNode.fromMap(initialSchema));

    final stopwatch = Stopwatch()..start();
    renderer.build(QuickjsUiNode.fromMap(updatedSchema));
    stopwatch.stop();

    // Only root, the changed section and the changed leaf are rebuilt. The 19
    // other sections and 49 sibling leaves retain their existing widget trees.
    expect(stats?.rebuilt, 3);
    expect(stats?.reused, 68);
    // ignore: avoid_print
    print(
      'nodeLocalUpdate nodes=1021 rebuilt=${stats?.rebuilt} '
      'reusedSubtrees=${stats?.reused} '
      'parseAndBuild=${_ms(stopwatch.elapsedMicroseconds)}ms',
    );
  });
}

Map<String, Object?> _largeSchema({
  required int sections,
  required int itemsPerSection,
}) {
  return <String, Object?>{
    'type': 'Column',
    'key': 'root',
    'children': <Object?>[
      for (var section = 0; section < sections; section += 1)
        <String, Object?>{
          'type': 'Column',
          'key': 'section-$section',
          'padding': <String, Object?>{'horizontal': 8, 'vertical': 4},
          'children': <Object?>[
            for (var item = 0; item < itemsPerSection; item += 1)
              <String, Object?>{
                'type': 'Text',
                'key': 'item-$section-$item',
                'data': 'Section $section item $item',
                'style': <String, Object?>{
                  'fontSize': 14,
                  'fontWeight': item.isEven ? 'w400' : 'w500',
                },
              },
          ],
        },
    ],
  };
}

_Measurements _measure(int iterations, Object? Function() action) {
  for (var index = 0; index < 5; index += 1) {
    action();
  }
  final samples = <int>[];
  Object? result;
  for (var index = 0; index < iterations; index += 1) {
    final stopwatch = Stopwatch()..start();
    result = action();
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds);
  }
  // Keep the benchmark action observable to the optimizer.
  expect(result, isNotNull);
  samples.sort();
  return _Measurements(samples[samples.length ~/ 2]);
}

String _legacySignature(QuickjsUiNode node) {
  final children = node.children.map(_legacySignature).join(',');
  return '${node.type}|${_stableValue(node.props)}|[$children]';
}

String _stableValue(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return '$value';
  }
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((left, right) => '${left.key}'.compareTo('${right.key}'));
    return '{${entries.map((entry) => '${entry.key}:${_stableValue(entry.value)}').join(',')}}';
  }
  if (value is Iterable) {
    return '[${value.map(_stableValue).join(',')}]';
  }
  return '$value';
}

String _ms(int microseconds) => (microseconds / 1000).toStringAsFixed(3);

final class _Measurements {
  const _Measurements(this.median);

  final int median;
}
