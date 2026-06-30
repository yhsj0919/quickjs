import {
  Column,
  ElevatedButton,
  Page,
  Text,
} from 'quickjs_ui';

/**
 * @typedef {Object} CounterProps
 * @property {string=} title
 * @property {number=} initialCount
 *
 * @typedef {Object} CounterState
 * @property {number} count
 */

export default Page({
  name: 'CounterPage',

  props: {
    title: 'string',
    initialCount: 'number'
  },

  /** @param {CounterProps} props @returns {CounterState} */
  createState(props) {
    return { count: props.initialCount ?? 0 };
  },

  /**
   * @param {CounterState} state
   * @param {CounterProps} props
   */
  build(state, props, page) {
    return Column({
      mainAxisAlignment: 'center',
      crossAxisAlignment: 'center',
      children: [
        Text(`${props.title ?? 'Counter'}: ${state.count}`, {
          style: { fontSize: 20, fontWeight: 'bold' }
        }),
        ElevatedButton({
          child: Text('Increment'),
          onPressed: page.increment()
        })
      ]
    });
  },

  /** @param {CounterState} state @returns {CounterState} */
  increment(state) {
    return { ...state, count: state.count + 1 };
  }
});
