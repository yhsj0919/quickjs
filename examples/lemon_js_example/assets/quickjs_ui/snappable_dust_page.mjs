import {
  Canvas,
  Center,
  Column,
  Container,
  GestureDetector,
  Page,
  Positioned,
  SnapshotBoundary,
  Stack,
  Text
} from 'quickjs_ui';

const width = 360;
const height = 500;
const card = { x: 38, y: 120, width: 284, height: 220 };
const columns = 24;
const rows = 18;
const bucketCount = 16;
const staggerMs = 16;
const travelMs = 920;
const fadeMs = 760;
const sceneKey = 'snapshot-particle-transition';
let scenePublished = false;

function hash(value) {
  const result = Math.sin(value * 91.3458) * 47453.5453;
  return result - Math.floor(result);
}

function drawBackdrop(ctx) {
  ctx.clear('#020617');
  for (let index = 0; index < 52; index += 1) {
    ctx.fillStyle = index % 3 === 0 ? '#6366f1' : '#334155';
    ctx.globalAlpha = 0.18 + hash(index + 900) * 0.28;
    ctx.fillCircle(
      12 + hash(index + 300) * 336,
      20 + hash(index + 600) * 430,
      0.8 + hash(index + 1200) * 1.4
    );
  }
  ctx.globalAlpha = 1;
  ctx.fillStyle = '#e2e8f0';
  ctx.font = '22px sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('SNAPSHOT PARTICLE TRANSITION', width / 2, 48);
  ctx.fillStyle = '#64748b';
  ctx.font = '12px sans-serif';
  ctx.fillText('One retained scene · two Flutter snapshots', width / 2, 76);
}

function drawParticleTransition(ctx) {
  ctx.drawSnapshotParticleGrid({
    sourceSlot: 'source',
    targetSlot: 'target',
    x: card.x,
    y: card.y,
    width: card.width,
    height: card.height,
    columns,
    rows,
    bucketCount,
    staggerMs,
    travelMs,
    fadeMs
  });
}

function cardView(variant) {
  if (variant === 1) {
    return Container({
      width: card.width,
      height: card.height,
      padding: { horizontal: 26, vertical: 22 },
      decoration: {
        color: '#0f766e',
        borderRadius: 24,
        border: { color: '#5eead4', width: 1 }
      },
      child: Column({
        crossAxisAlignment: 'start',
        gap: 11,
        children: [
          Text('SYSTEM MATRIX', {
            style: { color: '#ffffff', fontSize: 24, fontWeight: 'w800' }
          }),
          Text('LIVE FLUTTER CONTROL', {
            style: { color: '#99f6e4', fontSize: 13, fontWeight: 'w600' }
          }),
          Container({
            height: 12,
            margin: { top: 10 },
            decoration: { color: '#14b8a6', borderRadius: 6 }
          }),
          Container({
            width: 178,
            height: 12,
            decoration: { color: '#2dd4bf', borderRadius: 6 }
          }),
          Container({
            width: 116,
            height: 12,
            decoration: { color: '#5eead4', borderRadius: 6 }
          }),
          Text('STATUS  98.6%', {
            style: { color: '#ccfbf1', fontSize: 13, fontWeight: 'w700' }
          })
        ]
      })
    });
  }

  return Container({
    width: card.width,
    height: card.height,
    padding: { horizontal: 26, vertical: 24 },
    decoration: {
      color: '#4f46e5',
      borderRadius: 24,
      border: { color: '#818cf8', width: 1 }
    },
    child: Column({
      crossAxisAlignment: 'start',
      gap: 11,
      children: [
        Text('QUICKJS', {
          style: { color: '#ffffff', fontSize: 25, fontWeight: 'w800' }
        }),
        Text('SNAPPABLE FLUTTER WIDGET', {
          style: { color: '#c7d2fe', fontSize: 13, fontWeight: 'w600' }
        }),
        Container({
          height: 2,
          margin: { vertical: 7 },
          decoration: { color: '#818cf8', borderRadius: 1 }
        }),
        Text('This is a real Flutter widget tree.', {
          style: { color: '#ffffff', fontSize: 15 }
        }),
        Text('Its pixels are bound through a scene image slot.', {
          style: { color: '#c7d2fe', fontSize: 12 }
        })
      ]
    })
  });
}

function capturedCard(role, variant, captureToken, actions) {
  return SnapshotBoundary({
    key: `transition-${role}`,
    snapshotKey: `transition-${role}`,
    captureToken,
    pixelRatio: 1,
    onCaptured: actions.captured({ role, variant }),
    onCaptureError: actions.captureFailed({ role }),
    child: cardView(variant)
  });
}

function desiredTarget(state) {
  return state.transitionType === 'same'
    ? state.currentVariant
    : 1 - state.currentVariant;
}

