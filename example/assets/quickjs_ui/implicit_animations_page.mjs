import {
  AnimatedContainer,
  AnimatedOpacity,
  AnimatedPadding,
  Column,
  Container,
  ElevatedButton,
  Page,
  SingleChildScrollView,
  Text,
} from 'quickjs_ui';

export default Page({
  name: 'ImplicitAnimationsPage',

  createState() {
    return { expanded: false, visible: true, padded: false };
  },

  build(state, _props, page) {
    return SingleChildScrollView({
      padding: { all: 16 },
      children: [
        Text('基础隐式动画', { style: { fontSize: 24, fontWeight: 'w800' } }),
        Text('三个示例分别控制尺寸与装饰、透明度和内边距。', {
          style: { color: '$outline', fontSize: 13 },
        }),
        Container({ height: 16 }),
        Column({
          crossAxisAlignment: 'stretch',
          gap: 12,
          children: [
            ElevatedButton({
              label: '切换 AnimatedContainer',
              onPressed: page.toggleExpanded(),
            }),
            AnimatedContainer({
              durationMs: 280,
              animationCurve: 'easeInOut',
              height: state.expanded ? 128 : 64,
              alignment: 'center',
              decoration: {
                color: state.expanded ? '$primary' : '$primaryContainer',
                borderRadius: state.expanded ? 28 : 10,
              },
              child: Text(state.expanded ? '展开状态' : '收起状态', {
                style: { color: state.expanded ? '$onPrimary' : '$onPrimaryContainer' },
              }),
            }),
            ElevatedButton({ label: '切换 AnimatedOpacity', onPressed: page.toggleVisible() }),
            AnimatedOpacity({
              durationMs: 240,
              opacity: state.visible ? 1 : 0.15,
              child: Container({
                padding: { all: 18 },
                decoration: { color: '$secondaryContainer', borderRadius: 12 },
                child: Text('透明度独立变化'),
              }),
            }),
            ElevatedButton({ label: '切换 AnimatedPadding', onPressed: page.togglePadding() }),
            Container({
              decoration: { color: '$surfaceVariant', borderRadius: 12 },
              child: AnimatedPadding({
                durationMs: 260,
                padding: state.padded ? 32 : 6,
                child: Container({
                  height: 48,
                  alignment: 'center',
                  decoration: { color: '$tertiaryContainer', borderRadius: 10 },
                  child: Text('内边距独立变化'),
                }),
              }),
            }),
          ],
        }),
      ],
    });
  },

  toggleExpanded(state) {
    return { expanded: !state.expanded };
  },
  toggleVisible(state) {
    return { visible: !state.visible };
  },
  togglePadding(state) {
    return { padded: !state.padded };
  },
});
