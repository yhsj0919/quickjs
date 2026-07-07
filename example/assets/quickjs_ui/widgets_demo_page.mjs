import {
  AlertDialog,
  AnimatedAlign,
  AnimatedSwitcher,
  AppBar,
  BottomNavigationBar,
  BottomSheet,
  Card,
  Center,
  Checkbox,
  CircularProgressIndicator,
  ClipRRect,
  Column,
  Container,
  DecoratedBox,
  Divider,
  Drawer,
  DropdownButton,
  Expanded,
  FloatingActionButton,
  GridView,
  Icon,
  IconButton,
  InkWell,
  LinearProgressIndicator,
  ListView,
  OutlinedButton,
  Page,
  Padding,
  Positioned,
  RefreshIndicator,
  RichText,
  Row,
  SafeArea,
  Scaffold,
  SingleChildScrollView,
  SizedBox,
  Slider,
  SnackBar,
  Spacer,
  Stack,
  Switch,
  Text,
  TextButton,
  Wrap,
} from 'quickjs_ui';

const menuItems = [
  { label: '总览', iconName: 'home' },
  { label: '表单', iconName: 'edit' },
  { label: '反馈', iconName: 'info' },
];

function sectionTitle(title, subtitle) {
  return Padding({
    padding: { bottom: 12 },
    child: Column({
      crossAxisAlignment: 'stretch',
      gap: 4,
      children: [
        Text(title, { style: { fontSize: 22, fontWeight: 'w800' } }),
        Text(subtitle, { style: { color: '$outline', fontSize: 13 } }),
      ],
    }),
  });
}

function panel({ child, color = '$surface', marginBottom = 12 }) {
  return Container({
    margin: { bottom: marginBottom },
    padding: { all: 14 },
    decoration: {
      color,
      borderRadius: 16,
      border: { color: '$outline', width: 1 },
    },
    child,
  });
}

function metric(label, value, color) {
  return Container({
    padding: { all: 12 },
    decoration: {
      color,
      borderRadius: 14,
    },
    child: Column({
      crossAxisAlignment: 'stretch',
      gap: 4,
      children: [
        Text(value, { style: { fontSize: 20, fontWeight: 'w800' } }),
        Text(label, { style: { fontSize: 12, color: '$outline' } }),
      ],
    }),
  });
}

function overviewPage(state, page) {
  return ListView({
    padding: { all: 16 },
    children: [
      sectionTitle('0.6 组件总览', '一个重新生成的真实页面 demo，返回按钮在 JS AppBar 中声明。'),
      panel({
        color: '$primaryContainer',
        child: Column({
          crossAxisAlignment: 'stretch',
          gap: 12,
          children: [
            Row({
              children: [
                Icon({ icon: 'star', color: '$primary' }),
                Padding({
                  padding: { left: 8 },
                  child: Text('今日概览', {
                    style: { color: '$onPrimaryContainer', fontWeight: 'w800' },
                  }),
                }),
              ],
            }),
            RichText({
              spans: [
                'QuickJS UI 0.6 ',
                { text: '补齐基础控件', style: { fontWeight: 'w800', color: '$primary' } },
                '，本页用原生 Flutter Widget 渲染 JS schema。',
              ],
              style: { color: '$onPrimaryContainer' },
            }),
            Row({
              children: [
                Expanded({ child: metric('按钮点击', `${state.actionCount}`, '#dbeafe') }),
                Padding({ padding: { left: 8 }, child: SizedBox({ width: 1, height: 64, child: Divider({}) }) }),
                Expanded({ child: metric('刷新次数', `${state.refreshCount}`, '#dcfce7') }),
              ],
            }),
          ],
        }),
      }),
      GridView({
        shrinkWrap: true,
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.45,
        children: [
          featureTile('Scaffold', 'AppBar / Drawer / FAB'),
          featureTile('Layout', 'Wrap / Stack / Expanded'),
          featureTile('Forms', 'Switch / Slider / Dropdown'),
          featureTile('Overlay', 'SnackBar / Dialog / Sheet'),
        ],
      }),
      Padding({
        padding: { top: 12 },
        child: panel({
          child: SizedBox({
            height: 150,
            child: Stack({
              children: [
                Positioned({
                  left: 0,
                  top: 0,
                  child: Container({
                    width: 88,
                    height: 88,
                    decoration: {
                      color: '$secondaryContainer',
                      borderRadius: 20,
                    },
                  }),
                }),
                Positioned({
                  right: 0,
                  bottom: 0,
                  child: SizedBox({
                    width: 240,
                    height: 100,
                    child: DecoratedBox({
                      color: '#eef2ff',
                      child: ClipRRect({
                        borderRadius: 18,
                        child: Center({
                          child: Text('Stack + Positioned', {
                            style: { fontWeight: 'w700' },
                          }),
                        }),
                      }),
                    }),
                  }),
                }),
              ],
            }),
          }),
        }),
      }),
      panel({
        child: Wrap({
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton({ label: 'TextButton', onPressed: page.recordAction({ source: 'TextButton' }) }),
            OutlinedButton({ label: 'OutlinedButton', onPressed: page.recordAction({ source: 'OutlinedButton' }) }),
            IconButton({ icon: 'search', tooltip: 'IconButton', onPressed: page.recordAction({ source: 'IconButton' }) }),
          ],
        }),
      }),
      InkWell({
        onTap: page.recordAction({ source: 'InkWell' }),
        child: panel({
          color: '$surfaceVariant',
          child: Row({
            children: [
              Icon({ icon: 'info', color: '$primary' }),
              Padding({
                padding: { left: 10 },
                child: Text(`最近动作：${state.lastAction}`),
              }),
            ],
          }),
        }),
      }),
    ],
  });
}

