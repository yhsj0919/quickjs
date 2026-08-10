import {
  Column,
  Container,
  ElevatedButton,
  Expanded,
  ListView,
  Page,
  Text,
  Wrap,
} from 'quickjs_ui';

const initialItems = ['alpha', 'beta', 'gamma', 'delta'];

function itemCard(item, index) {
  return Container({
    key: `item-${item}`,
    padding: { all: 14 },
    margin: { bottom: 8 },
    decoration: {
      color: index % 2 === 0 ? '$primaryContainer' : '$secondaryContainer',
      borderRadius: 12,
      border: { color: '$outline', width: 1 },
    },
    child: Column({
      crossAxisAlignment: 'stretch',
      gap: 4,
      children: [
        Text(item, { style: { fontWeight: 'w800' } }),
        Text(`key = item-${item}`, { style: { color: '$outline', fontSize: 12 } }),
      ],
    }),
  });
}

export default Page({
  name: 'KeyedListTransitionsPage',

  createState() {
    return { items: initialItems, nextId: 1, status: '等待操作' };
  },

  build(state, _props, page) {
    return Column({
      crossAxisAlignment: 'stretch',
      children: [
        Container({
          padding: { left: 16, right: 16, top: 16, bottom: 12 },
          child: Column({
            crossAxisAlignment: 'stretch',
            gap: 10,
            children: [
              Text('Keyed 列表过渡', { style: { fontSize: 24, fontWeight: 'w800' } }),
              Text('新增、删除和反转时，stable key 决定列表项的进出与重排。', {
                style: { color: '$outline', fontSize: 13 },
              }),
              Wrap({
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton({ label: '新增', onPressed: page.addItem() }),
                  ElevatedButton({ label: '删除首项', onPressed: page.removeFirst() }),
                  ElevatedButton({ label: '反转', onPressed: page.reverseItems() }),
                ],
              }),
              Container({
                padding: { all: 10 },
                decoration: { color: '$surfaceVariant', borderRadius: 10 },
                child: Text(`状态：${state.status}`),
              }),
            ],
          }),
        }),
        Expanded({
          child: ListView({
            padding: { left: 16, right: 16, bottom: 16 },
            animateItems: true,
            itemTransitionDurationMs: 220,
            children: state.items.map((item, index) => itemCard(item, index)),
          }),
        }),
      ],
    });
  },

  addItem(state) {
    const item = `new-${state.nextId}`;
    return {
      items: [item, ...state.items],
      nextId: state.nextId + 1,
      status: `新增 ${item}`,
    };
  },
  removeFirst(state) {
    if (state.items.length === 0) return { status: '列表已经为空' };
    return { items: state.items.slice(1), status: `删除 ${state.items[0]}` };
  },
  reverseItems(state) {
    return { items: [...state.items].reverse(), status: '列表顺序已反转' };
  },
});
