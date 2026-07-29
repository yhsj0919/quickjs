import { SnowLayer } from '../core/snow_layer.mjs';
import { sceneRoot } from '../core/scene_helpers.mjs';

export function HeavySnowScene(props) {
  return sceneRoot(props.width, props.height, [
    '#40576a', '#879cac', '#dce6ee'
  ], [
    SnowLayer(props)
  ]);
}
