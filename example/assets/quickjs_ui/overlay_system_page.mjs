import {
  Column,
  Container,
  ElevatedButton,
  Overlay,
  Page,
  Row,
  SingleChildScrollView,
  Text
} from 'quickjs_ui';

function overlayCard(state, actions) {
  return Container({
    width: 320,
    padding: 20,
    decoration: {
      color: '#0f172a',
      borderRadius: 22,
      border: { color: '#22d3ee', width: 1 }
    },
    child: Column({
      mainAxisSize: 'min',
      crossAxisAlignment: 'stretch',
      gap: 12,
      children: [
        Text('ARBITRARY OVERLAY', {
          style: { color: '#67e8f9', fontSize: 18, fontWeight: 'w800' }
        }),
        Text(`位置：${state.alignment} · 动画：${state.transition}`, {
          style: { color: '#cbd5e1', fontSize: 13 }
        }),
        Text('这里可以放任意 JSUI 控件、Canvas、表单或组合组件。', {
          style: { color: '#94a3b8', fontSize: 13 }
        }),
        ElevatedButton({
          child: Text('关闭浮层'),
          onPressed: actions.close(),
          stateStyles: {
            normal: {
              backgroundColor: '#0891b2',
              foregroundColor: '#ffffff',
              borderRadius: 12
            },
            pressed: { scale: 0.95 }
          }
        })
      ]
    })
  });
}

export default Page({
  name: 'OverlaySystemPage',

  createState() {
    return {
      visible: false,
      alignment: 'center',
      transition: 'fadeScale',
      dismissals: 0
    };
  },

  open(state, data) {
    return {
      visible: true,
      alignment: data.alignment,
      transition: data.transition
    };
  },

  close() {
    return { visible: false };
  },

  dismissed(state) {
    return { visible: false, dismissals: state.dismissals + 1 };
  },

  build(state, props, actions) {
    return SingleChildScrollView({
      padding: 20,
      children: [
        Container({
          padding: 20,
          decoration: {
            color: '#07111f',
            borderRadius: 26,
            border: { color: '#164e63', width: 1 }
          },
          child: Column({
            crossAxisAlignment: 'stretch',
            gap: 16,
            children: [
              Text('OVERLAY SYSTEM LAB', {
                style: { color: '#ecfeff', fontSize: 23, fontWeight: 'w800' }
              }),
              Text('统一测试任意内容、遮罩、定位、进出动画和关闭生命周期。', {
                style: { color: '#94a3b8', fontSize: 13 }
              }),
              ElevatedButton({
                child: Text('中央 · Fade + Scale'),
                onPressed: actions.open({
                  alignment: 'center',
                  transition: 'fadeScale'
                })
              }),
              Row({
                gap: 10,
                children: [
                  ElevatedButton({
                    child: Text('顶部下滑'),
                    onPressed: actions.open({
                      alignment: 'topCenter',
                      transition: 'slideDown'
                    })
                  }),
                  ElevatedButton({
                    child: Text('底部'),
                    onPressed: actions.open({
                      alignment: 'bottomCenter',
                      transition: 'slideUp'
                    })
                  })
                ]
              }),
              Text(`遮罩关闭次数：${state.dismissals}`, {
                style: { color: '#67e8f9', fontSize: 13 }
              })
            ]
          })
        }),
        Overlay({
          visible: state.visible,
          alignment: state.alignment,
          padding: 20,
          barrierDismissible: true,
          barrierColor: '#99020717',
          transition: state.transition,
          durationMs: 180,
          curve: 'easeOutCubic',
          onDismissed: actions.dismissed(),
          child: overlayCard(state, actions)
        })
      ]
    });
  }
});
