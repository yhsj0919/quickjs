import {
  AppBar,
  BottomNavigationBar,
  Column,
  Container,
  Drawer,
  Expanded,
  FloatingActionButton,
  GridView,
  Icon,
  IconButton,
  ListView,
  OutlinedButton,
  Page,
  Row,
  Scaffold,
  Stack,
  Positioned,
  Text,
} from 'quickjs_ui';

const destinations = [
  { label: '首页', iconName: 'home' },
  { label: '组件', iconName: 'widgets' },
  { label: '信息', iconName: 'info' },
];

function card(title, detail, color = '$surfaceVariant') {
  return Container({
    padding: { all: 14 },
    decoration: {
      color,
      borderRadius: 16,
      border: { color: '$outline', width: 1 },
    },
    child: Column({
      crossAxisAlignment: 'stretch',
      mainAxisAlignment: 'center',
      gap: 6,
      children: [
        Text(title, { style: { fontWeight: 'w800' } }),
        Text(detail, { style: { color: '$outline', fontSize: 12 } }),
      ],
    }),
  });
}

function content(state) {
  return ListView({
    padding: { all: 16 },
    children: [
      Text('页面结构与导航', { style: { fontSize: 24, fontWeight: 'w800' } }),
      Text('本页只演示 Scaffold 插槽、导航容器和基础布局。', {
        style: { color: '$outline', fontSize: 13 },
      }),
      Container({ height: 16 }),
      GridView({
        shrinkWrap: true,
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.45,
        children: [
          card('Scaffold', 'AppBar / Drawer / FAB'),
          card('Navigation', 'BottomNavigationBar'),
          card('GridView', '二维自适应排列'),
          card('Stack', 'Positioned 分层布局'),
        ],
      }),
      Container({ height: 12 }),
      Container({
        height: 150,
        decoration: { color: '$surface', borderRadius: 16 },
        child: Stack({
          children: [
            Positioned({
              left: 14,
              top: 14,
              child: Container({
                width: 86,
                height: 86,
                decoration: { color: '$secondaryContainer', borderRadius: 20 },
              }),
            }),
            Positioned({
              right: 14,
              bottom: 14,
              child: Container({
                width: 220,
                padding: { all: 16 },
                decoration: { color: '#eef2ff', borderRadius: 18 },
                child: Text(`当前导航：${destinations[state.section].label}`),
              }),
            }),
          ],
        }),
      }),
      Container({ height: 12 }),
      card('最近操作', state.lastAction, '$primaryContainer'),
    ],
  });
}

export default Page({
  name: 'LayoutNavigationDemo',

  createState() {
    return { section: 0, actionCount: 0, lastAction: '等待操作' };
  },

  build(state, _props, page) {
    return Scaffold({
      appBar: AppBar({
        titleText: '页面结构与导航',
        actions: [
          IconButton({ icon: 'back', tooltip: '返回', onPressed: page.goBack() }),
        ],
      }),
      drawer: Drawer({
        child: ListView({
          padding: { top: 24, horizontal: 16 },
          children: [
            Row({ children: [Icon({ icon: 'menu' }), Expanded({ child: Text('Drawer 插槽') })] }),
            Container({ height: 12 }),
            Text(`当前导航：${destinations[state.section].label}`),
            Container({ height: 12 }),
            OutlinedButton({ label: '记录一次操作', onPressed: page.recordAction() }),
          ],
        }),
      }),
      body: content(state),
      bottomNavigationBar: BottomNavigationBar({
        currentIndex: state.section,
        onTap: page.selectSection(),
        items: destinations,
      }),
      floatingActionButton: FloatingActionButton({
        icon: 'add',
        tooltip: '记录操作',
        onPressed: page.recordAction(),
      }),
    });
  },

  async goBack() {
    if (globalThis.quickjsUiDemo?.back) {
      await globalThis.quickjsUiDemo.back({ source: 'layout-navigation-demo' });
    }
    return null;
  },

  selectSection(_state, _payload, _props, event) {
    const section = event.index ?? 0;
    return { section, lastAction: `切换到 ${destinations[section].label}` };
  },

  recordAction(state) {
    const actionCount = state.actionCount + 1;
    return { actionCount, lastAction: `快速操作 #${actionCount}` };
  },
});
