import { Canvas, Positioned, animate } from 'quickjs_ui';
import { clamp } from './scene_helpers.mjs';

export function RainLayer(props) {
  const count = Math.round(70 + clamp(props.intensity, 0, 1) * 80);
  return Positioned({
    left: 0,
    top: props.top ?? 0,
    child: Canvas({
      key: 'weather-rain',
      width: props.width,
      height: props.height - (props.top ?? 0),
      paused: props.paused,
      playToken: props.playToken,
      willChange: true,
      draw(ctx) {
        ctx.lineCap = 'round';
        ctx.globalCompositeOperation = 'plus';
        for (let index = 0; index < count; index += 1) {
          const x = ((index * 73) % Math.ceil(props.width + 60)) - 30;
          const length = 12 + (index % 6) * 3;
          const durationMs = 580 + (index % 13) * 29;
          const options = {
            durationMs,
            phaseMs: index * 43,
            repeat: true
          };
          ctx.strokeStyle = index % 4 === 0 ? '#e0f2fe' : '#93c5fd';
          ctx.globalAlpha = 0.3 + (index % 5) * 0.1;
          ctx.lineWidth = 0.8 + (index % 3) * 0.5;
          ctx.drawLine(
            x,
            animate(-length, props.height, options),
            x + 9,
            animate(0, props.height + length, options)
          );
        }
      }
    })
  });
}
