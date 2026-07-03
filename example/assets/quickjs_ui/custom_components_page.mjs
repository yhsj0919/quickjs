import {
  Checkbox,
  Column,
  Component,
  Container,
  DropdownButton,
  ElevatedButton,
  Padding,
  Page,
  Switch,
  Text
} from 'quickjs_ui';

export const AppBar = Component((props) => ({
  type: 'AppBar',
  title: props.title,
  subtitle: props.subtitle,
  onBack: props.onBack
}));

export const Card = Component((props) => ({
  type: 'Card',
  tone: props.tone,
  child: Padding({
    padding: 16,
    child: props.child
  })
}));

export default Page({
  name: 'CustomComponentsPage',

  createState() {
    return {
      enabled: true,
      selectedSize: 'medium',
      expanded: false
    };
  },

  build(state, props, page) {
    return Column({
      gap: 12,
      children: [
        AppBar({
          title: props.title ?? 'Custom components',
          subtitle: 'JS schema + Dart renderer registry'
        }),
        Card({
          tone: state.enabled ? 'primary' : 'muted',
          child: Column({
            gap: 12,
            children: [
              Container({
                width: state.expanded ? 240 : 140,
                padding: 12,
                borderRadius: 8,
                color: state.enabled ? '#dbeafe' : '#eeeeee',
                animationDurationMs: 180,
                animationCurve: 'easeOut',
                child: Text(`Size: ${state.selectedSize}`)
              }),
              Checkbox({
                value: state.enabled,
                onChanged: page.setEnabled()
              }),
              Switch({
                value: state.expanded,
                onChanged: page.setExpanded()
              }),
              DropdownButton({
                value: state.selectedSize,
                onChanged: page.setSize(),
                items: [
                  { value: 'small', label: 'Small' },
                  { value: 'medium', label: 'Medium' },
                  { value: 'large', label: 'Large' }
                ]
              }),
              ElevatedButton({
                child: Text('Reset'),
                onPressed: page.reset()
              })
            ]
          })
        })
      ]
    });
  },

  setEnabled(state, _payload, _props, event) {
    return { ...state, enabled: event.value === true };
  },

  setExpanded(state, _payload, _props, event) {
    return { ...state, expanded: event.value === true };
  },

  setSize(state, _payload, _props, event) {
    return { ...state, selectedSize: event.value };
  },

  reset(state) {
    return { ...state, enabled: true, selectedSize: 'medium', expanded: false };
  }
});
