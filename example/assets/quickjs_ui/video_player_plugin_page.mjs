import {
  Column,
  ElevatedButton,
  ListView,
  Page,
  Slider,
  Text
} from 'quickjs_ui';
import { VideoPlayer } from 'quickjs_ui/video_player';

const DEFAULT_SOURCE =
  'https://ht-1368.oss-cn-qingdao.aliyuncs.com/media/202607/8733401de810_9%E6%9C%8830%E6%97%A5%E9%93%AD%E8%AE%B0%E5%8E%86%E5%8F%B2-%E5%BD%A9%E4%BA%91.mp4';

function formatMs(value) {
  const totalMs = Math.max(0, value ?? 0);
  const totalSeconds = Math.floor(totalMs / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  const tenths = Math.floor((totalMs % 1000) / 100);
  return `${minutes}:${String(seconds).padStart(2, '0')}.${tenths}`;
}

export default Page({
  name: 'VideoPlayerPluginStressPage',

  createState(props) {
    const autoplay = props.autoplay !== false;
    const loop = props.loop !== false;
    return {
      autoplay,
      loop,
      playing: autoplay,
      ready: false,
      scrubbing: false,
      wasPlayingBeforeScrub: false,
      positionMs: 0,
      scrubPositionMs: 0,
      durationMs: 0,
      seekPositionMs: 0,
      seekToken: 0,
      endedCount: 0,
      restartToken: 0,
      status: autoplay ? '等待自动播放' : '等待 VideoPlayer 初始化'
    };
  },

  build(state, props, page) {
    const sliderValue = state.scrubbing ? state.scrubPositionMs : state.positionMs;
    const sliderMax = Math.max(state.durationMs, 1);

    return ListView({
      padding: 16,
      shrinkWrap: true,
      children: [
        Text(props.title ?? 'VideoPlayer plugin stress demo', {
          style: { fontSize: 20, fontWeight: 'bold' }
        }),
        Text('Imported from quickjs_ui/video_player; progress updates use sample events.'),
        VideoPlayer({
          key: 'demo-player',
          playerKey: 'demo-player',
          source: props.source ?? DEFAULT_SOURCE,
          playing: state.playing,
          loop: state.loop,
          progressThrottleMs: 50,
          progressCoalesceKey: 'demo-player:progress',
          restartToken: state.restartToken,
          seekToken: state.seekToken,
          seekPositionMs: state.seekPositionMs,
          onReady: page.onReady(),
          onProgress: page.onProgress(),
          onEnded: page.onEnded(),
          onError: page.onError()
        }),
        ...(state.ready
          ? [
              Slider({
                min: 0,
                max: sliderMax,
                value: Math.min(sliderValue, sliderMax),
                label: formatMs(sliderValue),
                ...(state.durationMs > 0
                  ? {
                      onChanged: page.scrub(),
                      onChangeEnd: page.seek()
                    }
                  : {})
              })
            ]
          : []),
        Text(`状态：${state.status}`),
        Text(
          `进度：${formatMs(state.positionMs)} / ${formatMs(state.durationMs)}` +
            ` | 播放结束次数：${state.endedCount}` +
            ` | 自动播放：${state.autoplay ? '开' : '关'}` +
            ` | 循环：${state.loop ? '开' : '关'}`
        ),
        Column({
          gap: 12,
          children: [
            ElevatedButton({
              child: Text(state.playing ? '暂停' : '播放'),
              ...(state.ready ? { onPressed: page.togglePlay() } : {})
            }),
            ElevatedButton({
              child: Text('从头播放'),
              ...(state.ready ? { onPressed: page.restart() } : {})
            })
          ]
        })
      ]
    });
  },

  onReady(state, _payload, _props, event) {
    const playing = state.autoplay ? true : state.playing;
    return {
      ready: true,
      playing,
      durationMs: event.durationMs ?? state.durationMs,
      status: playing
        ? state.loop
          ? '自动播放中（循环）'
          : '自动播放中'
        : 'VideoPlayer 已就绪'
    };
  },

  onProgress(state, _payload, _props, event) {
    if (state.scrubbing) {
      return {
        durationMs: event.durationMs ?? state.durationMs
      };
    }
    return {
      positionMs: event.positionMs ?? state.positionMs,
      durationMs: event.durationMs ?? state.durationMs
    };
  },

  onEnded(state) {
    if (state.loop) {
      return {
        playing: true,
        restartToken: state.restartToken + 1,
        endedCount: state.endedCount + 1,
        positionMs: 0,
        status: '循环播放中'
      };
    }
    return {
      playing: false,
      endedCount: state.endedCount + 1,
      status: '播放结束'
    };
  },

  onError(state, _payload, _props, event) {
    return {
      playing: false,
      ready: false,
      status: `播放错误：${event.message ?? 'unknown'}`
    };
  },

  scrub(state, _payload, _props, event) {
    const value = Math.max(0, event.value ?? state.positionMs);
    if (!state.scrubbing) {
      return {
        scrubbing: true,
        wasPlayingBeforeScrub: state.playing,
        playing: false,
        scrubPositionMs: value,
        status: '拖动进度'
      };
    }
    return {
      scrubPositionMs: value
    };
  },

  seek(state, _payload, _props, event) {
    const value = Math.max(0, event.value ?? state.scrubPositionMs);
    const playing = state.wasPlayingBeforeScrub;
    return {
      scrubbing: false,
      wasPlayingBeforeScrub: false,
      seekToken: state.seekToken + 1,
      seekPositionMs: value,
      positionMs: value,
      scrubPositionMs: value,
      playing,
      status: playing ? '播放中' : '已定位'
    };
  },

  togglePlay(state) {
    if (!state.ready) {
      return null;
    }
    return {
      playing: !state.playing,
      status: state.playing ? '已暂停' : '播放中'
    };
  },

  restart(state) {
    return {
      playing: true,
      restartToken: state.restartToken + 1,
      positionMs: 0,
      scrubPositionMs: 0,
      seekPositionMs: 0,
      status: '从头播放'
    };
  }
});
