import { Column, ElevatedButton, Page, Padding } from 'quickjs_ui';

export default Page({
  name: 'DiffRefreshPage',

  createState() {
    return {
      version: 0,
    };
  },

  build(state, props, page) {
    return Column({
      crossAxisAlignment: 'stretch',
      children: [
        {
          type: 'Probe',
          key: 'stable-probe',
          id: 'stable',
          label: 'Stable keyed node from JS',
          color: '$secondaryContainer',
        },
        Padding({
          padding: { top: 8 },
          child: {
            type: 'Probe',
            key: 'changed-probe',
            id: 'changed',
            label: `Changed keyed node from JS #${state.version}`,
            color: '$primaryContainer',
          },
        }),
        Padding({
          padding: { top: 12 },
          child: ElevatedButton({
            onPressed: page.bump(),
            child: {
              type: 'Text',
              data: 'Refresh changed node',
            },
          }),
        }),
      ],
    });
  },

  bump(state) {
    return {
      ...state,
      version: state.version + 1,
    };
  },
});
