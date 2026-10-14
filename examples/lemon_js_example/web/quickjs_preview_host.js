(function () {
  'use strict';
  const protocol = 'quickjs-preview.v1';
  const params = new URLSearchParams(window.location.search);
  const channel = params.get('channel');
  const configuredOrigin = params.get('parentOrigin');
  let parentOrigin;
  try {
    parentOrigin = new URL(configuredOrigin).origin;
    if (parentOrigin === 'null') throw new Error('Invalid parent origin');
  } catch (_) {
    parentOrigin = null;
  }
  let receive;
  window.quickjsPreviewHost = Object.freeze({
    register(callback) {
      receive = callback;
    },
    emit(json) {
      if (!channel || !parentOrigin || window.parent === window) return;
      window.parent.postMessage({ ...JSON.parse(json), protocol, channel }, parentOrigin);
    },
  });
  window.addEventListener('message', (event) => {
    const data = event.data;
    if (!receive || !channel || !parentOrigin || event.source !== window.parent ||
        event.origin !== parentOrigin || !data || data.protocol !== protocol ||
        data.channel !== channel || typeof data.command !== 'string') return;
    receive(JSON.stringify(data));
  });
})();
