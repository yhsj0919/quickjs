import { Canvas, Positioned, animate } from 'quickjs_ui';
import { clamp } from './scene_helpers.mjs';

export function SnowLayer(props) {
  const count = Math.round(55 + clamp(props.intensity, 0, 1) * 65);
  return Positioned({
    left: 0,
    top: 0,
    child: Canvas({
      key: 'weather-snow',
      width: props.width,
      height: props.height,
      paused: props.paused,
      playToken: props.playToken,
      willChange: true,
      draw(ctx) {
        ctx.globalCompositeOperation = 'plus';
        for (let index = 0; index < count; index += 1) {
          const x = 8 + ((index * 67) % Math.max(16, props.width - 16));
          const durationMs = 2800 + (index % 17) * 130;
          ctx.fillStyle = index % 4 === 0 ? '#ffffff' : '#dbeafe';
          ctx.globalAlpha = 0.45 + (index % 5) * 0.1;
          ctx.fillCircle(
            animate(x - 12, x + 12, {
              durationMs: 1800 + (index % 11) * 150,
              phaseMs: index * 51,
              repeat: true,
              autoreverse: true,
              curve: 'easeInOut'
            }),
            animate(-16, props.height + 18, {
              durationMs,
              phaseMs: index * 67,
              repeat: true
            }),
            1.4 + (index % 5) * 0.52
          );
        }
      }
    })
  });
}
