import {
  Canvas, Center, Column, Container, Page, Stack, Text, animate
} from 'quickjs_ui';

const DAYS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const TEMPERATURES = [21, 24, 23, 28, 26, 30, 27];
const CHART_HEIGHT = 360;
const PADDING = Object.freeze({ left: 48, top: 38, right: 28, bottom: 48 });
const MIN_TEMP = 18;
const MAX_TEMP = 32;

function chartWidth(props) {
  return Math.max(320, Math.min(920, Number(props.width || 720) - 40));
}

function pointAt(index, width) {
  const plotWidth = width - PADDING.left - PADDING.right;
  const plotHeight = CHART_HEIGHT - PADDING.top - PADDING.bottom;
  return {
    x: PADDING.left + plotWidth * index / (TEMPERATURES.length - 1),
    y: PADDING.top + (MAX_TEMP - TEMPERATURES[index]) /
      (MAX_TEMP - MIN_TEMP) * plotHeight
  };
}

function drawGrid(ctx, width) {
  ctx.clear('#f8fafc');
  ctx.font = '13px system-ui';
  ctx.fillStyle = '#64748b';
  ctx.strokeStyle = '#cbd5e1';
  ctx.lineWidth = 1;
  ctx.setLineDash([5, 6]);
  for (const temperature of [20, 24, 28, 32]) {
    const plotHeight = CHART_HEIGHT - PADDING.top - PADDING.bottom;
    const y = PADDING.top + (MAX_TEMP - temperature) /
      (MAX_TEMP - MIN_TEMP) * plotHeight;
    ctx.drawLine(PADDING.left, y, width - PADDING.right, y);
    ctx.fillText(`${temperature}°`, 10, y + 4);
  }
  ctx.setLineDash([]);
  for (let index = 0; index < DAYS.length; index += 1) {
    const point = pointAt(index, width);
    const metrics = ctx.measureText(DAYS[index]);
    ctx.fillText(DAYS[index], point.x - metrics.width / 2, CHART_HEIGHT - 18);
  }
}

function tracePath(ctx, width) {
  ctx.beginPath();
  const first = pointAt(0, width);
  ctx.moveTo(first.x, first.y);
  for (let index = 1; index < TEMPERATURES.length; index += 1) {
    const previous = pointAt(index - 1, width);
    const current = pointAt(index, width);
    const middle = (previous.x + current.x) / 2;
    ctx.bezierCurveTo(middle, previous.y, middle, current.y, current.x, current.y);
  }
}

function drawChart(ctx, width) {
  ctx.save();
  ctx.clipProgress(animate(0, 1, { durationMs: 1200, curve: 'easeOut' }));
  tracePath(ctx, width);
  const last = pointAt(TEMPERATURES.length - 1, width);
  const first = pointAt(0, width);
  ctx.lineTo(last.x, CHART_HEIGHT - PADDING.bottom);
  ctx.lineTo(first.x, CHART_HEIGHT - PADDING.bottom);
  ctx.closePath();
  const area = ctx.createLinearGradient(0, PADDING.top, 0, CHART_HEIGHT);
  area.addColorStop(0, '#8838bdf8');
  area.addColorStop(1, '#0038bdf8');
  ctx.fillStyle = area;
  ctx.fill();

  tracePath(ctx, width);
  const line = ctx.createLinearGradient(PADDING.left, 0, width - PADDING.right, 0);
  line.addColorStop(0, '#0284c7');
  line.addColorStop(0.55, '#2563eb');
  line.addColorStop(1, '#7c3aed');
  ctx.strokeStyle = line;
  ctx.lineWidth = 4;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.stroke();

  for (let index = 0; index < TEMPERATURES.length; index += 1) {
    const point = pointAt(index, width);
    const glow = ctx.createRadialGradient(
      point.x, point.y, 1, point.x, point.y, 8
    );
    glow.addColorStop(0, '#ffffff');
    glow.addColorStop(0.45, '#38bdf8');
    glow.addColorStop(1, '#0038bdf8');
    ctx.fillStyle = glow;
    ctx.fillCircle(point.x, point.y, 8);
  }
  ctx.restore();
}

