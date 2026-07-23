import {
  Column,
  Container,
  ElevatedButton,
  Page,
  Row,
  SingleChildScrollView,
  Switch,
  Text,
  Wrap
} from 'quickjs_ui';

const transition = { durationMs: 180, curve: 'easeOutCubic' };

function countButton(value, current, actions) {
  return ElevatedButton({
    child: Text(`${value}`),
    stateTransition: transition,
    stateStyles: {
      normal: {
        backgroundColor: value === current ? '#0891b2' : '#1e293b',
        foregroundColor: '#ecfeff',
        borderColor: value === current ? '#67e8f9' : '#334155',
        borderWidth: 1,
        borderRadius: 12,
        padding: { horizontal: 14, vertical: 9 }
      },
      hovered: { backgroundColor: '#0e7490', scale: 1.04 },
      pressed: { scale: 0.94 }
    },
    onPressed: actions.setCount({ value })
  });
}

export default Page({
  name: 'ControlMotionStressPage',

  createState() {
    return { count: 10, enabled: true, cycle: 0 };
  },

  setCount(state, data) {
    return { count: data.value };
  },

  toggleEnabled(state) {
    return { enabled: !state.enabled, cycle: state.cycle + 1 };
  },

  build(state, props, actions) {
    const controls = Array.from({ length: state.count }, (_, index) =>
      ElevatedButton({
        key: `stress-control-${index}`,
        child: Text(`CONTROL ${String(index + 1).padStart(2, '0')}`),
        stateTransition: transition,
        stateStyles: {
          normal: {
            backgroundColor: '#155e75',
            foregroundColor: '#ecfeff',
            borderColor: '#22d3ee',
            borderWidth: 1,
            borderRadius: 14,
            elevation: 6,
            opacity: 1,
            scale: 1,
            padding: { horizontal: 16, vertical: 11 }
          },
          hovered: {
            backgroundColor: '#0e7490',
            borderColor: '#67e8f9',
            elevation: 10,
            scale: 1.025
          },
          pressed: { backgroundColor: '#0891b2', elevation: 0, scale: 0.95 },
          disabled: {
            backgroundColor: '#1e293b',
            foregroundColor: '#64748b',
            borderColor: '#334155',
            elevation: 0,
            opacity: 0.6,
            scale: 0.96
          }
        },
        onPressed: state.enabled ? actions.toggleEnabled() : undefined
      })
    );

    return SingleChildScrollView({
      padding: 18,
      children: [
        Container({
          padding: 18,
          decoration: {
            color: '#07111f',
            borderRadius: 24,
            border: { color: '#164e63', width: 1 }
          },
          child: Column({
            crossAxisAlignment: 'stretch',
            gap: 16,
            children: [
              Text('CONTROL MOTION STRESS', {
                style: { color: '#ecfeff', fontSize: 22, fontWeight: 'w800' }
              }),
              Text('同时切换控件状态，直接观察 120Hz / 60Hz 下的响应和连续性。', {
                style: { color: '#94a3b8', fontSize: 13 }
              }),
              Row({
                mainAxisAlignment: 'spaceBetween',
                children: [
                  Text(`${state.count} CONTROLS · CYCLE ${state.cycle}`, {
                    style: { color: '#67e8f9', fontSize: 13, fontWeight: 'w700' }
                  }),
                  Switch({
                    value: state.enabled,
                    onChanged: actions.toggleEnabled(),
                    stateTransition: transition,
                    stateStyles: {
                      normal: { scale: 1 },
                      hovered: { scale: 1.06 },
                      pressed: { scale: 0.92 }
                    },
                    thumbStyle: {
                      normal: { color: '#94a3b8' },
                      selected: { color: '#ecfeff' }
                    },
                    trackStyle: {
                      normal: { color: '#334155' },
                      selected: { color: '#0891b2' }
                    }
                  })
                ]
              }),
              Wrap({
                spacing: 8,
                runSpacing: 8,
                children: [
                  countButton(1, state.count, actions),
                  countButton(10, state.count, actions),
                  countButton(40, state.count, actions)
                ]
              }),
              ElevatedButton({
                child: Text(state.enabled ? '触发全部禁用动画' : '触发全部恢复动画'),
                stateTransition: transition,
                stateStyles: {
                  normal: {
                    backgroundColor: '#7c3aed',
                    foregroundColor: '#ffffff',
                    borderRadius: 14,
                    padding: { horizontal: 18, vertical: 13 }
                  },
                  hovered: { backgroundColor: '#8b5cf6', scale: 1.02 },
                  pressed: { backgroundColor: '#6d28d9', scale: 0.96 }
                },
                onPressed: actions.toggleEnabled()
              }),
              Wrap({ spacing: 8, runSpacing: 8, children: controls })
            ]
          })
        })
      ]
    });
  }
});
