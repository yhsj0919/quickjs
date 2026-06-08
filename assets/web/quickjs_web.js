// Flutter Web entry. Runs QuickJS inside a Web Worker and exposes a stable
// global API for dart:js_interop.
(function () {
  /** @type {Worker | null} */
  let worker = null;
  let quickjsVersion = 'unknown';
  let config = null;
  let initializing = null;
  let nextRequestId = 1;
  /** @type {Map<number, { resolve: (value: unknown) => void, reject: (reason: unknown) => void, timer: number | null }>} */
  const pending = new Map();
  const timeoutMessage = 'QuickJS evaluation timed out';
  const cancelledMessage = 'QuickJS evaluation was cancelled';

  async function ensureReady() {
    if (worker) {
      return;
    }
    if (!config) {
      throw new Error('quickjsNgWeb: call ensureInitialized first');
    }
    if (initializing) {
      await initializing;
      return;
    }

    worker = createWorker(config.workerScriptUrl);
    initializing = postRaw('init', {
      wasmUrl: config.wasmUrl,
      bridgeModuleUrl: config.bridgeModuleUrl,
    }).then((version) => {
      quickjsVersion = String(version);
    }).finally(() => {
      initializing = null;
    });
    await initializing;
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
      if (callbacks.timer !== null) {
        clearTimeout(callbacks.timer);
      }
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

  async function post(type, payload = {}, timeoutMs = 0) {
    await ensureReady();
    return postRaw(type, payload, timeoutMs);
  }

  function postRaw(type, payload = {}, timeoutMs = 0) {
    const target = worker;
    if (!target) {
      throw new Error('quickjsNgWeb: worker is not ready');
    }
    const id = nextRequestId++;
    return new Promise((resolve, reject) => {
      let timer = null;
      if (Number.isFinite(timeoutMs) && timeoutMs > 0) {
        timer = setTimeout(() => {
          const callbacks = pending.get(id);
          if (!callbacks) {
            return;
          }
          pending.delete(id);
          callbacks.reject(new Error(timeoutMessage));
          rejectAll(new Error(timeoutMessage));
        }, timeoutMs);
      }
      pending.set(id, { resolve, reject, timer });
      target.postMessage({ id, type, ...payload });
    });
  }

  function rejectAll(error) {
    for (const callbacks of pending.values()) {
      if (callbacks.timer !== null) {
        clearTimeout(callbacks.timer);
      }
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
      config = { wasmUrl, bridgeModuleUrl, workerScriptUrl };
      await ensureReady();
      return quickjsVersion;
    },

    quickjsVersion() {
      return quickjsVersion;
    },

    /** @param {string} code */
    async evalCode(code, timeoutMs = 0) {
      return post('eval', { code }, timeoutMs);
    },

    async runtimeNew() {
      return post('runtimeNew');
    },

    /** @param {number} id @param {string} code */
    async runtimeEval(id, code, timeoutMs = 0) {
      return post('runtimeEval', { runtimeId: id, code }, timeoutMs);
    },

    async runtimeStop() {
      rejectAll(new Error(cancelledMessage));
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
