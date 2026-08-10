import { animate, Container, Positioned, RepaintBoundary, Stack } from 'quickjs_ui';

export function sceneRoot(width, height, colors, children, stops) {
  return Container({
    width,
    height,
    child: Stack({
      fit: 'expand',
      children: [
        RepaintBoundary({
          child: Container({
            decoration: {
              gradient: {
                type: 'linear',
                begin: 'topCenter',
                end: 'bottomCenter',
                colors,
                ...(stops == null ? {} : { stops })
              }
            }
          })
        }),
        ...children
      ]
    })
  });
}

export function fill(color, opacity = 1) {
  return Positioned({
    left: 0,
    top: 0,
    right: 0,
    bottom: 0,
    child: Container({ opacity, decoration: { color } })
  });
}

export function loop(from, to, durationMs, phaseMs = 0) {
  return animate(from, to, {
    durationMs,
    phaseMs,
    repeat: true,
    curve: 'linear'
  });
}

export function breathe(from, to, durationMs, phaseMs = 0) {
  return animate(from, to, {
    durationMs,
    phaseMs,
    repeat: true,
    autoreverse: true,
    curve: 'easeInOut'
  });
}

export function animationProps(props) {
  return {
    paused: props.paused,
    playToken: props.playToken,
    ...(props.animationFrameIntervalMs == null ? {} : {
      animationFrameIntervalMs: props.animationFrameIntervalMs
    })
  };
}

export function clamp(value, minimum, maximum) {
  const number = Number(value);
  if (!Number.isFinite(number)) return minimum;
  return Math.min(maximum, Math.max(minimum, number));
}
