import {
  Column,
  Container,
  ElevatedButton,
  ListView,
  Page,
  Text
} from 'quickjs_ui';

function hostKeys() {
  const host = globalThis.quickjsUiHost;
  if (!host) {
    return [];
  }
  return Object.keys(host).sort();
}

function appKeys() {
  const app = globalThis.quickjsUiApp;
  if (!app) {
    return [];
  }
  return Object.keys(app).sort();
}

function describe(value) {
  if (value === undefined) {
    return 'undefined';
  }
  if (typeof value === 'string') {
    return value;
  }
  try {
    return JSON.stringify(value);
  } catch (_) {
    return String(value);
  }
}

function appendCall(state, message) {
  return {
    ...state,
    keys: hostKeys(),
    appKeys: appKeys(),
    calls: [message, ...state.calls].slice(0, 8)
  };
}

export default Page({
  name: 'quickjs-ui-host-capabilities',

  createState() {
    return {
      keys: hostKeys(),
      appKeys: appKeys(),
      lifecycleEvents: [],
      calls: []
    };
  },

  build(state, props, page) {
    const keys = state.keys.length ? state.keys.join(', ') : '无';
    const app = state.appKeys.length ? state.appKeys.join(', ') : '无';
    const methods = (props.methods ?? []).length ? props.methods.join(', ') : '无';
    const callText = state.calls.length ? state.calls.join('\n') : '还没有 JS 调用记录';
    const lifecycleText = state.lifecycleEvents.length
      ? state.lifecycleEvents.join(' → ')
      : '等待 mount';

    return ListView({
      padding: 16,
      gap: 12,
      children: [
        Text('宿主能力', {
          style: { fontSize: 22, fontWeight: 'w700' }
        }),
        Text(`已挂载 API：${keys}`),
        Text(`自定义应用 API：${app}`),
        Text(`声明方法：${methods}`),
        Text(`生命周期：${lifecycleText}`),
        Container({
          padding: 12,
          decoration: {
            color: '$surface',
            borderRadius: 8,
            border: { color: '$outline', width: 1 }
          },
          child: Column({
            crossAxisAlignment: 'stretch',
            gap: 8,
            children: [
              Text('从 JS 页面调用宿主 API', { style: { fontWeight: 'w700' } }),
              ElevatedButton({
                child: Text('调用 toast'),
                onPressed: page.callToast()
              }),
              ElevatedButton({
                child: Text('调用 confirm'),
                onPressed: page.callConfirm()
              }),
              ElevatedButton({
                child: Text('调用 storage'),
                onPressed: page.callStorage()
              }),
              ElevatedButton({
                child: Text('调用 nativeCall'),
                onPressed: page.callNative()
              }),
              ElevatedButton({
                child: Text('调用 dialog'),
                onPressed: page.callDialog()
              }),
              ElevatedButton({
                child: Text('调用 snackbar'),
                onPressed: page.callSnackbar()
              }),
              ElevatedButton({
                child: Text('调用 bottom sheet'),
                onPressed: page.callBottomSheet()
              }),
              ElevatedButton({
                child: Text('调用自定义能力'),
                onPressed: page.callCustomEcho()
              }),
              ElevatedButton({
                child: Text('调用 add(20, 22)'),
                onPressed: page.callAdd()
              }),
              ElevatedButton({
                child: Text('调用 navigationIntent'),
                onPressed: page.callNavigation()
              }),
              ElevatedButton({
                child: Text('检查 network 默认关闭'),
                onPressed: page.checkNetwork()
              })
            ]
          })
        }),
        Container({
          padding: 12,
          decoration: {
            color: '$surfaceContainerHighest',
            borderRadius: 8
          },
          child: Column({
            crossAxisAlignment: 'stretch',
            gap: 8,
            children: [
              Text('JS 状态日志', { style: { fontWeight: 'w700' } }),
              Text(callText)
            ]
          })
        }),
        ElevatedButton({
          child: Text('记录已挂载 API'),
          onPressed: page.recordKeys()
        }),
        Text(
          '宿主 API 调用由异步 provider 提供。此页面的按钮都在 JS 页面内声明并调用 quickjsUiHost / quickjsUiApp；Flutter 外壳只负责注册能力、处理 provider、展示 snackbar/dialog/bottom sheet，并维护 route registry。navigationIntent 只允许进入 route registry 中注册过的页面。'
        )
      ]
    });
  },

  async callToast(state) {
    const result = await quickjsUiHost.toast('Hello from JS page', {
      source: 'mjs'
    });
    return appendCall(state, `quickjsUiHost.toast => ${describe(result)}`);
  },

  async callConfirm(state) {
    const result = await quickjsUiHost.confirm('确认启用宿主能力？');
    return appendCall(state, `quickjsUiHost.confirm => ${describe(result)}`);
  },

  async callStorage(state) {
    await quickjsUiHost.storage.setItem('demo', 'stored-from-js');
    const result = await quickjsUiHost.storage.getItem('demo');
    return appendCall(state, `quickjsUiHost.storage => ${describe(result)}`);
  },

  async callNative(state) {
    const result = await quickjsUiHost.nativeCall('example.echo', {
      value: 42,
      source: 'mjs'
    });
    return appendCall(state, `quickjsUiHost.nativeCall => ${describe(result)}`);
  },

  async callDialog(state) {
    const result = await quickjsUiHost.dialog({
      title: '来自 JS 的 Dialog',
      content: Column({
        crossAxisAlignment: 'stretch',
        gap: 8,
        children: [
          Text('这是 JS 传入的自定义 dialog 内容。'),
          Text('content 使用 quickjs_ui schema，由宿主 Dialog 渲染。', {
            style: { color: '$primary', fontWeight: 'w700' }
          })
        ]
      })
    });
    return appendCall(state, `quickjsUiHost.dialog => ${describe(result)}`);
  },

  async callSnackbar(state) {
    const result = await quickjsUiHost.snackbar({
      message: '这是 JS 通过 quickjsUiHost.snackbar 打开的 SnackBar'
    });
    return appendCall(state, `quickjsUiHost.snackbar => ${describe(result)}`);
  },

  async callBottomSheet(state) {
    const result = await quickjsUiHost.bottomSheet({
      title: '来自 JS 的 BottomSheet',
      content: Column({
        crossAxisAlignment: 'stretch',
        gap: 8,
        children: [
          Text('这是 JS 通过 quickjsUiHost.bottomSheet 打开的宿主 bottom sheet。'),
          Text('bottomSheet 也可以传入自定义 quickjs_ui 内容。', {
            style: { color: '$secondary', fontWeight: 'w700' }
          })
        ]
      })
    });
    return appendCall(state, `quickjsUiHost.bottomSheet => ${describe(result)}`);
  },

  async callCustomEcho(state) {
    const result = await quickjsUiApp.customEcho('custom capability from JS');
    return appendCall(state, `quickjsUiApp.customEcho => ${describe(result)}`);
  },

  async callAdd(state) {
    const result = await quickjsUiApp.add(20, 22);
    return appendCall(state, `quickjsUiApp.add => ${describe(result)}`);
  },

  async callNavigation(state) {
    const result = await quickjsUiHost.navigationIntent({
      route: 'quickjs-ui.host-capabilities.detail',
      params: { source: 'mjs-page' }
    });
    return appendCall(
      state,
      `quickjsUiHost.navigationIntent => ${describe(result)}`
    );
  },

  checkNetwork(state) {
    return appendCall(state, `typeof quickjsUiHost.network => ${typeof quickjsUiHost.network}`);
  },

  recordKeys(state) {
    return appendCall(
      state,
      `quickjsUiHost => ${hostKeys().join(', ')} | quickjsUiApp => ${appKeys().join(', ')}`
    );
  },

  onMount(state, payload, props, event) {
    logLifecycle('mount', state, event);
    return appendLifecycle(state, 'mount');
  },

  onPause(state, payload, props, event) {
    logLifecycle('pause', state, event);
    return appendLifecycle(state, 'pause');
  },

  onResume(state, payload, props, event) {
    logLifecycle('resume', state, event);
    return appendLifecycle(state, 'resume');
  },

  onDispose(state, payload, props, event) {
    logLifecycle('dispose', state, event);
    return appendLifecycle(state, 'dispose');
  }
});

function appendLifecycle(state, event) {
  return {
    ...state,
    lifecycleEvents: [...state.lifecycleEvents, event].slice(-8)
  };
}

function logLifecycle(name, state, event) {
  console.log(
    `[quickjs_ui lifecycle] ${name}`,
    JSON.stringify({
      event,
      state
    })
  );
}
