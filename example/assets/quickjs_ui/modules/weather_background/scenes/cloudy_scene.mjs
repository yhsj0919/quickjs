import { Image, Positioned } from 'quickjs_ui';
import { loop, sceneRoot } from '../core/scene_helpers.mjs';

export function CloudyScene(props) {
  const layers = [
    ['cloudy/cloud_2.png', 0.92, -0.03, 28000, 0],
    ['cloudy/cloud_3.png', 1.08, 0.06, 23000, 6200],
    ['cloudy/cloud_1.png', 1.42, 0.15, 19000, 10700]
  ];
  return sceneRoot(props.width, props.height, [
    '#557c99', '#8da9ba', '#c7d5dc'
  ], [
    ...layers.map(([asset, scale, top, durationMs, phaseMs], index) => {
      const width = props.width * scale;
      return Positioned({
        key: `cloud-${index}`,
        left: -width,
        top: props.height * top,
        child: Image({
          src: props.theme.asset(asset),
          width,
          fit: 'fitWidth',
          paused: props.paused,
          playToken: props.playToken,
          transform: {
            translate: { x: loop(0, props.width + width, durationMs, phaseMs) }
          },
          filterQuality: 'low'
        })
      });
    })
  ]);
}
