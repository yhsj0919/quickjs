import {
  animate,
  Center,
  Column,
  Container,
  GestureDetector,
  Page,
  Text
} from 'quickjs_ui';

const entrance = (from, to, durationMs = 720) =>
  animate(from, to, { durationMs, curve: 'easeOut' });

export default Page({
  name: 'UniversalEffectsPage',

  createState() {
    return { run: 0, completed: false };
  },

  replay(state) {
    return { run: state.run + 1, completed: false };
  },

  finished(state, data) {
    if (data.run !== state.run) return null;
    return { completed: true };
  },

  build(state, props, actions) {
    return Center({
      child: GestureDetector({
        onTap: actions.replay(),
        child: Container({
          width: 330,
          padding: 24,
          decoration: {
            color: '#07111f',
            borderRadius: 28,
            border: { color: '#1e3a5f', width: 1 }
          },
          child: Column({
            gap: 18,
            children: [
              Text('UNIVERSAL NODE EFFECTS', {
                style: {
                  color: '#e0f2fe',
                  fontSize: 22,
                  fontWeight: 'w800'
                }
              }),
              Container({
                key: 'animated-effect-card',
                width: 270,
                height: 190,
                padding: 24,
                playToken: state.run,
                opacity: entrance(0.08, 1, 620),
                transform: {
                  translate: {
                    x: entrance(-72, 0),
                    y: entrance(52, 0)
                  },
                  scale: entrance(0.72, 1),
                  rotate: entrance(-0.16, 0)
                },
                clipRadius: entrance(72, 24),
                blur: entrance(14, 0, 560),
                onAnimationEnd: actions.finished({ run: state.run }),
                decoration: {
                  color: '#4f46e5',
                  borderRadius: 24,
                  border: { color: '#818cf8', width: 1 }
                },
                child: Column({
                  crossAxisAlignment: 'start',
                  gap: 12,
                  children: [
                    Text('Any Flutter node', {
                      style: {
                        color: '#ffffff',
                        fontSize: 24,
                        fontWeight: 'w800'
                      }
                    }),
                    Text('opacity · transform · clip · blur', {
                      style: { color: '#c7d2fe', fontSize: 14 }
                    }),
                    Container({
                      width: 170,
                      height: 12,
                      colorFilter: {
                        color: '#80ffffff',
                        blendMode: 'screen'
                      },
                      decoration: {
                        color: '#22d3ee',
                        borderRadius: 6
                      }
                    })
                  ]
                })
              }),
              Text(
                state.completed
                  ? '动画完成 · 点击重新播放'
                  : 'Flutter VSync 本地执行',
                {
                  style: {
                    color: state.completed ? '#5eead4' : '#94a3b8',
                    fontSize: 13,
                    fontWeight: 'w600'
                  }
                }
              )
            ]
          })
        })
      })
    });
  }
});
