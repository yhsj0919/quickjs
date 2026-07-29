import {
  AnchoredOverlay,
  Column,
  Container,
  ElevatedButton,
  ListView,
  Page,
  Row,
  SizedBox,
  Text,
  TextField,
  Wrap,
} from 'quickjs_ui';

const panel = (title, detail) => Container({
  padding: 14,
  decoration: {
    color: '#ffffff',
    borderRadius: 14,
    border: { color: '#dbe5f0', width: 1 },
    boxShadow: {
      color: '#220f172a',
      offset: { x: 0, y: 8 },
      blurRadius: 20,
    },
  },
  child: Column({
    gap: 5,
    children: [
      Text(title, { style: { color: '#0f172a', fontSize: 16, fontWeight: 'w700' } }),
      Text(detail, { style: { color: '#64748b', fontSize: 12, height: 1.35 } }),
    ],
  }),
});

export default Page({
  name: 'AnchoredOverlayDemo',
  createState() {
    return {
      dropdownOpen: false,
      directionOpen: false,
      tooltipOpen: false,
      followOpen: false,
      placement: 'bottomStart',
      mouseStatus: '等待鼠标进入',
      pointerStatus: '等待指针操作',
      keyboardStatus: '点击输入框后按键',
      inputValue: '',
    };
  },
  toggleDropdown(state) {
    return { dropdownOpen: !state.dropdownOpen };
  },
  closeDropdown() {
    return { dropdownOpen: false };
  },
  toggleDirection(state) {
    return { directionOpen: !state.directionOpen };
  },
  closeDirection() {
    return { directionOpen: false };
  },
  setPlacement(state, data) {
    return { placement: data.placement, directionOpen: true };
  },
  showTooltip() {
    return { tooltipOpen: true };
  },
  hideTooltip() {
    return { tooltipOpen: false };
  },
  toggleFollow(state) {
    return { followOpen: !state.followOpen };
  },
  closeFollow() {
    return { followOpen: false };
  },
  mouseEnter() {
    return { mouseStatus: '鼠标已进入' };
  },
  mouseExit() {
    return { mouseStatus: '鼠标已移出' };
  },
  mouseHover(state, data) {
    return {
      mouseStatus: `悬停坐标 ${Math.round(data.localX || 0)}, ${Math.round(data.localY || 0)}`,
    };
  },
  mouseScroll(state, data) {
    return { mouseStatus: `滚轮 ΔY ${Math.round(data.scrollDeltaY || 0)}` };
  },
  pointerDown(state, data) {
    return { pointerStatus: `指针按下 · ${data.kind || 'unknown'} · buttons ${data.buttons || 0}` };
  },
  pointerMove(state, data) {
    return {
      pointerStatus: `指针移动 ${Math.round(data.localX || 0)}, ${Math.round(data.localY || 0)}`,
    };
  },
  pointerUp() {
    return { pointerStatus: '指针抬起' };
  },
  pointerCancel() {
    return { pointerStatus: '指针操作已取消' };
  },
  inputChanged(state, data) {
    return { inputValue: data.value || '' };
  },
  inputFocused() {
    return { keyboardStatus: '输入框已获得焦点' };
  },
  inputBlurred() {
    return { keyboardStatus: '输入框已失去焦点' };
  },
  keyDown(state, data) {
    return { keyboardStatus: `按下按键：${data.key || data.keyId || '未知'}` };
  },
  keyUp(state, data) {
    return { keyboardStatus: `释放按键：${data.key || data.keyId || '未知'}` };
  },
  build(state, props, actions) {
    return Container({
      color: '#f4f7fb',
      child: ListView({
        physics: 'bouncing',
        scrollbar: true,
        padding: { left: 18, top: 18, right: 18, bottom: 80 },
        gap: 22,
        children: [
          Column({
            gap: 5,
            children: [
              Text('UI 基础能力', {
                style: { color: '#0f172a', fontSize: 28, fontWeight: 'w800' },
              }),
              Text('渐变与阴影 · 鼠标与指针 · 焦点键盘 · 原生锚点浮层', {
                style: { color: '#64748b', fontSize: 13 },
              }),
            ],
          }),

          Column({
            gap: 10,
            children: [
              Text('渐变、阴影与偏移', { style: { fontSize: 17, fontWeight: 'w700' } }),
              Container({
                height: 150,
                minWidth: 260,
                maxWidth: 560,
                padding: 18,
                translate: { x: 4, y: -2 },
                rotate: -0.012,
                decoration: {
                  gradient: {
                    type: 'linear',
                    colors: ['#2563eb', '#7c3aed', '#ec4899'],
                    stops: [0, 0.55, 1],
                    begin: 'topLeft',
                    end: 'bottomRight',
                  },
                  borderRadius: 22,
                  border: {
                    left: { color: '#bfdbfe', width: 3 },
                    top: { color: '#ddd6fe', width: 1 },
                    right: { color: '#fbcfe8', width: 3 },
                    bottom: { color: '#f5d0fe', width: 5 },
                  },
                  boxShadow: [
                    { color: '#552563eb', offset: { x: 8, y: 14 }, blurRadius: 24, spreadRadius: 2 },
                    { color: '#33ec4899', offset: { x: -5, y: 3 }, blurRadius: 12 },
                  ],
                },
                child: Column({
                  gap: 8,
                  children: [
                    Text('系统绘制的线性渐变', {
                      style: { color: '#ffffff', fontSize: 20, fontWeight: 'w800' },
                    }),
                    Text('三色 stops、起止方向、双层阴影、阴影偏移、分边边框、约束和轻微变换同时生效。', {
                      maxLines: 2,
                      overflow: 'ellipsis',
                      style: { color: '#eef2ff', fontSize: 13, height: 1.35 },
                    }),
                  ],
                }),
              }),
              Wrap({
                spacing: 12,
                runSpacing: 10,
                children: [
                  Container({
                    width: 74,
                    height: 74,
                    decoration: {
                      shape: 'circle',
                      gradient: {
                        type: 'radial',
                        colors: ['#fef3c7', '#f59e0b', '#b45309'],
                        stops: [0, 0.62, 1],
                        center: 'topLeft',
                        radius: 0.9,
                      },
                      boxShadow: { color: '#55f59e0b', offset: { x: 3, y: 7 }, blurRadius: 12 },
                    },
                  }),
                  Container({
                    width: 190,
                    padding: 12,
                    decoration: {
                      gradient: {
                        type: 'linear',
                        colors: ['#06b6d4', '#6366f1', '#8b5cf6'],
                        begin: 'centerLeft',
                        end: 'centerRight',
                      },
                      borderRadius: 14,
                    },
                    child: Text('径向渐变 · 横向渐变', {
                      textAlign: 'center',
                      style: { color: '#ffffff', fontWeight: 'w700' },
                    }),
                  }),
                ],
              }),
            ],
          }),

          Column({
            gap: 10,
            children: [
              Text('鼠标与原始指针事件', { style: { fontSize: 17, fontWeight: 'w700' } }),
              Container({
                height: 150,
                padding: 16,
                mouseCursor: 'move',
                onMouseEnter: actions.mouseEnter(),
                onMouseExit: actions.mouseExit(),
                onMouseHover: actions.mouseHover(),
                onMouseScroll: actions.mouseScroll(),
                onPointerDown: actions.pointerDown(),
                onPointerMove: actions.pointerMove(),
                onPointerUp: actions.pointerUp(),
                onPointerCancel: actions.pointerCancel(),
                decoration: {
                  color: '#ecfeff',
                  borderRadius: 16,
                  border: { color: '#67e8f9', width: 1.5 },
                },
                child: Column({
                  gap: 8,
                  children: [
                    Text('在此区域移动、滚轮或按下鼠标', {
                      style: { color: '#155e75', fontWeight: 'w700' },
                    }),
                    Text(state.mouseStatus, { style: { color: '#0e7490', fontSize: 13 } }),
                    Text(state.pointerStatus, { style: { color: '#0f766e', fontSize: 13 } }),
                  ],
                }),
              }),
            ],
          }),

          Column({
            gap: 10,
            children: [
              Text('焦点与键盘事件', { style: { fontSize: 17, fontWeight: 'w700' } }),
              Container({
                onKeyDown: actions.keyDown(),
                onKeyUp: actions.keyUp(),
                child: TextField({
                  value: state.inputValue,
                  labelText: '输入或按任意键',
                  onChanged: actions.inputChanged(),
                  onFocus: actions.inputFocused(),
                  onBlur: actions.inputBlurred(),
                }),
              }),
              Text(state.keyboardStatus, { style: { color: '#475569', fontSize: 13 } }),
            ],
          }),

          Column({
            gap: 10,
            children: [
              Text('匹配锚点宽度', { style: { fontSize: 17, fontWeight: 'w700' } }),
              AnchoredOverlay({
                visible: state.dropdownOpen,
                placement: 'bottomStart',
                gap: 8,
                matchAnchorWidth: true,
                consumeOutsideTap: true,
                onDismissed: actions.closeDropdown(),
                anchor: ElevatedButton({
                  onPressed: actions.toggleDropdown(),
                  child: Text(state.dropdownOpen ? '关闭下拉面板' : '打开下拉面板'),
                }),
                overlay: panel('账户操作', '浮层宽度与按钮一致，并在靠近屏幕边缘时自动调整。'),
              }),
            ],
          }),

          Column({
            gap: 10,
            children: [
              Text('方向与偏移', { style: { fontSize: 17, fontWeight: 'w700' } }),
              Row({
                gap: 8,
                children: ['topStart', 'bottomStart', 'bottomEnd'].map((placement) =>
                  ElevatedButton({
                    onPressed: actions.setPlacement({ placement }),
                    child: Text(placement),
                  })
                ),
              }),
              AnchoredOverlay({
                visible: state.directionOpen,
                placement: state.placement,
                offset: { x: 6, y: 8 },
                screenPadding: 12,
                onDismissed: actions.closeDirection(),
                anchor: ElevatedButton({
                  onPressed: actions.toggleDirection(),
                  child: Text(`当前方向：${state.placement}`),
                }),
                overlay: panel('方向浮层', '通过 placement、offset 和 screenPadding 控制定位。'),
              }),
            ],
          }),

          Column({
            gap: 10,
            children: [
              Text('鼠标悬停提示', { style: { fontSize: 17, fontWeight: 'w700' } }),
              AnchoredOverlay({
                visible: state.tooltipOpen,
                placement: 'top',
                gap: 6,
                animated: true,
                anchor: Container({
                  width: 190,
                  padding: 12,
                  mouseCursor: 'pointer',
                  onMouseEnter: actions.showTooltip(),
                  onMouseExit: actions.hideTooltip(),
                  decoration: {
                    color: '#dbeafe',
                    borderRadius: 12,
                    border: { color: '#93c5fd', width: 1 },
                  },
                  child: Text('把鼠标移到这里', {
                    textAlign: 'center',
                    style: { color: '#1d4ed8', fontWeight: 'w700' },
                  }),
                }),
                overlay: Container({
                  padding: { horizontal: 10, vertical: 7 },
                  decoration: { color: '#0f172a', borderRadius: 8 },
                  child: Text('这是系统浮层中的悬停提示', {
                    style: { color: '#ffffff', fontSize: 12 },
                  }),
                }),
              }),
            ],
          }),

          SizedBox({ height: 170 }),

          Column({
            gap: 10,
            children: [
              Text('滚动时跟随锚点', { style: { fontSize: 17, fontWeight: 'w700' } }),
              AnchoredOverlay({
                visible: state.followOpen,
                placement: 'bottomEnd',
                gap: 8,
                useRootOverlay: true,
                dismissOnTapOutside: false,
                onDismissed: actions.closeFollow(),
                anchor: ElevatedButton({
                  onPressed: actions.toggleFollow(),
                  child: Text('打开后滚动页面'),
                }),
                overlay: panel('正在跟随', '滚动列表时，浮层保持附着在这个按钮上。'),
              }),
            ],
          }),
        ],
      }),
    });
  },
});
