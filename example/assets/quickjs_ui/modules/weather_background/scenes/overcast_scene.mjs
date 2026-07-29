import { RainCloudLayer } from '../core/rain_cloud_layer.mjs';
import { sceneRoot } from '../core/scene_helpers.mjs';

export function OvercastScene(props) {
  return sceneRoot(props.width, props.height, [
    '#172836', '#405765', '#71838b'
  ], [
    RainCloudLayer(props)
  ]);
}
