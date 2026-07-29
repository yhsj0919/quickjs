import 'package:flutter/widgets.dart';

import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiFeedbackOverlaysPage extends StatelessWidget {
  const QuickjsUiFeedbackOverlaysPage({super.key});

  @override
  Widget build(BuildContext context) => const QuickjsUiAssetDemoPage(
    title: '反馈、进度与浮层',
    path: 'assets/quickjs_ui/feedback_overlays_page.mjs',
  );
}
