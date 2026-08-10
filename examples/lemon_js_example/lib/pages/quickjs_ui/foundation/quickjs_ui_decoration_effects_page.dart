import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiDecorationEffectsPage extends StatelessWidget {
  const QuickjsUiDecorationEffectsPage({super.key});
  @override
  Widget build(BuildContext context) => const QuickjsUiAssetDemoPage(
    title: '渐变、边框与阴影',
    path: 'assets/quickjs_ui/decoration_effects_page.mjs',
  );
}
