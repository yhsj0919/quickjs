import { Column, Container, ElevatedButton, Page, Text } from 'quickjs_ui';

function describe(value) {
  if (value === undefined) {
    return 'undefined';
  }
  try {
    return JSON.stringify(value);
  } catch (_) {
    return String(value);
  }
}

export default Page({
  name: 'quickjs-ui-navigation-detail',

  createState() {
    return {
      result: '等待原生页面返回'
    };
  },

  build(state, props, page) {
    return Column({
      padding: 16,
      crossAxisAlignment: 'stretch',
      gap: 12,
      children: [
        Text('JSUI 详情页', {
          style: { fontSize: 22, fontWeight: 'w700' }
        }),
        Text(`itemId: ${props.itemId ?? 'none'}`),
        Text(`title: ${props.title ?? 'none'}`),
        Container({
          padding: 12,
          decoration: {
            color: '$surfaceContainerHighest',
            borderRadius: 8
          },
          child: Text(`route result: ${state.result}`)
        }),
        ElevatedButton({
          child: Text('打开原生设置页'),
          onPressed: page.openNativeSettings()
        }),
        ElevatedButton({
          child: Text('打开未注册页面'),
          onPressed: page.openMissingRoute()
        }),
        ElevatedButton({
          child: Text('返回原生列表页'),
          onPressed: page.popToNativeList()
        })
      ]
    });
  },

  async openNativeSettings(state, _payload, props) {
    const result = await quickjsUiHost.navigationIntent({
      route: 'quickjs-ui.navigation.settings',
      params: {
        source: 'jsui-detail',
        itemId: props.itemId,
        title: props.title
      }
    });
    return {
      ...state,
      result: describe(result)
    };
  },

  async openMissingRoute(state) {
    try {
      await quickjsUiHost.navigationIntent({
        route: 'quickjs-ui.navigation.missing',
        params: { source: 'jsui-detail' }
      });
      return {
        ...state,
        result: 'missing route unexpectedly opened'
      };
    } catch (error) {
      return {
        ...state,
        result: `missing route rejected: ${error?.message ?? String(error)}`
      };
    }
  },

  popToNativeList(state, _payload, props) {
    return quickjsUiNavigation.pop({
      from: 'jsui-detail',
      itemId: props.itemId,
      title: props.title
    });
  }
});
