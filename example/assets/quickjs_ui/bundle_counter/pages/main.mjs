import { Column, Page, Text } from 'quickjs_ui';
import { counterCard } from '../components/counter_card.mjs';

export default Page({
  name: 'BundleCounterPage',
  props: {
    title: 'string',
    initialCount: 'number'
  },

  createState(props) {
    return {
      count: props.initialCount ?? 0
    };
  },

  build(state, props, page) {
    return Column({
      mainAxisAlignment: 'center',
      crossAxisAlignment: 'center',
      children: [
        Text(props.title ?? 'Multi-file QuickJS UI', {
          style: {
            fontSize: 22,
            fontWeight: 'w700',
            color: '#263238'
          }
        }),
        counterCard({
          count: state.count,
          onIncrement: page.increment(),
          onReset: page.reset()
        })
      ]
    });
  },

  increment(state) {
    return {
      ...state,
      count: state.count + 1
    };
  },

  reset(state) {
    return {
      ...state,
      count: 0
    };
  }
});