function featureTile(title, subtitle) {
  return Container({
    padding: { all: 12 },
    decoration: {
      color: '$surfaceVariant',
      borderRadius: 14,
      border: { color: '$outline', width: 1 },
    },
    child: Column({
      crossAxisAlignment: 'stretch',
      mainAxisAlignment: 'center',
      gap: 4,
      children: [
        Text(title, { style: { fontWeight: 'w800' } }),
        Text(subtitle, { style: { color: '$outline', fontSize: 12 } }),
      ],
    }),
  });
}

function formPage(state, page) {
  return SingleChildScrollView({
    padding: { all: 16 },
    children: [
      sectionTitle('设置中心', '表单状态完全由 JS 管理，Flutter 只负责控件渲染和事件投递。'),
      panel({
        child: Column({
          crossAxisAlignment: 'stretch',
          gap: 12,
          children: [
            Row({
              children: [
                Checkbox({ value: state.accepted, onChanged: page.setAccepted() }),
                Expanded({ child: Text('启用实验控件') }),
                Switch({ value: state.darkPreview, onChanged: page.setDarkPreview() }),
              ],
            }),
            Divider({}),
            Text(`透明度：${Math.round(state.opacity * 100)}%`),
            Slider({
              value: state.opacity,
              min: 0.2,
              max: 1,
              divisions: 8,
              label: `${Math.round(state.opacity * 100)}%`,
              onChanged: page.setOpacity(),
            }),
            DropdownButton({
              value: state.priority,
              isExpanded: true,
              onChanged: page.setPriority(),
              items: [
                { value: 'low', label: '低优先级' },
                { value: 'normal', label: '普通优先级' },
                { value: 'high', label: '高优先级' },
              ],
            }),
          ],
        }),
      }),
      panel({
        color: state.darkPreview ? '#111827' : '#f8fafc',
        child: Column({
          crossAxisAlignment: 'stretch',
          gap: 10,
          children: [
            Text('实时预览', {
              style: {
                color: state.darkPreview ? '#ffffff' : '#111827',
                fontWeight: 'w800',
              },
            }),
            Container({
              width: 180 + state.opacity * 80,
              padding: { all: 12 },
              opacity: state.opacity,
              animationDurationMs: 220,
              animationCurve: 'easeOut',
              decoration: {
                color: state.accepted ? '$primary' : '$secondaryContainer',
                borderRadius: 14,
              },
              child: Text(`priority = ${state.priority}`, {
                style: { color: state.accepted ? '$onPrimary' : '$onSecondaryContainer' },
              }),
            }),
          ],
        }),
      }),
      Row({
        children: [
          Expanded({
            child: OutlinedButton({
              label: '重置',
              onPressed: page.resetForm(),
            }),
          }),
          SizedBox({ width: 8 }),
          Expanded({
            child: TextButton({
              label: '保存并提示',
              onPressed: page.saveForm(),
            }),
          }),
        ],
      }),
      SnackBar({
        visible: state.snackToken > 0,
        content: `表单已保存 #${state.snackToken}`,
        durationMs: 2200,
      }),
    ],
  });
}

