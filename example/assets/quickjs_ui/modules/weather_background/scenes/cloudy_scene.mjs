import { Container, Image, Positioned, Stack } from 'quickjs_ui';
import { animationProps, loop, sceneRoot } from '../core/scene_helpers.mjs';

export function CloudyScene(props) {
  const layers = [
    ['cloudy/cloud_2.png', 1, 0.78, 0.01, 126000, 42000],
    ['cloudy/cloud_3.png', 434 / 320, 0.72, 0.08, 108000, 70000],
    ['cloudy/cloud_1.png', 568 / 299, 0.68, 0.16, 93000, 22000]
  ];
  const background = props.weather === 'overcast'
    ? ['#557c99', '#8da9ba', '#c7d5dc']
    : ['#278bd3', '#67bceb', '#c7eef9'];
  const cloudBandHeight = props.height / 3;
  return sceneRoot(props.width, props.height, background, [
    Positioned({
      key: 'cloud-band',
      left: 0,
      top: 0,
      right: 0,
      height: cloudBandHeight,
      child: Stack({
        clipBehavior: 'none',
        children: layers.map(([
          asset,
          aspectRatio,
          heightScale,
          top,
          durationMs,
          phaseMs
        ], index) => {
          const height = cloudBandHeight * heightScale;
          const width = height * aspectRatio;
          return Positioned({
            key: `cloud-${index}`,
            left: -width,
            top: cloudBandHeight * top,
            child: Image({
              src: props.theme.asset(asset),
              width,
              height,
              fit: 'fitWidth',
              ...animationProps(props),
              transform: {
                translate: { x: loop(0, props.width + width, durationMs, phaseMs) }
              },
              filterQuality: 'low'
            })
          });
        })
      })
    })
  ]);
}
