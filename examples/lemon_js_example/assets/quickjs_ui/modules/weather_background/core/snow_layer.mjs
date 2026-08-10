import { Image, ParticleFlow, Positioned } from 'quickjs_ui';

const SNOW_PROFILES = Object.freeze({
  lightSnow: Object.freeze({ farCount: 18, nearCount: 6 }),
  moderateSnow: Object.freeze({ farCount: 32, nearCount: 10 }),
  largeSnow: Object.freeze({ farCount: 51, nearCount: 17 }),
  heavySnow: Object.freeze({ farCount: 90, nearCount: 30 })
});

export function SnowLayer(props) {
  const profile = SNOW_PROFILES[props.weather] ?? SNOW_PROFILES.largeSnow;
  const particles = [
    ...Array.from(
      { length: profile.farCount },
      (_, index) => farParticle(props, index)
    ),
    ...Array.from(
      { length: profile.nearCount },
      (_, index) => nearParticle(props, index)
    )
  ];
  return Positioned({
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
    child: ParticleFlow({
      key: `weather-snow-particles-${props.weather}`,
      width: props.width,
      height: props.height,
      frameIntervalMs: props.animationFrameIntervalMs,
      paused: props.paused,
      playToken: props.playToken,
      particles: particles.map((particle) => ({
        fromX: particle.x - particle.size / 2,
        toX: particle.x - particle.size / 2,
        fromY: -particle.size * 2,
        toY: props.height + particle.size * 2,
        fromOpacity: particle.opacity,
        toOpacity: particle.opacity,
        durationMs: particle.durationMs,
        phaseMs: particle.phaseMs,
      })),
      children: particles.map((particle, index) => snowflake(
        props,
        particle,
        index
      )),
    })
  });
}

function snowflake(props, particle, index) {
  return Image({
    key: `snowflake-${index}`,
    src: props.theme.asset('heavy_snow/snowflake.png'),
    width: particle.size,
    height: particle.size,
    fit: 'contain',
    filterQuality: 'low',
  });
}

function farParticle(props, index) {
  const size = 3 + random(index, 71) * 4;
  const durationMs = Math.round(9000 + random(index, 29) * 7000);
  return {
    x: 8 + random(index, 11) * Math.max(16, props.width - 16),
    size,
    opacity: 0.18 + random(index, 107) * 0.26,
    durationMs,
    phaseMs: Math.round(random(index, 47) * durationMs)
  };
}

function nearParticle(props, index) {
  const depth = random(index, 131);
  const size = 12 + depth * 12;
  const durationMs = Math.round(9000 + random(index, 149) * 5000);
  return {
    x: random(index, 167) * props.width,
    size,
    opacity: 0.58 + depth * 0.36,
    durationMs,
    phaseMs: Math.round(random(index, 181) * durationMs)
  };
}

function random(index, salt) {
  const value = Math.sin((index + 1) * 12.9898 + salt * 78.233) * 43758.5453;
  return value - Math.floor(value);
}
