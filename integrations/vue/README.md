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
`autoPlay: true` 会在插件 mount 完成后、`loaded` 事件之前调用 `onPageWillActive`。
默认即为 `autoPlay: true`，网页不需要额外通知，也没有预加载阶段。
`play()` 使用相同激活流程，每次激活只通知一次；暂停后可再次通知。
激活不会预先修改 `playing`，由插件在 `onPageWillActive` 内处理；暂停保留 `playing: false`
和 pause 生命周期。插件切换或 reload 会重新开始一轮生命周期。
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

## 图片与插件交替显示

将播放器放在轮播项的条件分支之外。第一次遇到插件才挂载，后续切到图片时只隐藏并暂停，
保留上一次插件的 `src` 和参数；切到另一个插件仅替换 MJS，不销毁 iframe。
不要将 `v-if="showPlugin"` 或随轮播项变化的 `key` 放在 `QuickJsPreview` 上。

```vue
<script setup>
import { computed, ref, watch } from 'vue';
import QuickJsPreview from '@lemon-js/vue-preview';
const props = defineProps({ item: { type: Object, required: true } });
const showPlugin = computed(() => props.item.type === 'plugin');
const pluginSrc = ref('');
const pluginProps = ref({});
watch(() => props.item, (item) => {
  if (item.type !== 'plugin') return;
  pluginSrc.value = item.src;
  pluginProps.value = item.pageProps ?? {};
}, { immediate: true });
</script>

<template>
  <div style="height: 80vh">
    <img v-if="!showPlugin" :src="item.src" style="width: 100%; height: 100%; object-fit: contain">
    <QuickJsPreview
      v-if="pluginSrc"
      v-show="showPlugin"
      player-url="https://module.palsmon.com/"
      :src="pluginSrc"
      :page-props="pluginProps"
      :auto-play="showPlugin"
    />
  </div>
</template>
```

这里的 `v-if="pluginSrc"` 只控制首次创建，图片项不会清空 `pluginSrc`。
首次加载仍需下载/启动 Flutter；常驻 iframe 避免后续轮播再次支付这部分成本。
切换 MJS 仍会执行新插件的 mount 和网络请求，属于插件加载阶段。

服务器应对 `application/wasm` 开启 gzip（或 Brotli），并配置静态资源缓存。
`index.html`、`flutter_bootstrap.js` 和未带版本号的 `main.dart.js` 应重新验证缓存；
资源按版本目录部署时，可为对应 WASM/JS 设置较长的缓存期限，避免新版本仍使用旧缓存。
