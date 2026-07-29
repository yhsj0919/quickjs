import { Column, Container, Page, Text, TextField } from 'quickjs_ui';

export default Page({
  name: 'PointerKeyboardEventsPage',
  createState() { return { mouse: '等待鼠标操作', pointer: '等待指针操作', keyboard: '点击输入框后按键', value: '' }; },
  mouseEnter: () => ({ mouse: '鼠标已进入' }),
  mouseExit: () => ({ mouse: '鼠标已移出' }),
  mouseHover: (state, data) => ({ mouse: `悬停坐标 ${Math.round(data.localX || 0)}, ${Math.round(data.localY || 0)}` }),
  mouseScroll: (state, data) => ({ mouse: `滚轮 ΔY ${Math.round(data.scrollDeltaY || 0)}` }),
  pointerDown: (state, data) => ({ pointer: `指针按下 · ${data.kind || 'unknown'} · buttons ${data.buttons || 0}` }),
  pointerMove: (state, data) => ({ pointer: `指针移动 ${Math.round(data.localX || 0)}, ${Math.round(data.localY || 0)}` }),
  pointerUp: () => ({ pointer: '指针抬起' }),
  pointerCancel: () => ({ pointer: '指针操作已取消' }),
  inputChanged: (state, data) => ({ value: data.value || '' }),
  inputFocused: () => ({ keyboard: '输入框已获得焦点' }),
  inputBlurred: () => ({ keyboard: '输入框已失去焦点' }),
  keyDown: (state, data) => ({ keyboard: `按下：${data.key || data.keyId || '未知'}` }),
  keyUp: (state, data) => ({ keyboard: `释放：${data.key || data.keyId || '未知'}` }),
  build(state, props, actions) {
    return Container({ color: '#f4f7fb', padding: 22, child: Column({ gap: 20, children: [
      Text('鼠标、指针与键盘事件', { style: { fontSize: 28, fontWeight: 'w800' } }),
      Container({
        height: 170, padding: 16, mouseCursor: 'move',
        onMouseEnter: actions.mouseEnter(), onMouseExit: actions.mouseExit(),
        onMouseHover: actions.mouseHover(), onMouseScroll: actions.mouseScroll(),
        onPointerDown: actions.pointerDown(), onPointerMove: actions.pointerMove(),
        onPointerUp: actions.pointerUp(), onPointerCancel: actions.pointerCancel(),
        decoration: { color: '#ecfeff', borderRadius: 16, border: { color: '#67e8f9', width: 1.5 } },
        child: Column({ gap: 10, children: [Text('在此区域移动、滚动或按下鼠标'), Text(state.mouse), Text(state.pointer)] })
      }),
      Container({
        onKeyDown: actions.keyDown(), onKeyUp: actions.keyUp(),
        child: TextField({ value: state.value, labelText: '输入或按任意键', onChanged: actions.inputChanged(), onFocus: actions.inputFocused(), onBlur: actions.inputBlurred() })
      }),
      Text(state.keyboard)
    ] }) });
  }
});
