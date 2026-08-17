import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiDecorationEffectsPage extends StatelessWidget {
  const JsUiDecorationEffectsPage({super.key});
  @override
  Widget build(BuildContext context) => const JsUiAssetDemoPage(
    title: '渐变、边框与阴影',
    path: 'assets/quickjs_ui/decoration_effects_page.mjs',
  );
}
