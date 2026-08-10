import { Column, Container, ElevatedButton, Page, Text } from 'quickjs_ui';
import { PackageSummary } from './components/package_summary.mjs';

export default Page({
  name: 'PackageDemoPage',

  createState() {
    return {
      reloads: 0,
      status: 'asset package loaded'
    };
  },

  build(state, props, actions) {
    return Container({
      padding: { all: 16 },
      child: Column({
        crossAxisAlignment: 'stretch',
        gap: 12,
        children: [
          Text('QuickJS UI Package Demo', {
            style: { fontSize: 20, fontWeight: 'bold' }
          }),
          PackageSummary({
            id: props.packageId,
            version: props.packageVersion,
            modules: props.moduleCount,
            resources: props.resourceCount
          }),
          Text(`status: ${state.status}`),
          Text(`reloads: ${state.reloads}`),
          ElevatedButton({
            onPressed: actions.reload(),
            child: Text('Reload state')
          })
        ]
      })
    });
  },

  reload(state) {
    return {
      reloads: state.reloads + 1,
      status: `reloaded ${state.reloads + 1}`
    };
  }
});
