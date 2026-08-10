import { animate, Canvas, Center, Page } from 'quickjs_ui';

const size = 300;
const center = size / 2;
const radius = 132;

function hand(ctx, angle, length, width, color, tail = 0) {
  ctx.save();
  ctx.translate(center, center);
  ctx.rotate(angle);
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.lineCap = 'round';
  ctx.drawLine(0, tail, 0, -length);
  ctx.restore();
}

function drawDial(ctx) {
  ctx.clear('#f8fafc');
  ctx.fillStyle = '#ffffff';
  ctx.fillCircle(center, center, radius);
  ctx.strokeStyle = '#172033';
  ctx.lineWidth = 5;
  ctx.strokeCircle(center, center, radius);
  for (let index = 0; index < 60; index += 1) {
    const angle = index * Math.PI / 30;
    const major = index % 5 === 0;
    const outer = radius - 10;
    const inner = outer - (major ? 15 : 7);
    ctx.strokeStyle = major ? '#172033' : '#94a3b8';
    ctx.lineWidth = major ? 3 : 1;
    ctx.drawLine(
      center + Math.sin(angle) * inner,
      center - Math.cos(angle) * inner,
      center + Math.sin(angle) * outer,
      center - Math.cos(angle) * outer
    );
  }
}

function drawHands(ctx) {
  const timezonePhaseMs = -new Date().getTimezoneOffset() * 60 * 1000;
  const rotation = (durationMs, phaseMs = 0) => animate(0, Math.PI * 2, {
    durationMs,
    phaseMs,
    repeat: true,
    timeSource: 'epoch'
  });
  hand(ctx, rotation(12 * 60 * 60 * 1000, timezonePhaseMs), 68, 7, '#172033');
  hand(ctx, rotation(60 * 60 * 1000), 96, 5, '#334155');
  hand(ctx, rotation(60 * 1000), 108, 2, '#e53935', 20);
  ctx.fillStyle = '#e53935';
  ctx.fillCircle(center, center, 6);
}

export default Page({
  name: 'CanvasClockPage',

  createState() {
    return {};
  },

  build() {
    return Center({
      child: Canvas({
        key: 'clock',
        width: size,
        height: size,
        staticDraw: drawDial,
        draw: drawHands,
        willChange: true
      })
    });
  }
});
