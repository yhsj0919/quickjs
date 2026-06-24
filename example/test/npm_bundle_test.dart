import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generated npm bundle runs as a registered ES module', () async {
    final source = await rootBundle.loadString('assets/js/npm_bundle.mjs');
    expect(source, isNot(contains("from 'fast-deep-equal'")));
    expect(source, isNot(contains('from "fast-deep-equal"')));

    final engine = await Quickjs.create(
      options: QuickjsRuntimeOptions(
        modules: <QuickjsHostModule>[
          QuickjsHostModule.esModule(
            specifier: 'example/npm-bundle',
            source: source,
          ),
        ],
      ),
    );
    addTearDown(engine.dispose);

    await engine.evalModule('''
import { bundledDependency, compareValues } from 'example/npm-bundle';
globalThis.npmBundleTestResult = bundledDependency + '/' + [
  compareValues({ answer: 42 }, { answer: 42 }),
  compareValues({ answer: 42 }, { answer: 7 })
].join('/');
''', name: 'test/use-npm-bundle.mjs');

    expect(
      await engine.eval('globalThis.npmBundleTestResult'),
      'fast-deep-equal/true/false',
    );
  });
}
