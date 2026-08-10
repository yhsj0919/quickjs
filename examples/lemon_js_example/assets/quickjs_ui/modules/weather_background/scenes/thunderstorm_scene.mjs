import { Image, Positioned, Stack, keyframes } from 'quickjs_ui';
import { HeavyRainScene } from './heavy_rain_scene.mjs';
import { animationProps } from '../core/scene_helpers.mjs';

const LIGHTNING = Object.freeze([
  Object.freeze({ assetIndex: 1, left: 0.02, width: 0.52, phaseMs: 0 }),
  Object.freeze({ assetIndex: 3, left: 0.18, width: 0.46, phaseMs: 2300 }),
  Object.freeze({ assetIndex: 2, left: 0.42, width: 0.54, phaseMs: 5100 }),
  Object.freeze({
    assetIndex: 4,
    left: 0.49,
    width: 0.54,
    height: 0.66,
    phaseMs: 7900
  })
]);

const LIGHTNING_CYCLE_MS = 10800;
const LIGHTNING_FLASH = Object.freeze([
  Object.freeze({ offset: 0, value: 0 }),
  Object.freeze({ offset: 0.92, value: 0 }),
  Object.freeze({ offset: 0.922, value: 1 }),
  Object.freeze({ offset: 0.924, value: 1 }),
  Object.freeze({ offset: 0.9274, value: 0 }),
  Object.freeze({ offset: 0.94, value: 0 }),
  Object.freeze({ offset: 0.947, value: 0.92 }),
  Object.freeze({ offset: 0.9685, value: 0.92 }),
  Object.freeze({ offset: 1, value: 0 })
]);

export function ThunderstormScene(props) {
  return Stack({
    children: [
      HeavyRainScene({ ...props, weather: 'moderateRain' }),
      ...LIGHTNING.map((lightning) => Positioned({
        key: `weather-lightning-${lightning.assetIndex}`,
        left: props.width * lightning.left,
        top: -props.height * 0.04,
        child: Image({
          src: props.theme.asset(
            `thunderstorm/lightning_${lightning.assetIndex}.png`
          ),
          width: props.width * lightning.width,
          height: props.height * (lightning.height ?? 0.56),
          fit: 'contain',
          alignment: 'topCenter',
          ...animationProps(props),
          opacity: keyframes(LIGHTNING_FLASH, {
            durationMs: LIGHTNING_CYCLE_MS,
            phaseMs: lightning.phaseMs,
            repeat: true,
            keyframes: LIGHTNING_FLASH
          }),
          filterQuality: 'low'
        })
      }))
    ]
  });
}
