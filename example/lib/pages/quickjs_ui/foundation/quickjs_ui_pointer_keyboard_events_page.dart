import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiPointerKeyboardEventsPage extends StatelessWidget {
  const QuickjsUiPointerKeyboardEventsPage({super.key});
  @override
  Widget build(BuildContext context) => const QuickjsUiAssetDemoPage(
    title: '鼠标、指针与键盘',
    path: 'assets/quickjs_ui/pointer_keyboard_events_page.mjs',
  );
}
