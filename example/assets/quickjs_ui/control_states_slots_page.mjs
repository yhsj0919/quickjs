import {
  Column,
  Container,
  ElevatedButton,
  Icon,
  OutlinedButton,
  Page,
  Row,
  SingleChildScrollView,
  Slider,
  Switch,
  Text,
  TextField
} from 'quickjs_ui';

const accentStates = {
  normal: {
    backgroundColor: '#172554',
    foregroundColor: '#dbeafe',
    borderColor: '#3b82f6',
    borderWidth: 1,
    borderRadius: 16,
    padding: { horizontal: 18, vertical: 14 }
  },
  hovered: {
    backgroundColor: '#1e3a8a',
    borderColor: '#60a5fa'
  },
  focused: {
    borderColor: '#22d3ee',
    borderWidth: 2
  },
  pressed: {
    backgroundColor: '#0891b2',
    foregroundColor: '#ffffff',
    elevation: 0
  },
  disabled: {
    backgroundColor: '#1e293b',
    foregroundColor: '#64748b',
    borderColor: '#334155'
  }
};

export default Page({
  name: 'ControlStatesSlotsPage',

  createState() {
    return { enabled: true, notifications: true, volume: 64, query: '' };
  },

  toggleEnabled(state) {
    return { enabled: !state.enabled };
  },

  setNotifications(state, data) {
    return { notifications: data.value };
  },

  setVolume(state, data) {
    return { volume: data.value };
  },

  setQuery(state, data) {
    return { query: data.value };
  },

  build(state, props, actions) {
    return SingleChildScrollView({
      padding: 20,
      children: [
        Container({
          padding: 22,
          decoration: {
            color: '#07111f',
            borderRadius: 26,
            border: { color: '#1e3a5f', width: 1 }
          },
          child: Column({
            crossAxisAlignment: 'stretch',
            gap: 20,
            children: [
              Text('CONTROL STATES + SLOTS', {
                style: {
                  color: '#e0f2fe',
                  fontSize: 22,
                  fontWeight: 'w800'
                }
              }),
              Text(
                '同一套 normal / hovered / focused / pressed / disabled 状态模型',
                { style: { color: '#94a3b8', fontSize: 13 } }
              ),
              ElevatedButton({
                leading: Icon({ icon: 'bolt', color: '#67e8f9' }),
                child: Text(state.enabled ? '交互已启用' : '重新启用'),
                trailing: Icon({ icon: 'arrow_forward', size: 18 }),
                gap: 10,
                stateStyles: accentStates,
                onPressed: actions.toggleEnabled()
              }),
              OutlinedButton({
                leading: Icon({ icon: 'lock', size: 18 }),
                label: 'Disabled 状态',
                trailing: Text('HOST FREE', {
                  style: { color: '#64748b', fontSize: 10 }
                }),
                stateStyles: accentStates
              }),
              Container({
                padding: 16,
                decoration: { color: '#0f172a', borderRadius: 18 },
                child: Column({
                  gap: 14,
                  children: [
                    Row({
                      mainAxisAlignment: 'spaceBetween',
                      children: [
                        Text('通知粒子流', {
                          style: { color: '#e2e8f0', fontSize: 16 }
                        }),
                        Switch({
                          value: state.notifications,
                          onChanged: state.enabled
                            ? actions.setNotifications()
                            : undefined,
                          thumbStyle: {
                            normal: { color: '#cbd5e1' },
                            selected: { color: '#ffffff' },
                            pressed: { color: '#67e8f9' },
                            disabled: { color: '#475569' }
                          },
                          trackStyle: {
                            normal: { color: '#334155' },
                            selected: {
                              color: '#0891b2',
                              borderColor: '#22d3ee',
                              borderWidth: 1
                            },
                            hovered: { color: '#0e7490' },
                            disabled: { color: '#1e293b' }
                          }
                        })
                      ]
                    }),
                    Text(`能量 ${Math.round(state.volume)}%`, {
                      style: { color: '#a5f3fc', fontSize: 13 }
                    }),
                    Slider({
                      value: state.volume,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label: `${Math.round(state.volume)}%`,
                      onChanged: state.enabled ? actions.setVolume() : undefined,
                      trackStyle: {
                        normal: {
                          activeColor: '#06b6d4',
                          inactiveColor: '#1e293b',
                          height: 7
                        },
                        disabled: {
                          activeColor: '#475569',
                          inactiveColor: '#1e293b'
                        }
                      },
                      thumbStyle: {
                        normal: { color: '#67e8f9', radius: 11 },
                        disabled: { color: '#475569' }
                      },
                      overlayStyle: {
                        normal: { color: '#3322d3ee', radius: 24 }
                      }
                    })
                  ]
                })
              }),
              TextField({
                value: state.query,
                enabled: state.enabled,
                labelText: '搜索组件',
                hintText: '输入 Button、Slider…',
                leading: Icon({ icon: 'widgets', color: '#22d3ee' }),
                prefix: Icon({ icon: 'search', size: 18, color: '#94a3b8' }),
                suffix: Text(`${state.query.length}/24`, {
                  style: { color: '#64748b', fontSize: 11 }
                }),
                trailing: Icon({ icon: 'tune', color: '#67e8f9' }),
                stateStyles: {
                  normal: {
                    fillColor: '#0f172a',
                    borderColor: '#334155',
                    borderWidth: 1,
                    borderRadius: 15
                  },
                  hovered: { fillColor: '#111c31', borderColor: '#475569' },
                  focused: {
                    fillColor: '#0c1b2e',
                    borderColor: '#22d3ee',
                    borderWidth: 2
                  },
                  disabled: {
                    fillColor: '#0b1220',
                    borderColor: '#1e293b'
                  }
                },
                onChanged: actions.setQuery()
              })
            ]
          })
        })
      ]
    });
  }
});