function feedbackPage(state, page) {
  return ListView({
    padding: { all: 16 },
    children: [
      sectionTitle('反馈与动态效果', '浮层应立刻出现，不需要滚动到 schema 节点所在位置。'),
      panel({
        child: Column({
          crossAxisAlignment: 'stretch',
          gap: 10,
          children: [
            LinearProgressIndicator({ value: state.progress }),
            Row({
              children: [
                CircularProgressIndicator({}),
                SizedBox({ width: 16 }),
                Expanded({
                  child: Text(`当前进度：${Math.round(state.progress * 100)}%`),
                }),
              ],
            }),
          ],
        }),
      }),
      RefreshIndicator({
        onRefresh: page.refreshCards(),
        child: SizedBox({
          height: 130,
          child: ListView({
            children: [
              Center({
                child: Padding({
                  padding: { vertical: 32 },
                  child: Text(`下拉刷新区域：${state.refreshCount}`),
                }),
              }),
            ],
          }),
        }),
      }),
      panel({
        child: Column({
          crossAxisAlignment: 'stretch',
          gap: 12,
          children: [
            Text('动画示例', { style: { fontWeight: 'w800' } }),
            SizedBox({
              height: 56,
              child: AnimatedAlign({
                alignment: state.alignEnd ? 'centerRight' : 'centerLeft',
                durationMs: 240,
                animationCurve: 'easeOut',
                child: Container({
                  padding: { horizontal: 14, vertical: 8 },
                  decoration: { color: '$primary', borderRadius: 999 },
                  child: Text('AnimatedAlign', { style: { color: '$onPrimary' } }),
                }),
              }),
            }),
            AnimatedSwitcher({
              durationMs: 220,
              child: Container({
                key: state.switcherOn ? 'switcher-a' : 'switcher-b',
                padding: { all: 12 },
                decoration: {
                  color: state.switcherOn ? '#dcfce7' : '#fee2e2',
                  borderRadius: 12,
                },
                child: Text(state.switcherOn ? 'Switcher: 成功状态' : 'Switcher: 警示状态'),
              }),
            }),
            Row({
              children: [
                Expanded({ child: TextButton({ label: '移动', onPressed: page.toggleAlign() }) }),
                Expanded({ child: TextButton({ label: '切换', onPressed: page.toggleSwitcher() }) }),
              ],
            }),
          ],
        }),
      }),
      panel({
        child: Wrap({
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton({ label: 'SnackBar', onPressed: page.openSnack() }),
            OutlinedButton({ label: 'Dialog', onPressed: page.openDialog() }),
            OutlinedButton({ label: 'BottomSheet', onPressed: page.openSheet() }),
          ],
        }),
      }),
      SizedBox({ height: 420, child: Center({ child: Text('故意留出高度，用来验证浮层不依赖滚动挂载。') }) }),
      SnackBar({
        visible: state.snackToken > 0,
        content: `已触发 SnackBar #${state.snackToken}`,
        durationMs: 2200,
      }),
      AlertDialog({
        visible: state.showDialog,
        titleText: '0.6 Dialog',
        contentText: '这个 Dialog 现在应该作为真正的 overlay 显示。',
        actions: [
          TextButton({ label: '关闭', onPressed: page.closeDialog() }),
        ],
      }),
      BottomSheet({
        visible: state.showSheet,
        onClosing: page.closeSheet(),
        child: SafeArea({
          child: Padding({
            padding: { all: 20 },
            child: Column({
              crossAxisAlignment: 'stretch',
              gap: 12,
              children: [
                Text('BottomSheet', { style: { fontSize: 18, fontWeight: 'w800' } }),
                Text('这个浮层由 JS schema 声明，由 Flutter 原生 bottom sheet 呈现。'),
                OutlinedButton({ label: '关闭', onPressed: page.closeSheet() }),
              ],
            }),
          }),
        }),
      }),
    ],
  });
}

function bodyFor(state, page) {
  if (state.section === 1) {
    return formPage(state, page);
  }
  if (state.section === 2) {
    return feedbackPage(state, page);
  }
  return overviewPage(state, page);
}

