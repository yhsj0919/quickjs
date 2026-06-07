// Flutter Web entry. Runs QuickJS inside a Web Worker and exposes a stable
// global API for dart:js_interop.
(function () {
  /** @type {Worker | null} */
  let worker = null;
  let quickjsVersion = 'unknown';
  let nextRequestId = 1;
  /** @type {Map<number, { resolve: (value: unknown) => void, reject: (reason: unknown) => void }>} */
  const pending = new Map();

  function ensureWorker() {
    if (!worker) {
      throw new Error('quickjsNgWeb: call ensureInitialized first');
    }
    return worker;
  }

  function createWorker(workerScriptUrl) {
    if (typeof Worker === 'undefined') {
      throw new Error('quickjsNgWeb: Web Worker is not supported');
    }

    const instance = new Worker(workerScriptUrl);
    instance.onmessage = (event) => {
      const message = event.data || {};
      const callbacks = pending.get(message.id);
      if (!callbacks) {
        return;
      }
      pending.delete(message.id);
      if (message.ok) {
        callbacks.resolve(message.result);
      } else {
        callbacks.reject(new Error(message.error || 'QuickJS worker failed'));
      }
    };
    instance.onerror = (event) => {
      rejectAll(new Error(event.message || 'QuickJS worker crashed'));
    };
    instance.onmessageerror = () => {
      rejectAll(new Error('QuickJS worker message error'));
    };
    return instance;
  }

  function post(type, payload = {}) {
    const target = ensureWorker();
    const id = nextRequestId++;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      target.postMessage({ id, type, ...payload });
    });
  }

  function rejectAll(error) {
    for (const callbacks of pending.values()) {
      callbacks.reject(error);
    }
    pending.clear();
    if (worker) {
      worker.terminate();
      worker = null;
    }
  }

  globalThis.quickjsNgWeb = {
    /**
     * @param {string} wasmUrl
     * @param {string} bridgeModuleUrl
     * @param {string} workerScriptUrl
     */
    async ensureInitialized(wasmUrl, bridgeModuleUrl, workerScriptUrl) {
      if (worker) {
        return quickjsVersion;
      }
      worker = createWorker(workerScriptUrl);
      try {
        quickjsVersion = await post('init', { wasmUrl, bridgeModuleUrl });
      } catch (error) {
        if (worker) {
          worker.terminate();
          worker = null;
        }
        throw error;
      }
      return quickjsVersion;
    },

    quickjsVersion() {
      return quickjsVersion;
    },

    /** @param {string} code */
    async evalCode(code) {
      return post('eval', { code });
    },

    async runtimeNew() {
      return post('runtimeNew');
    },

    /** @param {number} id @param {string} code */
    async runtimeEval(id, code) {
      return post('runtimeEval', { runtimeId: id, code });
    },

    /** @param {number} id */
    async runtimeDispose(id) {
      if (!worker) {
        return;
      }
      await post('runtimeDispose', { runtimeId: id });
    },
  };
})();
