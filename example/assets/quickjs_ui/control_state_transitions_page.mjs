import {
  Column,
  Container,
  ElevatedButton,
  Icon,
  Page,
  Row,
  SingleChildScrollView,
  Slider,
  Switch,
  Text,
  TextField
} from 'quickjs_ui';

const transition = { durationMs: 180, curve: 'easeOutCubic' };

export default Page({
  name: 'ControlStateTransitionsPage',

  createState() {
    return { armed: true, intensity: 72, callsign: 'NOVA', launches: 0 };
  },

  launch(state) {
    return { launches: state.launches + 1 };
  },

  setArmed(state, data) {
    return { armed: data.value };
  },

  setIntensity(state, data) {
    return { intensity: data.value };
  },

  setCallsign(state, data) {
    return { callsign: data.value };
  },

  build(state, props, actions) {
    return SingleChildScrollView({
      padding: 20,
      children: [
        Container({
          padding: 22,
          decoration: {
            color: '#07111f',
            borderRadius: 28,
            border: { color: '#164e63', width: 1 }
          },
          child: Column({
            crossAxisAlignment: 'stretch',
            gap: 20,
            children: [
              Text('STATE MOTION LAB', {
                style: {
                  color: '#ecfeff',
                  fontSize: 24,
                  fontWeight: 'w800'
                }
              }),
              Text('悬停、按压、聚焦和禁用状态均由 Flutter VSync 本地插值', {
                style: { color: '#94a3b8', fontSize: 13 }
              }),
              ElevatedButton({
                leading: Icon({ icon: 'bolt', color: '#a5f3fc' }),
                child: Text(
                  state.launches === 0
                    ? '启动能量核心'
                    : `再次启动 · ${state.launches}`
                ),
                trailing: Icon({ icon: 'arrow_forward', size: 18 }),
                gap: 10,
                stateTransition: transition,
                stateStyles: {
                  normal: {
                    backgroundColor: '#155e75',
                    foregroundColor: '#ecfeff',
                    borderColor: '#22d3ee',
                    borderWidth: 1,
                    borderRadius: 17,
                    elevation: 8,
                    scale: 1,
                    padding: { horizontal: 20, vertical: 15 }
                  },
                  hovered: {
                    backgroundColor: '#0e7490',
                    borderColor: '#67e8f9',
                    elevation: 14,
                    scale: 1.025
                  },
                  focused: {
                    borderColor: '#ffffff',
                    borderWidth: 2
                  },
                  pressed: {
                    backgroundColor: '#0891b2',
                    elevation: 0,
                    scale: 0.955
                  },
                  disabled: {
                    backgroundColor: '#1e293b',
                    foregroundColor: '#64748b',
                    borderColor: '#334155',
                    opacity: 0.65
                  }
                },
                onPressed: state.armed ? actions.launch() : undefined
              }),
              Container({
                padding: 17,
                decoration: {
                  color: '#0f172a',
                  borderRadius: 20,
                  border: { color: '#1e293b', width: 1 }
                },
                child: Column({
                  gap: 16,
                  children: [
                    Row({
                      mainAxisAlignment: 'spaceBetween',
                      children: [
                        Column({
                          crossAxisAlignment: 'start',
                          gap: 4,
                          children: [
                            Text('核心武装', {
                              style: {
                                color: '#e2e8f0',
                                fontSize: 16,
                                fontWeight: 'w700'
                              }
                            }),
                            Text(state.armed ? 'ONLINE' : 'STANDBY', {
                              style: {
                                color: state.armed ? '#5eead4' : '#64748b',
                                fontSize: 11,
                                fontWeight: 'w700'
                              }
                            })
                          ]
                        }),
                        Switch({
                          value: state.armed,
                          onChanged: actions.setArmed(),
                          stateTransition: transition,
                          stateStyles: {
                            normal: { scale: 1, opacity: 1 },
                            hovered: { scale: 1.08 },
                            pressed: { scale: 0.92 }
                          },
                          thumbStyle: {
                            normal: { color: '#94a3b8' },
                            selected: { color: '#ecfeff' },
                            pressed: { color: '#67e8f9' }
                          },
                          trackStyle: {
                            normal: {
                              color: '#334155',
                              borderColor: '#475569',
                              borderWidth: 1
                            },
                            selected: {
                              color: '#0e7490',
                              borderColor: '#22d3ee',
                              borderWidth: 2
                            },
                            hovered: { color: '#0891b2' }
                          },
                          overlayStyle: {
                            normal: { color: '#2222d3ee' },
                            pressed: { color: '#5522d3ee' }
                          }
                        })
                      ]
                    }),
                    Text(`输出强度 ${Math.round(state.intensity)}%`, {
                      style: { color: '#a5f3fc', fontSize: 13 }
                    }),
                    Slider({
                      value: state.intensity,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label: `${Math.round(state.intensity)}%`,
                      onChanged: actions.setIntensity(),
                      stateTransition: {
                        durationMs: 120,
                        curve: 'easeOut'
                      },
                      stateStyles: {
                        normal: { scale: 1 },
                        hovered: { scale: 1.015 },
                        pressed: { scale: 0.985 }
                      },
                      trackStyle: {
                        normal: {
                          activeColor: '#06b6d4',
                          inactiveColor: '#1e293b',
                          height: 6
                        },
                        hovered: {
                          activeColor: '#22d3ee',
                          height: 8
                        },
                        pressed: {
                          activeColor: '#67e8f9',
                          height: 10
                        }
                      },
                      thumbStyle: {
                        normal: { color: '#cffafe', radius: 10 },
                        hovered: { radius: 12 },
                        pressed: { color: '#ffffff', radius: 14 }
                      },
                      overlayStyle: {
                        normal: { color: '#3322d3ee', radius: 20 },
                        pressed: { color: '#5522d3ee', radius: 27 }
                      }
                    })
                  ]
                })
              }),
              TextField({
                value: state.callsign,
                labelText: '任务代号',
                hintText: '输入代号',
                leading: Icon({ icon: 'widgets', color: '#22d3ee' }),
                prefix: Icon({ icon: 'search', color: '#64748b', size: 18 }),
                trailing: Icon({ icon: 'tune', color: '#67e8f9' }),
                stateTransition: transition,
                stateStyles: {
                  normal: {
                    fillColor: '#0f172a',
                    borderColor: '#334155',
                    borderWidth: 1,
                    borderRadius: 15,
                    scale: 1
                  },
                  hovered: {
                    fillColor: '#111c31',
                    borderColor: '#475569'
                  },
                  focused: {
                    fillColor: '#0c2130',
                    borderColor: '#22d3ee',
                    borderWidth: 2,
                    borderRadius: 20,
                    scale: 1.015
                  },
                  disabled: {
                    fillColor: '#0b1220',
                    borderColor: '#1e293b',
                    opacity: 0.6
                  }
                },
                onChanged: actions.setCallsign()
              }),
              Text('快速移动鼠标并连续点击，观察动画是否从当前帧平滑转向。', {
                style: { color: '#64748b', fontSize: 12 }
              })
            ]
          })
        })
      ]
    });
  }
});
