import { Column, ElevatedButton, Page, Text } from 'quickjs_ui';

export default Page({
  name: 'DevPanelPage',

  createState() {
    return { count: 0, note: '等待挂载' };
  },

  onMount(state) {
    return { ...state, note: '已挂载' };
  },

  build(state, props, page) {
    return Column({
      mainAxisAlignment: 'center',
      crossAxisAlignment: 'stretch',
      children: [
        Text('开发调试面板', {
          key: 'title',
          style: { fontSize: 20, fontWeight: 'bold' }
        }),
        Text(`计数: ${state.count}`, { key: 'count' }),
        Text(state.note, { key: 'note' }),
        ElevatedButton({
          key: 'increment',
          child: Text('增加'),
          onPressed: page.increment()
        }),
        ElevatedButton({
          key: 'update-note',
          child: Text('更新备注'),
          onPressed: page.updateNote()
        })
      ]
    });
  },

  increment(state) {
    return { ...state, count: state.count + 1 };
  },

  updateNote(state) {
    return { ...state, note: `更新于 ${state.count}` };
  }
});
