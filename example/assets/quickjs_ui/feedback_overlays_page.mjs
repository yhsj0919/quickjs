import {
  AlertDialog,
  AnimatedAlign,
  AnimatedSwitcher,
  BottomSheet,
  CircularProgressIndicator,
  Column,
  Container,
  Expanded,
  LinearProgressIndicator,
  ListView,
  OutlinedButton,
  Page,
  Row,
  SafeArea,
  SnackBar,
  Text,
  TextButton,
  Wrap,
} from 'quickjs_ui';

function panel(child) {
  return Container({
    margin: { bottom: 12 },
    padding: { all: 16 },
    decoration: {
      color: '$surface',
      borderRadius: 16,
      border: { color: '$outline', width: 1 },
    },
    child,
  });
}

export default Page({
  name: 'FeedbackOverlaysDemo',

  createState() {
    return {
      progress: 0.42,
      alignEnd: false,
      switcherOn: true,
      snackToken: 0,
      showDialog: false,
      showSheet: false,
    };
  },

  build(state, _props, page) {
    return ListView({
      padding: { all: 16 },
      children: [
        Text('反馈、进度与浮层', { style: { fontSize: 24, fontWeight: 'w800' } }),
        Text('每个按钮只验证一种反馈能力，Dialog 与 BottomSheet 使用系统浮层。', {
          style: { color: '$outline', fontSize: 13 },
        }),
        Container({ height: 16 }),
        panel(Column({
          crossAxisAlignment: 'stretch',
          gap: 14,
          children: [
            LinearProgressIndicator({ value: state.progress }),
            Row({
              children: [
                CircularProgressIndicator({}),
                Container({ width: 16 }),
                Expanded({ child: Text(`当前进度：${Math.round(state.progress * 100)}%`) }),
                TextButton({ label: '增加', onPressed: page.advance() }),
              ],
            }),
          ],
        })),
        panel(Column({
          crossAxisAlignment: 'stretch',
          gap: 12,
          children: [
            AnimatedAlign({
              alignment: state.alignEnd ? 'centerRight' : 'centerLeft',
              durationMs: 240,
              animationCurve: 'easeOut',
              child: Container({
                padding: { horizontal: 14, vertical: 8 },
                decoration: { color: '$primary', borderRadius: 999 },
                child: Text('AnimatedAlign', { style: { color: '$onPrimary' } }),
              }),
            }),
            AnimatedSwitcher({
              durationMs: 220,
              child: Container({
                key: state.switcherOn ? 'success' : 'warning',
                padding: { all: 12 },
                decoration: {
                  color: state.switcherOn ? '#dcfce7' : '#fee2e2',
                  borderRadius: 12,
                },
                child: Text(state.switcherOn ? 'Switcher：成功状态' : 'Switcher：警示状态'),
              }),
            }),
            Row({
              children: [
                Expanded({ child: TextButton({ label: '移动', onPressed: page.toggleAlign() }) }),
                Expanded({ child: TextButton({ label: '切换', onPressed: page.toggleSwitcher() }) }),
              ],
            }),
          ],
        })),
        panel(Wrap({
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton({ label: 'SnackBar', onPressed: page.openSnack() }),
            OutlinedButton({ label: 'Dialog', onPressed: page.openDialog() }),
            OutlinedButton({ label: 'BottomSheet', onPressed: page.openSheet() }),
          ],
        })),
        SnackBar({
          visible: state.snackToken > 0,
          content: `已触发 SnackBar #${state.snackToken}`,
          durationMs: 2200,
        }),
        AlertDialog({
          visible: state.showDialog,
          onClosing: page.closeDialog(),
          titleText: '系统 Dialog',
          contentText: 'Dialog 不参与列表布局，也不会撑满页面。',
          actions: [TextButton({ label: '关闭', onPressed: page.closeDialog() })],
        }),
        BottomSheet({
          visible: state.showSheet,
          onClosing: page.closeSheet(),
          child: SafeArea({
            child: Container({
              padding: { all: 20 },
              child: Column({
                crossAxisAlignment: 'stretch',
                gap: 12,
                children: [
                  Text('BottomSheet', { style: { fontSize: 18, fontWeight: 'w800' } }),
                  Text('内容高度由自身决定。'),
                  OutlinedButton({ label: '关闭', onPressed: page.closeSheet() }),
                ],
              }),
            }),
          }),
        }),
      ],
    });
  },

  advance(state) {
    return { progress: state.progress >= 0.92 ? 0.12 : state.progress + 0.1 };
  },
  toggleAlign(state) {
    return { alignEnd: !state.alignEnd };
  },
  toggleSwitcher(state) {
    return { switcherOn: !state.switcherOn };
  },
  openSnack(state) {
    return { snackToken: state.snackToken + 1 };
  },
  openDialog() {
    return { showDialog: true };
  },
  closeDialog() {
    return { showDialog: false };
  },
  openSheet() {
    return { showSheet: true };
  },
  closeSheet() {
    return { showSheet: false };
  },
});
