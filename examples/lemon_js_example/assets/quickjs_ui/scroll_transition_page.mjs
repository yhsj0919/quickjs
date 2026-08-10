import {
  Column,
  Container,
  ElevatedButton,
  ListView,
  Page,
  SingleChildScrollView,
  SizedBox,
  Text,
} from 'quickjs_ui';

const sections = ['alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta'];

export default Page({
  name: 'ScrollControlPage',

  createState() {
    return { scrollToken: 0, scrollToKey: null, status: '空闲' };
  },

  build(state, _props, page) {
    return ListView({
      key: 'scroll-root',
      padding: { all: 16 },
      scrollToken: state.scrollToken,
      scrollToKey: state.scrollToKey,
      scrollDurationMs: 220,
      onScroll: page.onRootScroll(),
      children: [
        Text('滚动控制与嵌套滚动', { style: { fontSize: 24, fontWeight: 'w800' } }),
        Text('验证滚动位置事件、按 stable key 定位和独立嵌套滚动区域。', {
          style: { color: '$outline', fontSize: 13 },
        }),
        Container({ height: 12 }),
        ElevatedButton({ label: '定位到 epsilon', onPressed: page.scrollToEpsilon() }),
        Container({
          margin: { vertical: 12 },
          padding: { all: 12 },
          decoration: { color: '$primaryContainer', borderRadius: 12 },
          child: Text(`状态：${state.status}`),
        }),
        SizedBox({
          height: 132,
          child: Container({
            padding: { all: 10 },
            decoration: {
              color: '$surface',
              borderRadius: 12,
              border: { color: '$outline', width: 1 },
            },
            child: SingleChildScrollView({
              onScroll: page.onNestedScroll(),
              children: [
                Text('嵌套 SingleChildScrollView', { style: { fontWeight: 'w800' } }),
                ...Array.from({ length: 9 }, (_, index) => Text(`嵌套内容 ${index + 1}`)),
              ],
            }),
          }),
        }),
        Container({ height: 12 }),
        ...sections.map((section, index) => Container({
          key: `section-${section}`,
          height: 112,
          margin: { bottom: 10 },
          padding: { all: 14 },
          decoration: {
            color: index % 2 === 0 ? '$surface' : '$surfaceVariant',
            borderRadius: 14,
            border: { color: '$outline', width: 1 },
          },
          child: Column({
            crossAxisAlignment: 'stretch',
            children: [
              Text(section, { style: { fontWeight: 'w800' } }),
              Text(`stable key: section-${section}`, { style: { color: '$outline' } }),
            ],
          }),
        })),
      ],
    });
  },

  onRootScroll(_state, _payload, _props, event) {
    return { status: `根列表 ${Math.round(event.pixels ?? 0)}px` };
  },
  onNestedScroll(_state, _payload, _props, event) {
    return { status: `嵌套区域 ${Math.round(event.pixels ?? 0)}px` };
  },
  scrollToEpsilon(state) {
    return {
      scrollToken: state.scrollToken + 1,
      scrollToKey: 'section-epsilon',
      status: '正在定位到 epsilon',
    };
  },
});
