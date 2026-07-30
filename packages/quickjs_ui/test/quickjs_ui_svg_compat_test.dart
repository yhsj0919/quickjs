import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_ui/src/renderer/quickjs_ui_svg_compat.dart';

void main() {
  test('normalizes black fills inside alpha masks only', () {
    const source = '''
<svg>
  <path id="visible" fill="black" />
  <mask id="alpha" style="mask-type:alpha">
    <path id="masked" fill="black" />
  </mask>
  <mask id="luminance">
    <path id="luminance-black" fill="black" />
  </mask>
</svg>
''';

    final normalized = normalizeQuickjsUiSvg(source);

    expect(normalized, contains('<path id="visible" fill="black" />'));
    expect(normalized, contains('<path id="masked" fill="white" />'));
    expect(normalized, contains('<path id="luminance-black" fill="black" />'));
  });

  test('supports mask-type attribute and compact black hex colors', () {
    const source = '''
<svg><mask mask-type='alpha'><path fill='#000'/></mask></svg>
''';

    expect(normalizeQuickjsUiSvg(source), contains("<path fill='white'/>"));
  });
}
