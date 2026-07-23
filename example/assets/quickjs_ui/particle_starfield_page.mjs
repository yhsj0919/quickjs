import { animate, Canvas, Center, Page } from 'quickjs_ui';

const width = 360;
const height = 560;

function drawStarfield(ctx) {
  const colors = ['#ffffff', '#dbeafe', '#bfdbfe', '#a5f3fc'];
  for (let index = 0; index < 520; index += 1) {
    const lane = ((index * 137.508) % 360);
    const depth = (index % 13) / 12;
    const duration = 650 + (1 - depth) * 1900;
    const phase = (index * 97) % duration;
    const trail = 3 + depth * 22;
    const options = { durationMs: duration, phaseMs: phase, repeat: true };
    ctx.strokeStyle = colors[index % colors.length];
    ctx.lineWidth = 0.6 + depth * 1.8;
    ctx.lineCap = 'round';
    ctx.globalAlpha = 0.3 + depth * 0.7;
    ctx.globalCompositeOperation = 'plus';
    ctx.drawLine(
      lane,
      animate(-30 - trail, height + 30 - trail, options),
      lane,
      animate(-30, height + 30, options)
    );
  }
}

export default Page({
  createState() { return {}; },
  build() {
    return Center({
      child: Canvas({
        key: 'warp-starfield',
        width,
        height,
        backgroundColor: '#020617',
        staticDraw(ctx) {
          ctx.fillStyle = '#071b3d';
          ctx.fillCircle(180, 280, 120);
          ctx.fillStyle = '#0c2b61';
          ctx.fillCircle(180, 280, 55);
        },
        draw: drawStarfield
      })
    });
  }
});
