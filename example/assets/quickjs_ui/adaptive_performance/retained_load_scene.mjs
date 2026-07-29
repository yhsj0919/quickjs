import { animate, Canvas } from 'quickjs_ui';

export function createRetainedLoadScene({
  sceneKey,
  width,
  height,
  columns = 100
}) {
  let submittedRevision = null;

  function drawLoad(ctx, count) {
    for (let index = 0; index < count; index += 1) {
      const column = index % columns;
      const row = Math.floor(index / columns);
      const phase = (index % 31) * 11;
      ctx.fillStyle = index % 3 === 0 ? '#22d3ee' : '#6366f1';
      ctx.globalAlpha = 0.35 + (index % 7) * 0.08;
      ctx.fillCircle(
        animate(-4, width + 4, {
          durationMs: 900 + (index % 23) * 37,
          phaseMs: phase,
          repeat: true
        }),
        8 + (row % 75) * 3.25 + (column % 3),
        0.7 + (index % 4) * 0.25
      );
    }
    ctx.globalAlpha = 1;
  }

  return Object.freeze({
    build({ count, revision }) {
      const shouldSubmit = submittedRevision !== revision;
      submittedRevision = revision;
      return Canvas({
        key: `${sceneKey}-canvas`,
        sceneKey,
        width,
        height,
        playToken: revision,
        ...(shouldSubmit ? {
          staticDraw(ctx) {
            ctx.fillStyle = '#020617';
            ctx.fillRect(0, 0, width, height);
          },
          draw(ctx) {
            drawLoad(ctx, count);
          }
        } : {})
      });
    }
  });
}
