import 'package:flutter/widgets.dart';

import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiFeedbackOverlaysPage extends StatelessWidget {
  const JsUiFeedbackOverlaysPage({super.key});

  @override
  Widget build(BuildContext context) => const JsUiAssetDemoPage(
    title: '反馈、进度与浮层',
    path: 'assets/quickjs_ui/feedback_overlays_page.mjs',
  );
}
