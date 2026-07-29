import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiAnchoredOverlayPage extends StatelessWidget {
  const QuickjsUiAnchoredOverlayPage({super.key});
  @override
  Widget build(BuildContext context) => const QuickjsUiAssetDemoPage(
    title: '锚点浮层',
    path: 'assets/quickjs_ui/anchored_overlay_demo_page.mjs',
  );
}
