import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiSnappableDustPage extends StatelessWidget {
  const QuickjsUiSnappableDustPage({super.key});
  @override
  Widget build(BuildContext context) => const QuickjsUiDarkAssetDemoPage(
    title: 'Canvas 卡片灰飞烟灭',
    path: 'assets/quickjs_ui/snappable_dust_page.mjs',
  );
}
