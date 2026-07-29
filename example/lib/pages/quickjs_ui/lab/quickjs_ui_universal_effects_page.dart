import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiUniversalEffectsPage extends StatelessWidget {
  const QuickjsUiUniversalEffectsPage({super.key});
  @override
  Widget build(BuildContext context) => const QuickjsUiDarkAssetDemoPage(
    title: '任意控件本地特效',
    path: 'assets/quickjs_ui/universal_effects_page.mjs',
  );
}
