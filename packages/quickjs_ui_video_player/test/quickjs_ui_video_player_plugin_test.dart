import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart' show QuickjsHostMount;
import 'package:quickjs_ui/quickjs_ui.dart';
import 'package:quickjs_ui_video_player/quickjs_ui_video_player.dart';

void main() {
  test('loads VideoPlayer through quickjs_ui/video_player import', () async {
    final session = QuickjsUiSession();
    addTearDown(session.dispose);

    await session.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'quickjs_ui_video_player_plugin_test',
        version: '0.1.0',
        source: '''
import { Page } from 'quickjs_ui';
import { VideoPlayer } from 'quickjs_ui/video_player';

export default Page({
  createState() {
    return { ready: false };
  },
  build(state, props, actions) {
    return VideoPlayer({
      source: props.source,
      playing: true,
      loop: true,
      aspectRatio: 1.5,
      onReady: actions.ready(),
      onProgress: actions.progress()
    });
  },
  ready() {
    return { ready: true };
  },
  progress() {
    return null;
  }
});
''',
      ),
      initialProps: const <String, Object?>{
        'source': 'https://example.com/video.mp4',
      },
      mounts: const <QuickjsHostMount>[QuickjsUiVideoPlayerPlugin.mount],
    );

    final node = session.node;
    expect(node?.type, 'VideoPlayer');
    expect(node?.props['source'], 'https://example.com/video.mp4');
    expect(node?.props['playing'], isTrue);
    expect(node?.props['loop'], isTrue);
    expect(node?.props['aspectRatio'], 1.5);
    expect(node?.props['onReady'], isA<Map<String, Object?>>());
    expect(node?.props['onProgress'], isA<Map<String, Object?>>());
    expect(
      (node?.props['onProgress'] as Map<String, Object?>?)?['throttleMs'],
      250,
    );
  });

  test('video plugin page survives progress storms with togglePlay', () async {
    final bundle = await QuickjsUiBundle.fromEntry(
      id: 'quickjs_ui_video_player_stress_page_test',
      version: '0.1.0',
      entry: 'video_player_plugin_page.mjs',
      resolver: QuickjsUiResourceResolver.file(
        basePath: '../../example/assets/quickjs_ui',
      ),
    );
    final session = QuickjsUiSession();
    addTearDown(session.dispose);

    await session.loadPlugin(
      bundle.toPlugin(),
      initialProps: const <String, Object?>{
        'title': 'VideoPlayer plugin demo',
        'autoplay': true,
        'loop': true,
      },
      mounts: const <QuickjsHostMount>[QuickjsUiVideoPlayerPlugin.mount],
    );

    await session.dispatch(<String, Object?>{
      'method': 'onReady',
      'durationMs': 15040,
    });

    for (var index = 0; index < 3000; index += 1) {
      await session.dispatch(<String, Object?>{
        'method': 'onProgress',
        'positionMs': index * 40,
        'durationMs': 15040,
        'isPlaying': index.isEven,
      });
      if (index % 3 == 0) {
        await session.dispatch(<String, Object?>{'method': 'togglePlay'});
      }
    }

    expect(session.state, isA<Map>());
  });
}