export default Page({
  name: 'QuickjsUi06WidgetsDemo',

  createState() {
    return {
      section: 0,
      actionCount: 0,
      lastAction: '等待操作',
      refreshCount: 0,
      accepted: true,
      darkPreview: false,
      opacity: 0.8,
      priority: 'normal',
      progress: 0.42,
      alignEnd: false,
      switcherOn: true,
      snackToken: 0,
      showDialog: false,
      showSheet: false,
    };
  },

  build(state, props, page) {
    return Scaffold({
      appBar: AppBar({
        titleText: 'QuickJS UI 0.6 Demo',
        centerTitle: false,
        actions: [
          IconButton({
            icon: 'back',
            tooltip: '返回上一页',
            onPressed: page.goBack(),
          }),
          IconButton({
            icon: 'refresh',
            tooltip: '刷新状态',
            onPressed: page.refreshCards(),
          }),
        ],
      }),
      drawer: Drawer({
        child: ListView({
          padding: { top: 24, horizontal: 16 },
          children: [
            Text('0.6 Demo 菜单', { style: { fontSize: 18, fontWeight: 'w800' } }),
            Padding({
              padding: { vertical: 12 },
              child: Text(`当前分区：${menuItems[state.section].label}`),
            }),
            OutlinedButton({ label: '返回上一页', onPressed: page.goBack() }),
          ],
        }),
      }),
      body: bodyFor(state, page),
      bottomNavigationBar: BottomNavigationBar({
        currentIndex: state.section,
        onTap: page.selectSection(),
        items: menuItems,
      }),
      floatingActionButton: FloatingActionButton({
        icon: state.section === 2 ? 'info' : 'add',
        tooltip: '快速操作',
        onPressed: page.primaryAction(),
      }),
    });
  },

  async goBack() {
    if (globalThis.quickjsUiDemo?.back) {
      await globalThis.quickjsUiDemo.back({ source: 'quickjs-ui-0.6-demo' });
    }
    return null;
  },

  selectSection(state, _payload, _props, event) {
    const index = event.index ?? 0;
    return {
      section: index,
      lastAction: `切换到 ${menuItems[index].label}`,
    };
  },

  recordAction(state, payload) {
    return {
      actionCount: state.actionCount + 1,
      lastAction: payload?.source ?? '未知动作',
    };
  },

  primaryAction(state) {
    if (state.section === 2) {
      return {
        snackToken: state.snackToken + 1,
        actionCount: state.actionCount + 1,
        lastAction: 'FAB 触发 SnackBar',
      };
    }
    return {
      actionCount: state.actionCount + 1,
      progress: Math.min(1, state.progress + 0.08),
      lastAction: 'FAB 快速操作',
    };
  },

  setAccepted(state, _payload, _props, event) {
    return { accepted: event.value === true, lastAction: '更新 Checkbox' };
  },

  setDarkPreview(state, _payload, _props, event) {
    return { darkPreview: event.value === true, lastAction: '更新 Switch' };
  },

  setOpacity(state, _payload, _props, event) {
    return { opacity: event.value ?? state.opacity, lastAction: '更新 Slider' };
  },

  setPriority(state, _payload, _props, event) {
    return { priority: event.value ?? 'normal', lastAction: '更新 Dropdown' };
  },

  resetForm() {
    return {
      accepted: true,
      darkPreview: false,
      opacity: 0.8,
      priority: 'normal',
      lastAction: '重置表单',
    };
  },

  saveForm(state) {
    return {
      snackToken: state.snackToken + 1,
      lastAction: '保存表单',
    };
  },

  refreshCards(state) {
    const next = (state.progress + 0.17) % 1;
    return {
      refreshCount: state.refreshCount + 1,
      progress: next < 0.12 ? 0.12 : next,
      lastAction: `刷新 #${state.refreshCount + 1}`,
    };
  },

  toggleAlign(state) {
    return { alignEnd: !state.alignEnd, lastAction: '切换 AnimatedAlign' };
  },

  toggleSwitcher(state) {
    return { switcherOn: !state.switcherOn, lastAction: '切换 AnimatedSwitcher' };
  },

  openSnack(state) {
    return {
      snackToken: state.snackToken + 1,
      lastAction: '打开 SnackBar',
    };
  },

  openDialog() {
    return { showDialog: true, lastAction: '打开 Dialog' };
  },

  closeDialog() {
    return { showDialog: false, lastAction: '关闭 Dialog' };
  },

  openSheet() {
    return { showSheet: true, lastAction: '打开 BottomSheet' };
  },

  closeSheet() {
    return { showSheet: false, lastAction: '关闭 BottomSheet' };
  },
});
