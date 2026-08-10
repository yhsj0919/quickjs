import { animate, Canvas, Center, Page } from 'quickjs_ui';

const size = 360;
const center = size / 2;

function rotation(durationMs, phaseMs, reverse) {
  return animate(reverse ? Math.PI * 2 : 0, reverse ? 0 : Math.PI * 2, {
    durationMs,
    phaseMs,
    repeat: true
  });
}

function drawGalaxy(ctx) {
  const colors = ['#22d3ee', '#818cf8', '#c084fc', '#f472b6', '#ffffff'];
  for (let index = 0; index < 300; index += 1) {
    const arm = index % 5;
    const radius = 18 + ((index * 47) % 145);
    const angle = arm * Math.PI * 0.4 + radius * 0.055;
    const duration = 5000 + radius * 38;
    ctx.save();
    ctx.translate(center, center);
    ctx.rotate(angle);
    ctx.rotate(rotation(duration, index * 43, arm === 4));
    ctx.translate(radius, ((index * 29) % 17) - 8);
    ctx.fillStyle = colors[index % colors.length];
    ctx.globalAlpha = 0.42 + (index % 9) * 0.06;
    ctx.globalCompositeOperation = 'plus';
    ctx.fillCircle(0, 0, 0.8 + (index % 7) * 0.23);
    ctx.restore();
  }
  ctx.fillStyle = '#ffffff';
  ctx.globalAlpha = 0.95;
  ctx.globalCompositeOperation = 'plus';
  ctx.fillCircle(center, center, 13);
  ctx.fillStyle = '#7c3aed';
  ctx.globalAlpha = 0.28;
  ctx.fillCircle(center, center, 25);
}

export default Page({
  createState() { return {}; },
  build() {
    return Center({
      child: Canvas({
        key: 'neon-galaxy',
        width: size,
        height: size,
        backgroundColor: '#020617',
        staticDraw(ctx) {
          ctx.lineWidth = 1;
          ctx.strokeStyle = '#172554';
          ctx.strokeCircle(center, center, 165);
          ctx.strokeStyle = '#312e81';
          ctx.strokeCircle(center, center, 110);
          ctx.strokeStyle = '#581c87';
          ctx.strokeCircle(center, center, 58);
        },
        draw: drawGalaxy
      })
    });
  }
});
