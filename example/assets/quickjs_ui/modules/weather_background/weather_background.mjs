import { Container, Stack } from 'quickjs_ui';
import { defaultWeatherTheme } from './theme.mjs';
import { SunnyScene } from './scenes/sunny_scene.mjs';
import { CloudyScene } from './scenes/cloudy_scene.mjs';
import { HeavyRainScene } from './scenes/heavy_rain_scene.mjs';
import { HeavySnowScene } from './scenes/heavy_snow_scene.mjs';
import { SandstormScene } from './scenes/sandstorm_scene.mjs';
import { ThunderstormScene } from './scenes/thunderstorm_scene.mjs';

const SCENES = Object.freeze({
  sunny: { render: SunnyScene },
  cloudy: { render: CloudyScene },
  overcast: { render: CloudyScene },
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
  const sceneProps = {
    width,
    height,
    intensity: props.intensity ?? scene.intensity ?? 0.75,
    paused: props.paused === true,
    playToken: props.playToken ?? 0,
    theme: props.theme ?? defaultWeatherTheme
  };
  const children = [Container({
    width,
    height,
    ignorePointer: true,
    child: scene.render(sceneProps)
  })];
  if (props.child != null) children.push(props.child);
  return Container({
    key: props.key,
    width,
    height,
    clipRadius: props.borderRadius ?? 28,
    decoration: { color: '#172836', borderRadius: props.borderRadius ?? 28 },
    child: Stack({ children })
  });
}

function positive(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : fallback;
}