function drawHover(ctx, width, hoverIndex) {
  if (hoverIndex < 0) return;
  const point = pointAt(hoverIndex, width);
  ctx.strokeStyle = '#64748b';
  ctx.lineWidth = 1;
  ctx.setLineDash([4, 5]);
  ctx.drawLine(point.x, PADDING.top, point.x, CHART_HEIGHT - PADDING.bottom);
  ctx.setLineDash([]);
  ctx.fillStyle = '#ffffff';
  ctx.fillCircle(point.x, point.y, 6);
  ctx.strokeStyle = '#2563eb';
  ctx.lineWidth = 3;
  ctx.strokeCircle(point.x, point.y, 6);

  const label = `${DAYS[hoverIndex]}  ${TEMPERATURES[hoverIndex]}°C`;
  ctx.font = '14px system-ui';
  const tooltipWidth = ctx.measureText(label).width + 24;
  const tooltipX = Math.max(
    8,
    Math.min(width - tooltipWidth - 8, point.x - tooltipWidth / 2)
  );
  const tooltipY = Math.max(8, point.y - 54);
  const tooltip = ctx.createLinearGradient(
    tooltipX, tooltipY, tooltipX + tooltipWidth, tooltipY
  );
  tooltip.addColorStop(0, '#0f172a');
  tooltip.addColorStop(1, '#334155');
  ctx.fillStyle = tooltip;
  ctx.fillRect(tooltipX, tooltipY, tooltipWidth, 36, 10);
  ctx.fillStyle = '#ffffff';
  ctx.fillText(label, tooltipX + 12, tooltipY + 23);
}

export default Page({
  name: 'TemperatureChartPage',
  createState() { return { hoverIndex: -1 }; },
  hoverPoint(state, data, props) {
    const width = chartWidth(props);
    const x = Number(data.localX ?? data.x);
    if (!Number.isFinite(x) || x < PADDING.left || x > width - PADDING.right) {
      return state.hoverIndex === -1 ? null : { hoverIndex: -1 };
    }
    const plotWidth = width - PADDING.left - PADDING.right;
    const index = Math.max(0, Math.min(
      TEMPERATURES.length - 1,
      Math.round((x - PADDING.left) / plotWidth * (TEMPERATURES.length - 1))
    ));
    return index === state.hoverIndex ? null : { hoverIndex: index };
  },
  clearHover(state) {
    return state.hoverIndex === -1 ? null : { hoverIndex: -1 };
  },
  build(state, props, actions) {
    const width = chartWidth(props);
    return Center({
      child: Column({
        gap: 12,
        children: [
          Text('一周温度趋势', {
            style: { fontSize: 24, fontWeight: 'w800', color: '#0f172a' }
          }),
          Text('移动鼠标查看每天温度', {
            style: { fontSize: 13, color: '#64748b' }
          }),
          Container({
            width,
            height: CHART_HEIGHT,
            clipRadius: 20,
            decoration: {
              color: '#f8fafc',
              borderRadius: 20,
              border: { color: '#cbd5e1', width: 1 },
              boxShadow: {
                color: '#220f172a',
                offset: { x: 0, y: 10 },
                blurRadius: 24
              }
            },
            child: Stack({
              children: [
                Canvas({
                  key: 'temperature-chart',
                  width,
                  height: CHART_HEIGHT,
                  staticDraw(ctx) { drawGrid(ctx, width); },
                  draw(ctx) { drawChart(ctx, width); },
                  willChange: true
                }),
                Canvas({
                  key: 'temperature-chart-pointer',
                  width,
                  height: CHART_HEIGHT,
                  onMouseHover: {
                    method: 'hoverPoint',
                    throttleMs: 16
                  },
                  onMouseExit: actions.clearHover(),
                  mouseCursor: 'basic',
                  draw(ctx) { drawHover(ctx, width, state.hoverIndex); }
                })
              ]
            })
          })
        ]
      })
    });
  }
});
