import { Image, Positioned, Stack, animate } from 'quickjs_ui';
import { animationProps } from './scene_helpers.mjs';

const SNOW_PROFILES = Object.freeze({
  lightSnow: Object.freeze({ farCount: 18, nearCount: 6 }),
  moderateSnow: Object.freeze({ farCount: 32, nearCount: 10 }),
  largeSnow: Object.freeze({ farCount: 51, nearCount: 17 }),
  heavySnow: Object.freeze({ farCount: 90, nearCount: 30 })
});

export function SnowLayer(props) {
  const profile = SNOW_PROFILES[props.weather] ?? SNOW_PROFILES.largeSnow;
  return Positioned({
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
    child: Stack({
      clipBehavior: 'none',
      children: [
        ...Array.from(
          { length: profile.farCount },
          (_, index) => farSnowflake(props, index)
        ),
        ...Array.from(
          { length: profile.nearCount },
          (_, index) => nearSnowflake(props, index)
        )
      ]
    })
  });
}

function farSnowflake(props, index) {
  const size = 3 + random(index, 71) * 4;
  const durationMs = Math.round(9000 + random(index, 29) * 7000);
  const x = 8 + random(index, 11) * Math.max(16, props.width - 16);
  return Positioned({
    key: `weather-snow-far-${index}`,
    left: x - size / 2,
    top: -size * 2,
    child: Image({
      src: props.theme.asset('heavy_snow/snowflake.png'),
      width: size,
      height: size,
      fit: 'contain',
      opacity: 0.18 + random(index, 107) * 0.26,
      ...animationProps(props),
      transform: {
        translate: {
          y: animate(0, props.height + size * 4, {
            durationMs,
            phaseMs: Math.round(random(index, 47) * durationMs),
            repeat: true,
            curve: 'linear'
          })
        }
      },
      filterQuality: 'low'
    })
  });
}

function random(index, salt) {
  const value = Math.sin((index + 1) * 12.9898 + salt * 78.233) * 43758.5453;
  return value - Math.floor(value);
}

function nearSnowflake(props, index) {
  const depth = random(index, 131);
  const size = 12 + depth * 12;
  const durationMs = Math.round(9000 + random(index, 149) * 5000);
  const x = random(index, 167) * props.width;
  return Positioned({
    key: `weather-snowflake-${index}`,
    left: x - size / 2,
    top: -size * 2,
    child: Image({
      src: props.theme.asset('heavy_snow/snowflake.png'),
      width: size,
      height: size,
      fit: 'contain',
      opacity: 0.58 + depth * 0.36,
      ...animationProps(props),
      transform: {
        translate: {
          y: animate(0, props.height + size * 4, {
            durationMs,
            phaseMs: Math.round(random(index, 181) * durationMs),
            repeat: true,
            curve: 'linear'
          })
        }
      },
      filterQuality: 'low'
    })
  });
}
