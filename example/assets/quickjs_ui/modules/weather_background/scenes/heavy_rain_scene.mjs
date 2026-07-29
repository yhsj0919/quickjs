import { Image, Positioned } from 'quickjs_ui';
import { RainLayer } from '../core/rain_layer.mjs';
import { sceneRoot } from '../core/scene_helpers.mjs';

export function HeavyRainScene(props) {
  const cloudWidth = props.width * 1.16;
  return sceneRoot(props.width, props.height, [
    '#172836', '#405765', '#71838b'
  ], [
    RainLayer({ ...props, top: Math.min(props.height * 0.27, props.width * 0.62) }),
    Positioned({
      left: -props.width * 0.08,
      top: -cloudWidth * 0.1,
      child: Image({
        src: props.theme.asset('heavy_rain/cloud_2.png'),
        width: cloudWidth,
        fit: 'fitWidth',
        filterQuality: 'low'
      })
    }),
    Positioned({
      left: -props.width * 0.08,
      top: cloudWidth * 0.08,
      child: Image({
        src: props.theme.asset('heavy_rain/cloud_1.png'),
        width: cloudWidth,
        fit: 'fitWidth',
        filterQuality: 'low'
      })
    })
  ]);
}
