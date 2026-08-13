import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_ui_video_player/lemon_js_ui_video_player.dart';

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
      fit: 'cover',
      backgroundColor: '#000000',
      playbackSpeed: 0.5,
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
      features: QuickjsUiVideoPlayerPlugin.plugin.features,
    );

    final node = session.node;
    expect(node?.type, 'VideoPlayer');
    expect(node?.props['source'], 'https://example.com/video.mp4');
    expect(node?.props['playing'], isTrue);
    expect(node?.props['loop'], isTrue);
    expect(node?.props.containsKey('aspectRatio'), isFalse);
    expect(node?.props['fit'], 'cover');
    expect(node?.props['backgroundColor'], '#000000');
    expect(node?.props['playbackSpeed'], 0.5);
    expect(node?.props['onReady'], isA<Map<String, Object?>>());
    expect(node?.props['onProgress'], isA<Map<String, Object?>>());
    expect(
      (node?.props['onProgress'] as Map<String, Object?>?)?['throttleMs'],
      250,
    );
  });

  test('VideoPlayer callbacks are optional', () async {
    final session = QuickjsUiSession();
    addTearDown(session.dispose);

    await session.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'quickjs_ui_video_player_optional_callbacks_test',
        version: '0.1.0',
        source: '''
import { Page } from 'quickjs_ui';
import { VideoPlayer } from 'quickjs_ui/video_player';

export default Page({
  build(_state, props) {
    return VideoPlayer({ source: props.source });
  }
});
''',
      ),
      initialProps: const <String, Object?>{
        'source': 'https://example.com/video.mp4',
      },
      features: QuickjsUiVideoPlayerPlugin.plugin.features,
    );

    final props = session.node?.props ?? const <String, Object?>{};
    expect(session.node?.type, 'VideoPlayer');
    expect(props['source'], 'https://example.com/video.mp4');
    expect(props['playing'], isFalse);
    expect(props['loop'], isFalse);
    expect(props['playbackSpeed'], 1);
    expect(props.containsKey('aspectRatio'), isFalse);
    expect(props['onReady'], isNull);
    expect(props['onProgress'], isNull);
    expect(props['onEnded'], isNull);
    expect(props['onError'], isNull);
  });

  test('video plugin page survives progress storms with togglePlay', () async {
    final bundle = await QuickjsUiBundle.fromEntry(
      id: 'quickjs_ui_video_player_stress_page_test',
      version: '0.1.0',
      entry: 'video_player_plugin_page.mjs',
      resolver: QuickjsUiResourceResolver.file(
        basePath: '../../examples/lemon_js_example/assets/quickjs_ui',
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
      features: QuickjsUiVideoPlayerPlugin.plugin.features,
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
