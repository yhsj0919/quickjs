import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_example/quickjs_ui_example_pages.dart';

void main() {
  test('Lab catalog exposes every particle demo', () {
    final titles = jsUiLabExamplePages.map((page) => page.title).toSet();

    expect(
      titles,
      containsAll(<String>{
        '粒子特效 · 星际穿梭',
        '粒子特效 · 霓虹星系',
        '粒子特效 · 萤火虫花园',
        '粒子特效 · 能量爆发',
        'Canvas 控件 · 弧形功率仪表盘',
        'Canvas 特效 · 卡片灰飞烟灭',
        '通用特效 · 任意控件本地动画',
        '综合性能 · 自适应效果质量',
      }),
    );
  });
}
