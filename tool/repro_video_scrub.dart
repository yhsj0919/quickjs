import 'package:quickjs/quickjs.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

Future<void> main() async {
  final bundle = await QuickjsUiBundle.asset(
    path: 'assets/quickjs_ui/native_video_player_page.mjs',
    bundleRoot: 'example',
  );
  final engine = await Quickjs.create();
  final session = QuickjsUiSession(engine: engine);

  await session.loadPlugin(
    bundle.toPlugin(),
    initialProps: const <String, Object?>{
      'title': 'scrub repro',
      'autoplay': false,
      'loop': true,
    },
  );

  // Simulate ready + many paused progress updates.
  await session.dispatch(<String, Object?>{
    'method': 'onReady',
    'durationMs': 60000,
  });

  for (var i = 0; i < 5000; i++) {
    await session.dispatch(<String, Object?>{
      'method': 'onProgress',
      'positionMs': i * 10,
      'durationMs': 60000,
      'isPlaying': false,
    });
  }

  print('state keys: ${(session.state as Map).keys.toList()}');
  print('dispatching scrub...');
  try {
    await session.dispatch(<String, Object?>{
      'method': 'scrub',
      'value': 12000.0,
    });
    print('scrub ok, state=${session.state}');
    await session.dispatch(<String, Object?>{
      'method': 'seek',
      'value': 12000.0,
    });
    print('seek ok');
  } catch (error, stack) {
    print('FAILED: $error');
    print(stack);
  } finally {
    session.dispose();
    await engine.dispose();
  }
}
