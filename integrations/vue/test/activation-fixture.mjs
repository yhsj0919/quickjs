import { Page, Text } from 'quickjs_ui';

// Browser regression fixture: activation must happen after mount, without
// overwriting playing first, and once per active period.
export default Page({
  createState() { return { mounted: false, playing: false, activations: 0 }; },
  onMount() { return { mounted: true }; },
  onPageWillActive(state) {
    if (!state.mounted) throw new Error('Activated before mount');
    if (state.playing) throw new Error('Activation duplicated or playing preset');
    return { playing: true, activations: state.activations + 1 };
  },
  assertActivation(state, data) {
    if (state.activations !== data.count || state.playing !== data.playing) {
      throw new Error(`Expected ${data.count}/${data.playing}, got ${state.activations}/${state.playing}`);
    }
  },
  build(state) { return Text(`mounted=${state.mounted}; activations=${state.activations}; playing=${state.playing}`); },
});
