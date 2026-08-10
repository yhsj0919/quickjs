import { RainCloudLayer } from '../core/rain_cloud_layer.mjs';
import { RainLayer } from '../core/rain_layer.mjs';
import { sceneRoot } from '../core/scene_helpers.mjs';

export function HeavyRainScene(props) {
  return sceneRoot(props.width, props.height, [
    '#172836', '#405765', '#71838b'
  ], [
    RainLayer({ ...props, top: Math.min(props.height * 0.2, props.width * 0.42) }),
    RainCloudLayer(props)
  ]);
}
