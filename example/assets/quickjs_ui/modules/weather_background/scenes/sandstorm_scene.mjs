import { Image, Positioned } from 'quickjs_ui';
import { loop, sceneRoot } from '../core/scene_helpers.mjs';

export function SandstormScene(props) {
  const strength = Math.max(0.2, Math.min(1, Number(props.intensity) || 0.75));
  return sceneRoot(props.width, props.height, [
    '#705038', '#a77850', '#d1ad7e'
  ], [
    ...['sandstorm/dust_2.png', 'sandstorm/dust_1.png'].map((asset, index) => {
      const width = props.width * (index === 0 ? 1.15 : 1.45);
      return Positioned({
        left: -width,
        top: props.height * (index === 0 ? 0.08 : 0.22),
        child: Image({
          src: props.theme.asset(asset),
          width,
          fit: 'fitWidth',
          opacity: (index === 0 ? 0.68 : 0.82) * strength,
          paused: props.paused,
          playToken: props.playToken,
          transform: {
            translate: {
              x: loop(0, props.width + width, index === 0 ? 21000 : 15000, index * 5200)
            }
          },
          filterQuality: 'low'
        })
      });
    })
  ]);
}
