import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiArcGaugePage extends StatelessWidget {
  const JsUiArcGaugePage({super.key});
  @override
  Widget build(BuildContext context) => const JsUiDarkAssetDemoPage(
    title: 'Canvas 弧形功率仪表盘',
    path: 'assets/quickjs_ui/arc_gauge_page.mjs',
  );
}
