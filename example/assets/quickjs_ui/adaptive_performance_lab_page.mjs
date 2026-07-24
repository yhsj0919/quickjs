import {
  animate,
  Canvas,
  Column,
  Container,
  ElevatedButton,
  Page,
  Row,
  SingleChildScrollView,
  SnapshotBoundary,
  Text,
  Wrap
} from 'quickjs_ui';

const counts = [1000, 5000, 10000];

function drawLoad(ctx, count) {
  for (let index = 0; index < count; index += 1) {
    const column = index % 100;
    const row = Math.floor(index / 100);
    const phase = (index % 31) * 11;
    ctx.fillStyle = index % 3 === 0 ? '#22d3ee' : '#6366f1';
    ctx.globalAlpha = 0.35 + (index % 7) * 0.08;
    ctx.fillCircle(
      animate(-4, 344, {
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

function effectCard(index, enabled, run) {
  const duration = 700 + index * 31;
  return Container({
    key: `adaptive-effect-${index}`,
    width: 72,
    height: 54,
    margin: 4,
    decoration: {
      color: index % 2 === 0 ? '#312e81' : '#164e63',
      borderRadius: 12
    },
    opacity: animate(0.55, 1, {
      durationMs: duration,
      repeat: true,
      autoreverse: true,
      phaseMs: run * 17
    }),
    transform: {
      scale: animate(0.92, 1.05, {
        durationMs: duration,
        repeat: true,
        autoreverse: true
      })
    },
    blur: enabled ? 10 : 0,
    backdropBlur: enabled ? 8 : 0,
    colorFilter: enabled
      ? { color: '#18ffffff', blendMode: 'srcIn' }
      : undefined,
    child: Text(`${index + 1}`, {
      textAlign: 'center',
      style: { color: '#ffffff', fontSize: 15 }
    })
  });
}

export default Page({
  name: 'AdaptivePerformanceLabPage',

  createState() {
    return {
      count: 1000,
      expensiveEffects: true,
      run: 0,
      captureToken: 0,
      snapshotId: null
    };
  },

  build(state, props, actions) {
    const snapshotResources = state.snapshotId == null
      ? {}
      : { source: state.snapshotId, target: state.snapshotId };
    return SingleChildScrollView({
      padding: 12,
      child: Column({
        crossAxisAlignment: 'stretch',
        children: [
          Text('Adaptive Performance Lab', {
            style: { color: '#f8fafc', fontSize: 22, fontWeight: 'bold' }
          }),
          Text(
            `${state.count} Canvas primitives · local VSync · no per-frame JS`,
            { style: { color: '#94a3b8', fontSize: 12 } }
          ),
          Row({
            children: counts.map((count) => ElevatedButton({
              key: `count-${count}`,
              onPressed: actions.setCount({ count }),
              child: Text(`${count}`)
            }))
          }),
          Row({
            children: [
              ElevatedButton({
                key: 'toggle-expensive-effects',
                onPressed: actions.toggleEffects(),
                child: Text(state.expensiveEffects ? 'Disable filters' : 'Enable filters')
              }),
              ElevatedButton({
                key: 'restart-adaptive-load',
                onPressed: actions.restart(),
                child: Text('Restart')
              })
            ]
          }),
          Canvas({
            key: 'adaptive-load-canvas',
            width: 340,
            height: 260,
            playToken: state.run,
            staticDraw(ctx) {
              ctx.fillStyle = '#020617';
              ctx.fillRect(0, 0, 340, 260);
            },
            draw(ctx) {
              drawLoad(ctx, state.count);
            }
          }),
          Wrap({
            children: Array.from({ length: 12 }, (_, index) =>
              effectCard(index, state.expensiveEffects, state.run)
            )
          }),
          SnapshotBoundary({
            key: 'adaptive-snapshot-source',
            captureToken: state.captureToken,
            onCaptured: actions.captured(),
            child: Container({
              width: 340,
              height: 90,
              decoration: {
                color: '#0f172a',
                borderColor: '#22d3ee',
                borderWidth: 1,
                borderRadius: 16
              },
              child: Text('SNAPSHOT PARTICLE LOAD', {
                textAlign: 'center',
                style: { color: '#67e8f9', fontSize: 19, fontWeight: 'bold' }
              })
            })
          }),
          Canvas({
            key: 'adaptive-particle-canvas',
            width: 340,
            height: 90,
            resources: snapshotResources,
            playToken: state.run,
            commands: state.snapshotId == null ? [] : [{
              op: 'snapshotParticleGrid',
              sourceSlot: 'source',
              targetSlot: 'target',
              x: 0,
              y: 0,
              width: 340,
              height: 90,
              columns: 32,
              rows: 16,
              bucketCount: 16,
              staggerMs: 12,
              travelMs: 800,
              fadeMs: 620
            }]
          })
        ]
      })
    });
  },

  setCount(state, payload) {
    return { count: payload.count, run: state.run + 1 };
  },

  toggleEffects(state) {
    return { expensiveEffects: !state.expensiveEffects };
  },

  restart(state) {
    return {
      run: state.run + 1,
      captureToken: state.captureToken + 1
    };
  },

  captured(state, payload) {
    return { snapshotId: payload.snapshotId };
  }
});
