# Vue 3 QuickJS 插件预览

Vue 组件通过 iframe 嵌入专用 Flutter Web 播放器，直接运行原有 quickjs_ui MJS。
组件需要 Vue 3 和 Vue SFC 构建支持（例如现有的 Vite Vue 项目）。

将 `QuickJsPreview.vue` 和 `preview-client.mjs` 放进 Vue 项目的组件目录，或安装本目录的 npm 包。

```vue
<script setup>
import { ref } from 'vue';
import QuickJsPreview from './components/QuickJsPreview.vue';
const preview = ref(null);
const playing = ref(true);
const pageProps = { screenNo: '宿主加密设备码' };
</script>

<template>
  <button @click="playing = !playing">{{ playing ? '暂停' : '启动' }}</button>
  <div style="height: 80vh">
    <QuickJsPreview
      ref="preview"
      player-url="https://module.palsmon.com/"
      src="https://module.palsmon.com/plugins/RenderScreen/main.mjs"
      :page-props="pageProps"
      :auto-play="playing"
      @error="console.error"
    />
  </div>
</template>
```

`player-url` 必须指向以 `lib/preview_main.dart` 构建的专用播放器，旧 Demo 包没有此通信入口。
`src` 可用绝对地址，也可用相对于 Vue 页面地址的路径。MJS 的相对模块、图片路径按插件目录解析。
修改 `src` 或 `pageProps` 会卸载旧插件并重新加载。父页面与播放器必须使用 HTTP(S)。

组件暴露 `play()`、`pause()`、`reload()`、`dispatch(event)`、`setState(patch)`，返回 Promise。
事件为 `ready`（播放器可接收指令）、`loaded`（插件首帧完成）、`error`。
播放控制发送 resume/pause 生命周期，并更新插件状态 `playing`；启动时调用 `onPageWillActive`。
RenderScreen 可直接使用此约定，其他插件如使用不同状态字段可调用 `setState`/`dispatch`。
暂停不会强行终止已开始的网络请求，也不会停止插件自己创建的全部定时器。

构建播放器（在 `examples/lemon_js_example` 下）：

```sh
flutter build web --release --target lib/preview_main.dart --no-web-resources-cdn
```

将 `build/web/` 全部部署到站点根目录。子目录部署需增加 `--base-href /preview/`。
MJS 文件和插件请求的 API 跨域时，需要对应服务器提供 CORS。
Nginx/OpenResty 要为 `.mjs` 返回 JavaScript MIME 类型：

```nginx
location ~* \.mjs$ {
    types { application/javascript mjs; }
    try_files $uri =404;
}
```

WASM 应返回 `application/wasm`。页面使用 `.mjs` 是为 QuickJS 提供源码；Flutter Web
自身的桥接 `.mjs` 则由浏览器模块加载器执行。播放器通信校验父窗口、来源和实例 channel。
预览对象应为可信插件；iframe 通信验证不替代插件的网络或宿主权限策略。
