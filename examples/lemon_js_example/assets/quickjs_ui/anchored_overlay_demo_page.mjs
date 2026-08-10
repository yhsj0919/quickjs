import { AnchoredOverlay, Column, Container, ElevatedButton, ListView, Page, Row, SizedBox, Text } from 'quickjs_ui';

const panel = (title, detail) => Container({
  padding: 14,
  decoration: {
    color: '#ffffff',
    borderRadius: 14,
    border: { color: '#dbe5f0', width: 1 },
    boxShadow: { color: '#220f172a', offset: { x: 0, y: 8 }, blurRadius: 20 }
  },
  child: Column({ gap: 5, children: [
    Text(title, { style: { color: '#0f172a', fontSize: 16, fontWeight: 'w700' } }),
    Text(detail, { style: { color: '#64748b', fontSize: 12 } })
  ] })
});

export default Page({
  name: 'AnchoredOverlayDemo',
  createState() {
    return { dropdownOpen: false, directionOpen: false, tooltipOpen: false, followOpen: false, placement: 'bottomStart' };
  },
  toggleDropdown: (state) => ({ dropdownOpen: !state.dropdownOpen }),
  closeDropdown: () => ({ dropdownOpen: false }),
  toggleDirection: (state) => ({ directionOpen: !state.directionOpen }),
  closeDirection: () => ({ directionOpen: false }),
  setPlacement: (state, data) => ({ placement: data.placement, directionOpen: true }),
  showTooltip: () => ({ tooltipOpen: true }),
  hideTooltip: () => ({ tooltipOpen: false }),
  toggleFollow: (state) => ({ followOpen: !state.followOpen }),
  closeFollow: () => ({ followOpen: false }),
  build(state, props, actions) {
    return Container({ color: '#f4f7fb', child: ListView({
      padding: { left: 18, top: 18, right: 18, bottom: 80 }, gap: 24,
      children: [
        Text('锚点浮层', { style: { fontSize: 28, fontWeight: 'w800' } }),
        AnchoredOverlay({
          visible: state.dropdownOpen, placement: 'bottomStart', gap: 8,
          matchAnchorWidth: true, consumeOutsideTap: true,
          onDismissed: actions.closeDropdown(),
          anchor: ElevatedButton({ onPressed: actions.toggleDropdown(), child: Text('匹配锚点宽度') }),
          overlay: panel('下拉面板', '浮层宽度与按钮一致，并自动避开屏幕边缘。')
        }),
        Column({ gap: 10, children: [
          Row({ gap: 8, children: ['topStart', 'bottomStart', 'bottomEnd'].map((placement) =>
            ElevatedButton({ onPressed: actions.setPlacement({ placement }), child: Text(placement) })) }),
          AnchoredOverlay({
            visible: state.directionOpen, placement: state.placement,
            offset: { x: 6, y: 8 }, screenPadding: 12,
            onDismissed: actions.closeDirection(),
            anchor: ElevatedButton({ onPressed: actions.toggleDirection(), child: Text(`当前方向：${state.placement}`) }),
            overlay: panel('方向与偏移', 'placement、offset 和 screenPadding 共同控制定位。')
          })
        ] }),
        AnchoredOverlay({
          visible: state.tooltipOpen, placement: 'top', gap: 6, animated: true,
          anchor: Container({
            width: 190, padding: 12, mouseCursor: 'pointer',
            onMouseEnter: actions.showTooltip(), onMouseExit: actions.hideTooltip(),
            decoration: { color: '#dbeafe', borderRadius: 12, border: { color: '#93c5fd', width: 1 } },
            child: Text('悬停显示提示', { textAlign: 'center' })
          }),
          overlay: Container({ padding: 8, decoration: { color: '#0f172a', borderRadius: 8 }, child: Text('系统 Overlay 中的提示', { style: { color: '#ffffff' } }) })
        }),
        SizedBox({ height: 180 }),
        AnchoredOverlay({
          visible: state.followOpen, placement: 'bottomEnd', gap: 8,
          useRootOverlay: true, dismissOnTapOutside: false,
          onDismissed: actions.closeFollow(),
          anchor: ElevatedButton({ onPressed: actions.toggleFollow(), child: Text('打开后滚动页面') }),
          overlay: panel('正在跟随', '滚动时浮层持续附着在锚点上。')
        })
      ]
    }) });
  }
});
