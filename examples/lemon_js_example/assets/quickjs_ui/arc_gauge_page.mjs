import { Canvas, Center, Page } from 'quickjs_ui';

const width = 360;
const height = 430;
const centerX = width / 2;
const centerY = 190;
const radius = 126;
const startAngle = Math.PI * 0.75;
const sweepAngle = Math.PI * 1.5;
const endAngle = startAngle + sweepAngle;
const segmentCount = 54;

function pointAt(angle, distance) {
  return {
    x: centerX + Math.cos(angle) * distance,
    y: centerY + Math.sin(angle) * distance
  };
}

function strokeArc(ctx, radiusValue, from, to, color, widthValue, alpha = 1) {
  ctx.beginPath();
  ctx.arc(centerX, centerY, radiusValue, from, to);
  ctx.strokeStyle = color;
  ctx.lineWidth = widthValue;
  ctx.lineCap = 'round';
  ctx.globalAlpha = alpha;
  ctx.stroke();
  ctx.globalAlpha = 1;
}

function segmentColor(progress) {
  if (progress < 0.34) return '#22d3ee';
  if (progress < 0.68) return '#6366f1';
  if (progress < 0.86) return '#a855f7';
  return '#f43f5e';
}

function drawStaticGauge(ctx) {
  ctx.clear('#020617');

  ctx.fillStyle = '#071126';
  ctx.fillCircle(centerX, centerY, 153);
  ctx.strokeStyle = '#13213d';
  ctx.lineWidth = 1;
  ctx.strokeCircle(centerX, centerY, 153);
  ctx.strokeCircle(centerX, centerY, 105);

  strokeArc(ctx, radius, startAngle, endAngle, '#16243f', 18);

  for (let index = 0; index <= 27; index += 1) {
    const progress = index / 27;
    const angle = startAngle + sweepAngle * progress;
    const major = index % 3 === 0;
    const inner = pointAt(angle, major ? 100 : 106);
    const outer = pointAt(angle, 114);
    ctx.strokeStyle = major ? '#94a3b8' : '#334155';
    ctx.lineWidth = major ? 2 : 1;
    ctx.lineCap = 'round';
    ctx.drawLine(inner.x, inner.y, outer.x, outer.y);
  }

  ctx.fillStyle = '#64748b';
  ctx.font = '13px sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  const zero = pointAt(startAngle, 164);
  const middle = pointAt(startAngle + sweepAngle / 2, 164);
  const full = pointAt(endAngle, 164);
  ctx.fillText('0', zero.x, zero.y);
  ctx.fillText('50', middle.x, middle.y);
  ctx.fillText('100', full.x, full.y);

  ctx.fillStyle = '#1e293b';
  ctx.fillRect(52, 376, 256, 38, 19);
  ctx.fillStyle = '#94a3b8';
  ctx.font = '13px sans-serif';
  ctx.fillText('拖动仪表盘调节功率', centerX, 395);
}

function drawValue(ctx, value, dragging) {
  const progress = value / 100;
  const activeSegments = Math.round(segmentCount * progress);
  const segmentSweep = sweepAngle / segmentCount;

  for (let index = 0; index < activeSegments; index += 1) {
    const segmentProgress = index / (segmentCount - 1);
    const from = startAngle + index * segmentSweep + 0.012;
    const to = startAngle + (index + 1) * segmentSweep - 0.012;
    const color = segmentColor(segmentProgress);
    strokeArc(ctx, radius, from, to, color, 24, 0.12);
    strokeArc(ctx, radius, from, to, color, 13, 1);
  }

  const needleAngle = startAngle + sweepAngle * progress;
  const needleTip = pointAt(needleAngle, 94);
  const needleTail = pointAt(needleAngle + Math.PI, 20);
  ctx.strokeStyle = segmentColor(progress);
  ctx.lineWidth = 5;
  ctx.lineCap = 'round';
  ctx.globalCompositeOperation = 'plus';
  ctx.globalAlpha = 0.25;
  ctx.drawLine(needleTail.x, needleTail.y, needleTip.x, needleTip.y);
  ctx.lineWidth = 2;
  ctx.globalAlpha = 1;
  ctx.drawLine(needleTail.x, needleTail.y, needleTip.x, needleTip.y);
  ctx.globalCompositeOperation = 'srcOver';

  ctx.fillStyle = '#0f172a';
  ctx.fillCircle(centerX, centerY, 15);
  ctx.fillStyle = segmentColor(progress);
  ctx.fillCircle(centerX, centerY, dragging ? 10 : 8);
  ctx.fillStyle = '#ffffff';
  ctx.fillCircle(centerX, centerY, 3);

  ctx.fillStyle = '#f8fafc';
  ctx.font = '52px sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(String(value), centerX, 284);
  ctx.fillStyle = segmentColor(progress);
  ctx.font = '14px sans-serif';
  ctx.fillText('%  POWER', centerX, 326);

  ctx.fillStyle = dragging ? '#22d3ee' : '#475569';
  ctx.fillRect(134, 347, 92, 3, 2);
}

function valueFromPointer(x, y) {
  let angle = Math.atan2(y - centerY, x - centerX);
  if (angle < 0) angle += Math.PI * 2;

  if (angle < startAngle) {
    if (angle <= Math.PI * 0.25) {
      angle += Math.PI * 2;
    } else {
      angle = angle < Math.PI * 0.5 ? endAngle : startAngle;
    }
  }

  const progress = Math.max(0, Math.min(1, (angle - startAngle) / sweepAngle));
  return Math.round(progress * 100);
}

function pointerValue(data) {
  return valueFromPointer(Number(data.x), Number(data.y));
}

export default Page({
  name: 'ArcGaugePage',

  createState() {
    return { value: 72, dragging: false };
  },

  beginGauge(state, data) {
    return { value: pointerValue(data), dragging: true };
  },

  dragGauge(state, data) {
    if (!state.dragging) return null;
    return { value: pointerValue(data) };
  },

  endGauge(state, data) {
    return { value: pointerValue(data), dragging: false };
  },

  cancelGauge() {
    return { dragging: false };
  },

  build(state, props, actions) {
    return Center({
      child: Canvas({
        key: 'arc-gauge',
        width,
        height,
        backgroundColor: '#020617',
        staticDraw: drawStaticGauge,
        draw(ctx) {
          drawValue(ctx, state.value, state.dragging);
        },
        onPointerDown: actions.beginGauge(),
        onPointerMove: actions.dragGauge(),
        onPointerUp: actions.endGauge(),
        onPointerCancel: actions.cancelGauge(),
        semanticsLabel: `功率 ${state.value}%`,
        willChange: true
      })
    });
  }
});
