<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { createPreviewClient } from './preview-client.mjs';

const props = defineProps({
  playerUrl: { type: String, required: true },
  src: { type: String, required: true },
  pageProps: { type: Object, default: () => ({}) },
  autoPlay: { type: Boolean, default: true },
  title: { type: String, default: 'QuickJS 插件预览' },
});
const emit = defineEmits(['ready', 'loaded', 'error']);
const iframe = ref(null);
const iframeUrl = ref('');
const ready = ref(false);
const loaded = ref(false);
let client;
let revision = 0;
const errorMessage = ref('');
const status = computed(() => errorMessage.value || (!ready.value ? '正在启动播放器…' : !loaded.value ? '正在加载插件…' : ''));

function report(error) {
  errorMessage.value = error.message || String(error);
  emit('error', error);
}
async function reload() {
  if (!ready.value || !client) throw new Error('Preview is not ready');
  const current = ++revision;
  const activeClient = client;
  loaded.value = false;
  errorMessage.value = '';
  const autoPlay = props.autoPlay;
  await activeClient.request('load', {
    src: new URL(props.src, window.location.href).href,
    pageProps: JSON.parse(JSON.stringify(props.pageProps)),
    autoPlay,
  });
  if (current !== revision || client !== activeClient) return;
  loaded.value = true;
  if (props.autoPlay !== autoPlay) {
    await activeClient.request(props.autoPlay ? 'play' : 'pause');
  }
}
function connect() {
  ++revision;
  client?.close();
  ready.value = false;
  loaded.value = false;
  errorMessage.value = '';
  try {
    const url = new URL(props.playerUrl, window.location.href);
    if (!['http:', 'https:'].includes(url.protocol)) throw new Error('playerUrl must use HTTP(S)');
    const channel = Array.from(window.crypto.getRandomValues(new Uint8Array(16)),
      (byte) => byte.toString(16).padStart(2, '0')).join('');
    url.searchParams.set('channel', channel);
    url.searchParams.set('parentOrigin', window.location.origin);
    client = createPreviewClient({
      eventTarget: window,
      getFrame: () => iframe.value?.contentWindow,
      origin: url.origin,
      channel,
      onEvent(message) {
        if (message.type === 'ready') {
          ready.value = true;
          emit('ready');
          reload().catch(report);
        } else if (message.type === 'loaded') {
          loaded.value = true;
          emit('loaded', message);
        } else if (message.type === 'error') {
          report(new Error(message.error));
        }
      },
    });
    iframeUrl.value = url.href;
  } catch (error) { report(error); }
}
function command(name, data) {
  if (!client || !loaded.value) return Promise.reject(new Error('Load a plugin first'));
  return client.request(name, data);
}
const play = () => command('play');
const pause = () => command('pause');
const dispatch = (event) => command('dispatch', { event });
const setState = (patch) => command('setState', { patch });
defineExpose({ play, pause, reload, dispatch, setState });
onMounted(connect);
watch(() => props.playerUrl, connect);
watch(() => [props.src, props.pageProps], () => {
  if (ready.value) reload().catch(report);
}, { deep: true });
watch(() => props.autoPlay, (value) => {
  if (loaded.value) command(value ? 'play' : 'pause').catch(report);
});
onBeforeUnmount(() => { ++revision; client?.close(); });
</script>

<template>
  <div class="quickjs-preview">
    <iframe ref="iframe" :src="iframeUrl || undefined" :title="title" allow="autoplay; fullscreen" />
    <div v-if="status" class="quickjs-preview-status" role="status">{{ status }}</div>
  </div>
</template>

<style scoped>
.quickjs-preview { position: relative; width: 100%; height: 100%; min-height: 240px; }
.quickjs-preview iframe { display: block; width: 100%; height: 100%; border: 0; }
.quickjs-preview-status { position: absolute; inset: 0; display: grid; place-items: center; padding: 16px; background: #f8fafc; color: #334155; white-space: pre-wrap; }
</style>
