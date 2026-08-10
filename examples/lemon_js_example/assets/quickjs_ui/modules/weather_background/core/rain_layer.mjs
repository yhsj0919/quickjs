import { Image, Positioned, Stack, animate } from 'quickjs_ui';
import { animationProps } from './scene_helpers.mjs';

const RAIN_PROFILES = Object.freeze({
  lightRain: Object.freeze({ count: 24, minSize: 5, maxSize: 9, minDurationMs: 1400, maxDurationMs: 2200 }),
  moderateRain: Object.freeze({ count: 42, minSize: 6, maxSize: 11, minDurationMs: 1000, maxDurationMs: 1700 }),
  largeRain: Object.freeze({ count: 68, minSize: 7, maxSize: 13, minDurationMs: 700, maxDurationMs: 1250 }),
  heavyRain: Object.freeze({ count: 100, minSize: 8, maxSize: 15, minDurationMs: 450, maxDurationMs: 900 })
});

export function RainLayer(props) {
  const profile = RAIN_PROFILES[props.weather] ?? RAIN_PROFILES.largeRain;
  const top = props.top ?? 0;
  const height = Math.max(1, props.height - top);
  return Positioned({
    left: 0,
    right: 0,
    top,
    bottom: 0,
    child: Stack({
      key: 'weather-rain',
      clipBehavior: 'none',
      children: Array.from({ length: profile.count }, (_, index) => {
        const depth = (index * 37 % 101) / 100;
        const size = mix(profile.minSize, profile.maxSize, depth);
        const durationMs = Math.round(mix(
          profile.maxDurationMs,
          profile.minDurationMs,
          depth
        ));
        const x = ((index * 83 + index * index * 17) % 997) / 997 * props.width;
        return Positioned({
          key: `rain-drop-${index}`,
          left: x - size / 2,
          top: -size * 3,
          child: Image({
            src: props.theme.asset('heavy_rain/raindrop.webp'),
            width: size,
            fit: 'fitWidth',
            opacity: 0.42 + depth * 0.5,
            ...animationProps(props),
            transform: {
              translate: {
                y: animate(0, height + size * 6, {
                  durationMs,
                  phaseMs: Math.round((index * 157) % durationMs),
                  repeat: true,
                  curve: 'linear'
                })
              }
            },
            filterQuality: 'low'
          })
        });
      })
    })
  });
}

function mix(from, to, amount) {
  return from + (to - from) * amount;
}
