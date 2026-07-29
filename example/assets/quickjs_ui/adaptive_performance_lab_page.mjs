import {
  animate,
  Column,
  Container,
  ElevatedButton,
  Page,
  Row,
  SingleChildScrollView,
  Text,
  Wrap
} from 'quickjs_ui';
import { createRetainedLoadScene } from './adaptive_performance/retained_load_scene.mjs';
import { snapshotParticleStage } from './adaptive_performance/snapshot_particle_stage.mjs';

const counts = [1000, 5000, 10000];
const loadScene = createRetainedLoadScene({
  sceneKey: 'adaptive-load',
  width: 340,
  height: 260
});

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
      snapshotId: null,
      snapshotPhase: 'source'
    };
  },

  build(state, props, actions) {
    return SingleChildScrollView({
      padding: 12,
      child: Column({
        crossAxisAlignment: 'start',
        gap: 8,
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
          loadScene.build({ count: state.count, revision: state.run }),
          Wrap({
            children: Array.from({ length: 12 }, (_, index) =>
              effectCard(index, state.expensiveEffects, state.run)
            )
          }),
          snapshotParticleStage(state, actions)
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
      captureToken: state.captureToken + 1,
      snapshotPhase: 'source'
    };
  },

  captured(state, payload) {
    if (state.snapshotPhase !== 'source') return null;
    return { snapshotId: payload.snapshotId, snapshotPhase: 'animating' };
  },

  particlesFinished(state, payload) {
    if (state.snapshotPhase !== 'animating' || payload.run !== state.run) {
      return null;
    }
    return { snapshotPhase: 'settled' };
  }
});
