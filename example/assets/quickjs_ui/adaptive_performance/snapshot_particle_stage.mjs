import {
  Canvas,
  Container,
  SnapshotBoundary,
  Stack,
  Text
} from 'quickjs_ui';

const width = 340;
const height = 90;

function sourceCard(state, actions) {
  return SnapshotBoundary({
    key: 'adaptive-snapshot-source',
    captureToken: state.captureToken,
    onCaptured: actions.captured(),
    child: Container({
      width,
      height,
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
  });
}

function particleCanvas(state, actions) {
  return Canvas({
    key: 'adaptive-particle-canvas',
    width,
    height,
    resources: {
      source: state.snapshotId,
      target: state.snapshotId
    },
    playToken: state.run,
    ...(state.snapshotPhase === 'animating'
      ? { onAnimationEnd: actions.particlesFinished({ run: state.run }) }
      : {}),
    commands: [{
      op: 'snapshotParticleGrid',
      sourceSlot: 'source',
      targetSlot: 'target',
      x: 0,
      y: 0,
      width,
      height,
      columns: 32,
      rows: 16,
      bucketCount: 16,
      direction: 'create',
      staggerMs: 12,
      travelMs: 800,
      fadeMs: 620
    }]
  });
}

export function snapshotParticleStage(state, actions) {
  const showSource = state.snapshotPhase === 'source' || state.snapshotId == null;
  return Stack({
    clipBehavior: 'hardEdge',
    children: [
      showSource ? sourceCard(state, actions) : particleCanvas(state, actions)
    ]
  });
}
