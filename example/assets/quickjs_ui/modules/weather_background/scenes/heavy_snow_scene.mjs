import { Image, Positioned } from 'quickjs_ui';
import { SnowLayer } from '../core/snow_layer.mjs';
import { breathe, sceneRoot } from '../core/scene_helpers.mjs';

export function HeavySnowScene(props) {
  return sceneRoot(props.width, props.height, [
    '#40576a', '#879cac', '#dce6ee'
  ], [
    Positioned({
      right: props.width * 0.08,
      top: props.height * 0.08,
      child: Image({
        src: props.theme.asset('heavy_snow/snowflake.png'),
        width: props.width * 0.42,
        height: props.width * 0.42,
        fit: 'contain',
        opacity: 0.22,
        paused: props.paused,
        playToken: props.playToken,
        transform: { rotate: breathe(-0.14, 0.14, 6800) },
        filterQuality: 'low'
      })
    }),
    SnowLayer(props)
  ]);
}
