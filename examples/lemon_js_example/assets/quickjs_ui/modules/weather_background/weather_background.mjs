import { Container, ResponsiveViewport, Stack } from 'quickjs_ui';
import { defaultWeatherTheme } from './theme.mjs';
import { SunnyScene } from './scenes/sunny_scene.mjs';
import { CloudyScene } from './scenes/cloudy_scene.mjs';
import { OvercastScene } from './scenes/overcast_scene.mjs';
import { HeavyRainScene } from './scenes/heavy_rain_scene.mjs';
import { HeavySnowScene } from './scenes/heavy_snow_scene.mjs';
import { SandstormScene } from './scenes/sandstorm_scene.mjs';
import { ThunderstormScene } from './scenes/thunderstorm_scene.mjs';

const SCENES = Object.freeze({
  sunny: { render: SunnyScene },
  cloudy: { render: CloudyScene },
  overcast: { render: OvercastScene },
  haze: { render: SandstormScene, intensity: 0.35 },
  sandstorm: { render: SandstormScene, intensity: 0.85 },
  lightRain: { render: HeavyRainScene, intensity: 0.28 },
  moderateRain: { render: HeavyRainScene, intensity: 0.5 },
  largeRain: { render: HeavyRainScene, intensity: 0.72 },
  thunderstorm: { render: ThunderstormScene, intensity: 0.82 },
  heavyRain: { render: HeavyRainScene, intensity: 1 },
  lightSnow: { render: HeavySnowScene, intensity: 0.25 },
  moderateSnow: { render: HeavySnowScene, intensity: 0.5 },
  largeSnow: { render: HeavySnowScene, intensity: 0.72 },
  heavySnow: { render: HeavySnowScene, intensity: 1 }
});

export function WeatherBackground(props = {}) {
  const width = positive(props.width, 360);
  const height = positive(props.height, 560);
  const type = SCENES[props.weather] == null ? 'sunny' : props.weather;
  const scene = SCENES[type];
  const fps = frameRate(props.fps);
  const sceneProps = {
    weather: type,
    width,
    height,
    intensity: props.intensity ?? scene.intensity ?? 0.75,
    paused: props.paused === true,
    playToken: props.playToken ?? 0,
    ...(fps == null ? {} : {
      animationFrameIntervalMs: Math.max(4, Math.round(1000 / fps))
    }),
    theme: props.theme ?? defaultWeatherTheme
  };
  const sceneNode = Container({
    width,
    height,
    ignorePointer: true,
    child: scene.render(sceneProps)
  });
  const responsive = props.responsive === true;
  const borderRadius = Math.max(0, Number(props.borderRadius ?? 28) || 0);
  const children = [responsive
    ? ResponsiveViewport({
        designWidth: width,
        designHeight: height,
        fit: props.viewportFit ?? 'cover',
        alignment: props.viewportAlignment ?? 'center',
        child: sceneNode
      })
    : sceneNode];
  if (props.child != null) children.push(props.child);
  return Container({
    key: props.key,
    ...(responsive ? {} : { width, height }),
    ...(borderRadius > 0 ? { clipRadius: borderRadius } : {}),
    decoration: {
      color: '#172836',
      ...(borderRadius > 0 ? { borderRadius } : {})
    },
    child: Stack({ fit: responsive ? 'expand' : 'loose', children })
  });
}

function positive(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : fallback;
}

function frameRate(value) {
  if (value == null) return null;
  const fps = Number(value);
  if (!Number.isFinite(fps) || fps <= 0 || fps > 240) {
    throw new RangeError('WeatherBackground fps must be between 1 and 240');
  }
  return fps;
}
