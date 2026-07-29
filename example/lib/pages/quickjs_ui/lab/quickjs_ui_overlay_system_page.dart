import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiOverlaySystemPage extends StatelessWidget {
  const QuickjsUiOverlaySystemPage({super.key});
  @override
  Widget build(BuildContext context) => const QuickjsUiDarkAssetDemoPage(
    title: '任意内容浮层系统',
    path: 'assets/quickjs_ui/overlay_system_page.mjs',
  );
}
