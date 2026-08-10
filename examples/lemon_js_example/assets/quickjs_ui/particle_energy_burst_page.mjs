import { animate, Canvas, Center, Page } from 'quickjs_ui';

const size = 360;
const center = size / 2;

function pulse(to, durationMs, phaseMs) {
  return animate(4, to, { durationMs, phaseMs, repeat: true, curve: 'easeOut' });
}

function drawBurst(ctx) {
  const colors = ['#22d3ee', '#38bdf8', '#818cf8', '#c084fc', '#f0abfc'];
  for (let index = 0; index < 360; index += 1) {
    const angle = index * 2.399963229728653;
    const distance = 80 + (index % 19) * 5;
    const duration = 700 + (index % 23) * 55;
    const phase = index * 31;
    ctx.save();
    ctx.translate(center, center);
    ctx.rotate(angle);
    ctx.translate(pulse(distance, duration, phase), 0);
    ctx.fillStyle = colors[index % colors.length];
    ctx.globalAlpha = 0.38 + (index % 10) * 0.055;
    ctx.globalCompositeOperation = 'plus';
    ctx.fillCircle(0, 0, 1 + (index % 6) * 0.32);
    ctx.restore();
  }
  ctx.fillStyle = '#67e8f9';
  ctx.globalAlpha = 0.45;
  ctx.globalCompositeOperation = 'plus';
  ctx.fillCircle(
    center,
    center,
    animate(12, 34, {
      durationMs: 900,
      repeat: true,
      autoreverse: true,
      curve: 'easeInOut'
    })
  );
  ctx.fillStyle = '#ffffff';
  ctx.globalAlpha = 1;
  ctx.fillCircle(center, center, 10);
}

export default Page({
  createState() { return {}; },
  build() {
    return Center({
      child: Canvas({
        key: 'energy-burst',
        width: size,
        height: size,
        backgroundColor: '#020617',
        staticDraw(ctx) {
          ctx.lineWidth = 1;
          ctx.strokeStyle = '#172554';
          ctx.strokeCircle(center, center, 170);
          ctx.strokeStyle = '#1e3a8a';
          ctx.strokeCircle(center, center, 115);
          ctx.strokeStyle = '#4338ca';
          ctx.strokeCircle(center, center, 62);
        },
        draw: drawBurst
      })
    });
  }
});
