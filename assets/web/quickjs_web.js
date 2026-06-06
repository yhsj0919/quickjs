// Flutter Web entry — classic script (no Dart dynamic import).
// Loads the ESM bridge and exposes a stable global API for dart:js_interop.
(function () {
  /** @type {import('./quickjs_bridge.mjs') | null} */
  let bridge = null;

  globalThis.quickjsNgWeb = {
    /**
     * @param {string} wasmUrl
     * @param {string} bridgeModuleUrl
     */
    async ensureInitialized(wasmUrl, bridgeModuleUrl) {
      if (bridge) {
        return;
      }
      bridge = await import(bridgeModuleUrl);
      await bridge.init(wasmUrl);
    },

    /** @param {string} code */
    async evalCode(code) {
      if (!bridge) {
        throw new Error('quickjsNgWeb: call ensureInitialized first');
      }
      return bridge.evalCode(code);
    },

    async runtimeNew() {
      if (!bridge) {
        throw new Error('quickjsNgWeb: call ensureInitialized first');
      }
      return bridge.runtimeNew();
    },

    /** @param {number} id @param {string} code */
    runtimeEval(id, code) {
      if (!bridge) {
        throw new Error('quickjsNgWeb: call ensureInitialized first');
      }
      return bridge.runtimeEval(id, code);
    },

    /** @param {number} id */
    runtimeDispose(id) {
      if (!bridge) {
        return;
      }
      bridge.runtimeDispose(id);
    },
  };
})();
