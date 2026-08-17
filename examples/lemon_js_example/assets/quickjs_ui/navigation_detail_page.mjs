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

function logLifecycle(hook, payload) {
  const message = `${hook}: ${describe(payload)}`;
  console.log(`[quickjs_ui route lifecycle] detail ${message}`);
}

export default Page({
  name: 'quickjs-ui-navigation-detail',

  createState() {
    return {
      count: 0,
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
        Text(`detail count: ${state.count}`),
        Container({
          padding: 12,
          decoration: {
            color: '$surfaceContainerHighest',
            borderRadius: 8
          },
          child: Text(`route result: ${state.result}`)
        }),
        ElevatedButton({
          child: Text('详情计数 +1'),
          onPressed: page.increment()
        }),
        ElevatedButton({
          child: Text('打开 JSUI 子页（slide 过渡）'),
          onPressed: page.openJsuiChild()
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
    const result = await jsUiNavigation.push({
      route: 'quickjs-ui.navigation.settings',
      transition: {
        type: 'slide',
        from: 'right',
        durationMs: 220,
        curve: 'easeOutCubic'
      },
      params: {
        source: 'jsui-detail',
        itemId: props.itemId,
        title: props.title
      }
    });
    return {
      result: describe(result)
    };
  },

  increment(state) {
    return {
      count: state.count + 1
    };
  },

  async openJsuiChild(state, _payload, props) {
    try {
      const result = await jsUiNavigation.push({
        route: 'quickjs-ui.navigation.child',
        path: './navigation_child_page.mjs',
        transition: {
          type: 'slide',
          beginOffset: { dx: 0.16, dy: 0 },
          fade: true,
          durationMs: 240,
          reverseDurationMs: 200,
          curve: 'easeOutCubic'
        },
        params: {
          source: 'jsui-detail',
          itemId: props.itemId,
          count: state.count
        }
      });
      return {
        result: describe(result)
      };
    } catch (error) {
      return {
        result: `jsui child rejected: ${error?.message ?? String(error)}`
      };
    }
  },

  async openMissingRoute(state) {
    try {
      await jsUiNavigation.push({
        route: 'quickjs-ui.navigation.missing',
        transition: {
          type: 'slide',
          beginOffset: { dx: 0.16, dy: 0 },
          fade: true,
          durationMs: 240,
          curve: 'easeOutCubic'
        },
        params: { source: 'jsui-detail' }
      });
      return {
        result: 'missing route unexpectedly opened'
      };
    } catch (error) {
      return {
        result: `missing route rejected: ${error?.message ?? String(error)}`
      };
    }
  },

  onRouteEnter(state, payload) {
    logLifecycle('onRouteEnter', payload);
  },

  onRouteLeave(state, payload) {
    logLifecycle('onRouteLeave', payload);
  },

  onRouteResult(state, payload) {
    logLifecycle('onRouteResult', payload);
    return {
      result: describe(payload?.result ?? payload)
    };
  },

  async popToNativeList(state, _payload, props) {
    await jsUiNavigation.pop({
      from: 'jsui-detail',
      itemId: props.itemId,
      title: props.title
    });
    return null;
  }
});