export default Page({
  name: 'SnappableDustPage',

  createState() {
    return {
      mode: 'visible',
      currentVariant: 0,
      transitionType: 'same',
      sourceSnapshot: null,
      sourceVariant: null,
      targetSnapshot: null,
      targetVariant: null,
      activeSource: null,
      activeTarget: null,
      captureToken: null,
      run: 0,
      error: null
    };
  },

  captured(state, data) {
    let patch;
    if (data.role === 'source' && data.variant === state.currentVariant) {
      patch = {
        sourceSnapshot: data.snapshotId,
        sourceVariant: data.variant,
        error: null
      };
    } else if (
      data.role === 'target' &&
      data.variant === desiredTarget(state)
    ) {
      patch = {
        targetSnapshot: data.snapshotId,
        targetVariant: data.variant,
        error: null
      };
    } else {
      return null;
    }

    const sourceSnapshot = patch.sourceSnapshot ?? state.sourceSnapshot;
    const sourceVariant = patch.sourceVariant ?? state.sourceVariant;
    const targetSnapshot = patch.targetSnapshot ?? state.targetSnapshot;
    const targetVariant = patch.targetVariant ?? state.targetVariant;
    if (
      state.mode === 'preparing' &&
      sourceSnapshot != null &&
      targetSnapshot != null &&
      sourceVariant === state.currentVariant &&
      targetVariant === desiredTarget(state)
    ) {
      return {
        ...patch,
        mode: 'transitioning',
        activeSource: sourceSnapshot,
        activeTarget: targetSnapshot,
        run: state.run + 1
      };
    }
    return patch;
  },

  captureFailed(state, data) {
    return {
      mode: 'visible',
      captureToken: null,
      error: `${data.role}: ${data.message ?? 'Snapshot failed'}`
    };
  },

  startTransition(state) {
    if (state.mode !== 'visible') return null;
    return {
      mode: 'preparing',
      sourceSnapshot: null,
      sourceVariant: null,
      targetSnapshot: null,
      targetVariant: null,
      activeSource: null,
      activeTarget: null,
      captureToken: state.captureToken == null ? 0 : state.captureToken + 1,
      error: null
    };
  },

  finishTransition(state, data) {
    if (state.mode !== 'transitioning' || state.run !== data.run) return null;
    return {
      mode: 'visible',
      currentVariant: state.transitionType === 'different'
        ? state.targetVariant
        : state.currentVariant,
      transitionType: state.transitionType === 'same' ? 'different' : 'same',
      sourceSnapshot: null,
      sourceVariant: null,
      targetSnapshot: null,
      targetVariant: null,
      activeSource: null,
      activeTarget: null,
      captureToken: state.captureToken
    };
  },

  build(state, props, actions) {
    const publishScene = state.mode === 'transitioning' && !scenePublished;
    if (publishScene) scenePublished = true;
    const targetVariant = desiredTarget(state);
    const ready = state.mode !== 'preparing';
    const resources = {};
    if (state.activeSource != null) resources.source = state.activeSource;
    if (state.activeTarget != null) resources.target = state.activeTarget;

    const children = [
      Canvas({
        key: 'snapshot-particle-canvas',
        width,
        height,
        backgroundColor: '#020617',
        resources,
        paused: state.mode !== 'transitioning',
        playToken: state.run,
        ...(scenePublished
          ? {
              sceneKey,
              ...(publishScene
                  ? {
                    staticDraw: drawBackdrop,
                    draw: drawParticleTransition
                  }
                : {})
            }
          : {
              commands: [],
              staticDraw: drawBackdrop
            }),
        ...(state.mode === 'transitioning'
          ? {
              onAnimationEnd: actions.finishTransition({ run: state.run })
            }
          : {}),
        willChange: state.mode === 'transitioning'
      })
    ];

    if (state.mode === 'preparing') {
      children.push(Positioned({
        left: card.x,
        top: card.y,
        width: card.width,
        height: card.height,
        child: capturedCard(
          'target',
          targetVariant,
          state.captureToken,
          actions
        )
      }));
      children.push(Positioned({
        left: card.x,
        top: card.y,
        width: card.width,
        height: card.height,
        child: capturedCard(
          'source',
          state.currentVariant,
          state.captureToken,
          actions
        )
      }));
    } else if (state.mode === 'visible') {
      children.push(Positioned({
        left: card.x,
        top: card.y,
        width: card.width,
        height: card.height,
        child: cardView(state.currentVariant)
      }));
    }

    children.push(Positioned({
      left: 36,
      top: 382,
      width: 288,
      child: Container({
        padding: { horizontal: 16, vertical: 13 },
        decoration: {
          color: '#172033',
          borderRadius: 18,
          border: { color: ready ? '#334155' : '#7c2d12', width: 1 }
        },
        child: Text(
          state.error ??
            (ready
              ? state.transitionType === 'same'
                ? '点击：同控件分解并重构'
                : '点击：分解并重构为不同控件'
              : '正在准备源画面与目标画面…'),
          {
            textAlign: 'center',
            style: {
              color: state.error == null ? '#cbd5e1' : '#fb7185',
              fontSize: 13,
              fontWeight: 'w600'
            }
          }
        )
      })
    }));

    return Center({
      child: GestureDetector({
        onTap: actions.startTransition(),
        child: Stack({ width, height, children })
      })
    });
  }
});
