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

const initialItems = ['alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta'];

export default Page({
  name: 'ScrollTransitionPage',

  createState() {
    return {
      items: initialItems,
      scrollToken: 0,
      scrollToKey: null,
      swipe: 'none',
      scroll: '空闲',
    };
  },

  build(state, props, page) {
    return ListView({
      key: 'scroll-root',
      padding: { all: 16 },
      scrollToken: state.scrollToken,
      scrollToKey: state.scrollToKey,
      scrollDurationMs: 180,
      onScroll: page.onScroll(),
      animateItems: true,
      itemTransitionDurationMs: 180,
      children: [
        Container({
          key: 'title',
          margin: { bottom: 12 },
          child: Text('QuickJS UI 0.4.2 滚动与列表过渡', {
            style: '$text.titleMedium',
          }),
        }),
        Container({
          key: 'swipe-card',
          padding: { all: 12 },
          margin: { bottom: 12 },
          decoration: {
            color: '$primaryContainer',
            borderRadius: 12,
            border: { color: '$outline', width: 1 },
          },
          onSwipe: page.swipeCard(),
          child: Column({
            crossAxisAlignment: 'stretch',
            children: [
              Text('滑动手势卡片', { style: { fontWeight: 'w700' } }),
              Text(`最近滑动方向：${state.swipe}`),
            ],
          }),
        }),
        Container({
          key: 'actions',
          margin: { bottom: 12 },
          child: Column({
            crossAxisAlignment: 'stretch',
            children: [
              ElevatedButton({
                onPressed: page.scrollToLast(),
                child: Text('滚动到最后一项'),
              }),
              ElevatedButton({
                onPressed: page.reorderItems(),
                child: Text('反转动画列表'),
              }),
              ElevatedButton({
                onPressed: page.addItem(),
                child: Text('新增动画项'),
              }),
            ],
          }),
        }),
        SizedBox({
          key: 'nested-scroll-shell',
          height: 128,
          child: Container({
            padding: { all: 8 },
            margin: { bottom: 12 },
            decoration: {
              color: '$surface',
              borderRadius: 10,
              border: { color: '$outline', width: 1 },
            },
            child: SingleChildScrollView({
              onScroll: page.onNestedScroll(),
              children: [
                Text('SingleChildScrollView 演示'),
                ...Array.from({ length: 8 }, (_, index) =>
                  Text(`嵌套滚动块 ${index + 1}`)
                ),
              ],
            }),
          }),
        }),
        Container({
          key: 'status',
          margin: { bottom: 8 },
          child: Text(`滚动状态：${state.scroll}`),
        }),
        ...state.items.map((item) => itemCard(item)),
      ],
    });
  },

  onScroll(state, payload, props, event) {
    const pixels = Math.round(event.pixels ?? 0);
    return { scroll: `根列表 ${pixels}px` };
  },

  onNestedScroll(state, payload, props, event) {
    const pixels = Math.round(event.pixels ?? 0);
    return { scroll: `嵌套列表 ${pixels}px` };
  },

  swipeCard(state, payload, props, event) {
    return { swipe: event.direction ?? 'unknown' };
  },

  scrollToLast(state) {
    const last = state.items[state.items.length - 1];
    return {
      scrollToken: state.scrollToken + 1,
      scrollToKey: `item-${last}`,
      scroll: `滚动到 ${last}`,
    };
  },

  reorderItems(state) {
    return {
      items: [...state.items].reverse(),
      scroll: '列表已反转',
    };
  },

  addItem(state) {
    const next = `new-${state.items.length + 1}`;
    return {
      items: [next, ...state.items],
      scroll: `已新增 ${next}`,
    };
  },
});

function itemCard(item) {
  return Container({
    key: `item-${item}`,
    padding: { all: 12 },
    margin: { bottom: 8 },
    decoration: {
      color: '$surface',
      borderRadius: 10,
      border: { color: '$outline', width: 1 },
    },
    child: Text(`动画列表项：${item}`),
  });
}
