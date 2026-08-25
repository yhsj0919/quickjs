# lemon_js_ui_webview

`lemon_js_ui_webview` 是与 `lemon_js_ui_video_player` 平级的独立 JSUI
插件。它基于 `webview_all` 提供 WebView 组件，并在 QuickJS、Flutter 宿主和网页
JavaScript 之间建立显式桥接。

主要能力：

- 加载 URL 或 HTML；
- 前进、后退、刷新、停止和动态加载页面；
- QuickJS 与网页 JavaScript 双向异步调用；
- 获取、写入、恢复和清理 Cookie；
- 类 jQuery 的链式 DOM 查询与修改规则；
- 向主文档及子 frame 注入 document-start 脚本；
- 每个插件实例独立管理 WebView bridge，不持有跨宿主的全局引用。

## 宿主接入

在宿主 Flutter 项目中显式添加并注册插件：

```yaml
dependencies:
  lemon_js: ^0.3.0
  lemon_js_ui: ^0.2.1
  lemon_js_ui_webview: ^0.1.0
```

```dart
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_ui_webview/lemon_js_ui_webview.dart';

final webViewPlugin = JsUiWebViewPlugin();

JsUiView.asset(
  path: 'assets/pages/webview_page.mjs',
  uiPlugins: <JsUiPlugin>[webViewPlugin.plugin],
);
```

宿主必须显式创建 `JsUiWebViewPlugin`。需要隔离的 `JsUiView` 应分别持有插件实例，
不要在多个宿主间共享实例。

Windows 当前固定使用 `webview_all` / `webview_all_windows 1.3.8`。`1.3.9`
在部分 Windows 10 环境中无法注册图形帧回调，会持续报告 WebView2 surface size
更新失败。升级前应先完成对应 Windows 环境回归。

## 最小页面

```js
import {WebView, createWebBridge} from 'quickjs_ui/webview';

const bridge = createWebBridge('main-webview');

export default WebView({
  bridge,
  url: 'https://example.com'
});
```

也可以直接加载 HTML：

```js
WebView({
  bridge,
  html: '<!doctype html><title>Local page</title><h1>Hello</h1>',
  baseUrl: 'https://example.com/'
});
```

## 双向调用

QuickJS 暴露方法给网页：

```js
bridge.expose('saveSession', async ({url}) => {
  const cookies = await bridge.getCookies(url);
  return {saved: true, cookies};
});
```

网页调用 QuickJS：

```js
const result = await window.quickjsHost.call('saveSession', {
  url: location.href
});
```

网页也可以暴露方法：

```js
window.quickjsHost.expose('pageSummary', () => ({
  title: document.title,
  url: location.href
}));
```

QuickJS 调用网页方法：

```js
const summary = await bridge.callPage('pageSummary');
```

`bridge.evaluate(source)` 用于执行普通网页 JavaScript。JavaScript 返回
`null` 或 `undefined` 时桥接结果为 `null`，无需为无返回值脚本额外构造结果。

## Cookie 会话

登录完成后读取 Cookie：

```js
const cookies = await bridge.getCookies('https://example.com/');
```

下次创建 WebView 时恢复：

```js
WebView({
  bridge,
  url: 'https://example.com/account',
  initialCookies: cookies
});
```

插件会先写入 `initialCookies`，再加载页面。公共 Cookie 字段为 `name`、
`value`、`domain` 和可选的 `path`。Flutter Web 仍受浏览器同源策略和
HttpOnly 限制。

可用命令还包括 `setCookies`、`clearCookies`、`clearCache` 和
`clearLocalStorage`。

## 链式 DOM 规则

```js
import {dom, webRules} from 'quickjs_ui/webview';

const rules = webRules(
  dom('#A')
    .find('.B')
    .find('.C')
    .first()
    .replaceText('旧文本', '新文本')
    .attr('data-selected', 'true')
    .style({color: '#168f63'})
);

export default WebView({bridge, url: 'https://example.com', rules});
```

查询结果可以继续级联操作。支持 `find`、`children`、`first`、`last`、`at`，
以及文本、HTML、属性、样式、class、显示、删除、替换、点击、聚焦和值修改等操作。

只保留查询结果：

```js
dom('#A').find('.B').find('.C').first().isolate({
  removeOthers: true,
  fillViewport: true
});
```

`removeOthers: false`（默认）隐藏祖先链之外的分支；设为 `true` 会删除其他分支。
`observe()` 可在动态页面中持续等待目标并重新应用规则。

## 子 frame 脚本

跨域 iframe 不能从主页面直接访问 DOM。需要修改 frame 内页面时，可注册
document-start 脚本：

```js
const refineLoginFrame = `(() => {
  if (!location.hostname.endsWith('example.com')) return;
  document.documentElement.dataset.embedded = 'true';
})()`;

WebView({
  bridge,
  url: 'https://example.com',
  frameScripts: [refineLoginFrame]
});
```

`frameScripts` 会注入主文档和所有子 frame。脚本必须自行判断 URL 或页面特征，
避免修改无关 frame。未配置时不会增加额外注入。

## WebView 属性与 Bridge 命令

常用 WebView 属性：`url`、`html`、`baseUrl`、`headers`、`initialCookies`、
`rules`、`frameScripts`、`javaScriptEnabled`、`zoomEnabled`、`userAgent`。

页面事件：`onPageStarted`、`onPageFinished`、`onProgress`、`onUrlChanged`、
`onMessage`、`onError`。

Bridge 提供：`evaluate`、`apply`、`callPage`、`reload`、`stop`、`goBack`、
`goForward`、`canGoBack`、`canGoForward`、`getUrl`、`getTitle`、Cookie/缓存
命令，以及 `loadUrl`、`loadHtml`。

仓库示例：

- [QuickJS 页面](../../examples/lemon_js_example/assets/quickjs_ui/webview_plugin_page.mjs)
- [Flutter 宿主页面](../../examples/lemon_js_example/lib/pages/quickjs_ui/getting_started/quickjs_ui_webview_plugin_page.dart)
