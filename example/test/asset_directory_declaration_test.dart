import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('directory declarations include top-level and nested assets', () async {
    for (final path in <String>[
      'assets/js/npm_bundle.mjs',
      'assets/quickjs_ui/universal_effects_page.mjs',
      'assets/quickjs_ui/control_states_slots_page.mjs',
      'assets/quickjs_ui/bundle_counter/pages/main.mjs',
      'assets/quickjs_ui/bundle_counter/components/counter_card.mjs',
      'assets/quickjs_ui/package_demo/main.mjs',
      'assets/quickjs_ui/package_demo/components/package_summary.mjs',
      'assets/quickjs_ui/weatherIcon/avalanche-danger-alert.svg',
      'assets/plugins/zip_demo.zip',
    ]) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: path);
    }
  });
}
