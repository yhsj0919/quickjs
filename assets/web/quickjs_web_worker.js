// QuickJS Web Worker entry. Owns the WASM bridge and every runtime instance.
(function () {
  /** @type {import('./quickjs_bridge.mjs') | null} */
  let bridge = null;

  self.onmessage = async (event) => {
    const message = event.data || {};
    const id = message.id;
    const type = message.type;

    try {
      let result = null;
      switch (type) {
        case 'init':
          bridge = await import(message.bridgeModuleUrl);
          await bridge.init(message.wasmUrl);
          result = String(await bridge.quickjsVersion());
          break;
        case 'eval':
          ensureBridge();
          result = await bridge.evalCode(message.code);
          break;
        case 'runtimeNew':
          ensureBridge();
          result = await bridge.runtimeNew();
          break;
        case 'runtimeEval':
          ensureBridge();
          result = bridge.runtimeEval(message.runtimeId, message.code);
          break;
        case 'runtimeDispose':
          ensureBridge();
          bridge.runtimeDispose(message.runtimeId);
          break;
        default:
          throw new Error(`quickjs worker: unknown message type ${type}`);
      }

      self.postMessage({ id, ok: true, result });
    } catch (error) {
      self.postMessage({
        id,
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  };

  function ensureBridge() {
    if (!bridge) {
      throw new Error('quickjs worker: call init first');
    }
  }
})();
