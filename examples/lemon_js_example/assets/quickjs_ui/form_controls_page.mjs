import {
  Checkbox,
  Column,
  Container,
  DropdownButton,
  Expanded,
  OutlinedButton,
  Page,
  Row,
  SingleChildScrollView,
  Slider,
  SnackBar,
  Switch,
  Text,
  TextButton,
} from 'quickjs_ui';

function panel(child, color = '$surface') {
  return Container({
    margin: { bottom: 12 },
    padding: { all: 16 },
    decoration: {
      color,
      borderRadius: 16,
      border: { color: '$outline', width: 1 },
    },
    child,
  });
}

export default Page({
  name: 'FormControlsDemo',

  createState() {
    return {
      accepted: true,
      darkPreview: false,
      opacity: 0.8,
      priority: 'normal',
      saveToken: 0,
    };
  },

  build(state, _props, page) {
    return SingleChildScrollView({
      padding: { all: 16 },
      children: [
        Text('表单控件', { style: { fontSize: 24, fontWeight: 'w800' } }),
        Text('Checkbox、Switch、Slider 和 DropdownButton 共享一份 JS 状态。', {
          style: { color: '$outline', fontSize: 13 },
        }),
        Container({ height: 16 }),
        panel(Column({
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
        })),
        panel(Column({
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
        }), state.darkPreview ? '#111827' : '#f8fafc'),
        Row({
          children: [
            Expanded({ child: OutlinedButton({ label: '重置', onPressed: page.reset() }) }),
            Container({ width: 8 }),
            Expanded({ child: TextButton({ label: '保存', onPressed: page.save() }) }),
          ],
        }),
        SnackBar({
          visible: state.saveToken > 0,
          content: `表单已保存 #${state.saveToken}`,
          durationMs: 2200,
        }),
      ],
    });
  },

  setAccepted(_state, _payload, _props, event) {
    return { accepted: event.value === true };
  },
  setDarkPreview(_state, _payload, _props, event) {
    return { darkPreview: event.value === true };
  },
  setOpacity(state, _payload, _props, event) {
    return { opacity: event.value ?? state.opacity };
  },
  setPriority(_state, _payload, _props, event) {
    return { priority: event.value ?? 'normal' };
  },
  reset() {
    return { accepted: true, darkPreview: false, opacity: 0.8, priority: 'normal' };
  },
  save(state) {
    return { saveToken: state.saveToken + 1 };
  },
});
