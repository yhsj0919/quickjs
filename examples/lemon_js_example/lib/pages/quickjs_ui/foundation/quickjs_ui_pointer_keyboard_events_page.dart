import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiPointerKeyboardEventsPage extends StatelessWidget {
  const JsUiPointerKeyboardEventsPage({super.key});
  @override
  Widget build(BuildContext context) => const JsUiAssetDemoPage(
    title: '鼠标、指针与键盘',
    path: 'assets/quickjs_ui/pointer_keyboard_events_page.mjs',
  );
}
