import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiSnappableDustPage extends StatelessWidget {
  const JsUiSnappableDustPage({super.key});
  @override
  Widget build(BuildContext context) => const JsUiDarkAssetDemoPage(
    title: 'Canvas 卡片灰飞烟灭',
    path: 'assets/quickjs_ui/snappable_dust_page.mjs',
  );
}
