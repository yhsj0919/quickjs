import { Image, Positioned, animate } from 'quickjs_ui';
import { HeavyRainScene } from './heavy_rain_scene.mjs';

export function ThunderstormScene(props) {
  const lightning = props.theme.asset(
    `thunderstorm/lightning_${(Number(props.playToken) || 0) % 4 + 1}.png`
  );
  return {
    type: 'Stack',
    children: [
      HeavyRainScene({ ...props, intensity: 0.82 }),
      Positioned({
        left: props.width * 0.1,
        top: 0,
        child: Image({
          src: lightning,
          width: props.width * 0.8,
          height: props.height * 0.68,
          fit: 'contain',
          alignment: 'topCenter',
          paused: props.paused,
          playToken: props.playToken,
          opacity: animate(0, 1, {
            durationMs: 220,
            phaseMs: 2600,
            repeat: true,
            autoreverse: true,
            curve: 'easeOut'
          }),
          filterQuality: 'low'
        })
      })
    ]
  };
}
