import { animate, Canvas, Center, Page } from 'quickjs_ui';

const width = 360;
const height = 540;

function drift(from, to, durationMs, phaseMs) {
  return animate(from, to, {
    durationMs,
    phaseMs,
    repeat: true,
    autoreverse: true,
    curve: 'easeInOut'
  });
}

function drawFireflies(ctx) {
  const colors = ['#fef08a', '#bef264', '#86efac', '#67e8f9'];
  for (let index = 0; index < 260; index += 1) {
    const baseX = 15 + ((index * 83) % 330);
    const baseY = 20 + ((index * 149) % 500);
    const rangeX = 12 + (index % 9) * 4;
    const rangeY = 18 + (index % 11) * 3;
    ctx.fillStyle = colors[index % colors.length];
    ctx.globalAlpha = 0.35 + (index % 8) * 0.08;
    ctx.globalCompositeOperation = 'plus';
    ctx.fillCircle(
      drift(baseX - rangeX, baseX + rangeX, 1800 + (index % 13) * 170, index * 37),
      drift(baseY - rangeY, baseY + rangeY, 2200 + (index % 17) * 140, index * 61),
      drift(0.7, 2.6 + (index % 4) * 0.4, 700 + (index % 8) * 90, index * 29)
    );
  }
}

export default Page({
  createState() { return {}; },
  build() {
    return Center({
      child: Canvas({
        key: 'firefly-garden',
        width,
        height,
        backgroundColor: '#03120d',
        staticDraw(ctx) {
          ctx.fillStyle = '#052e16';
          ctx.fillCircle(70, 430, 130);
          ctx.fillStyle = '#064e3b';
          ctx.fillCircle(300, 470, 150);
          ctx.fillStyle = '#14532d';
          ctx.fillCircle(190, 590, 220);
        },
        draw: drawFireflies
      })
    });
  }
});
