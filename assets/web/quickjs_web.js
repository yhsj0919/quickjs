// Flutter Web 主线程入口。
// 这里只负责加载 Worker、转发消息、维护 pending Promise；QuickJS 不在主线程执行。
(function () {
  /** @type {Worker | null} */
  let worker = null;
  let quickjsVersion = 'unknown';
  let config = null;
  let initializing = null;
  let nextRequestId = 1;
  /** @type {Map<number, { resolve: (value: unknown) => void, reject: (reason: unknown) => void, timer: number | null }>} */
  const pending = new Map();
  /** @type {Map<string, (argsJson: string) => Promise<string>>} */
  const callbacks = new Map();
  /** @type {Map<number, { pull: (pullRequestId: string, streamId: number) => Promise<string>, cancel: (streamId: number) => void, sinkAction: (sinkId: number, action: string, payloadJson?: string) => Promise<void> }>} */
  const streamBridges = new Map();
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

    // 初始化只允许一个流程在路上，避免并发 create 重复拉起 Worker。
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
      if (message.type === 'callbackRequest') {
        void handleCallbackRequest(message);
        return;
      }
      if (message.type === 'streamPullRequest') {
        void handleStreamPullRequest(message);
        return;
      }
      if (message.type === 'streamCancelRequest') {
        handleStreamCancelRequest(message);
        return;
      }
      if (message.type === 'sinkActionRequest') {
        void handleSinkActionRequest(message);
        return;
      }
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
      // Worker 级错误会失败所有 pending 请求，并让下一次调用重新创建 Worker。
      rejectAll(new Error(event.message || 'QuickJS worker crashed'));
    };
    instance.onmessageerror = () => {
      rejectAll(new Error('QuickJS worker message error'));
    };
    return instance;
  }

  async function handleCallbackRequest(message) {
    const callbackKey = `${message.runtimeId}:${message.callbackId}`;
    const callback = callbacks.get(callbackKey);
    const callbackRequestId = message.callbackRequestId;
    if (!callback) {
      worker?.postMessage({
        type: 'callbackResponse',
        callbackRequestId,
        success: false,
        payloadJson: `QuickJS callback ${message.callbackId} is not bound`,
      });
      return;
    }

    try {
      const payloadJson = await callback(String(message.argsJson || '[]'));
      worker?.postMessage({
        type: 'callbackResponse',
        callbackRequestId,
        success: true,
        payloadJson,
      });
    } catch (error) {
      worker?.postMessage({
        type: 'callbackResponse',
        callbackRequestId,
        success: false,
        payloadJson: error instanceof Error ? error.message : String(error),
      });
    }
  }

  async function handleStreamPullRequest(message) {
    const bridge = streamBridges.get(Number(message.runtimeId));
    const pullRequestId = message.pullRequestId;
    if (!bridge) {
      worker?.postMessage({
        type: 'streamPullResponse',
        pullRequestId,
        success: false,
        payloadJson: `QuickJS stream bridge for runtime ${message.runtimeId} is not registered`,
      });
      return;
    }
    try {
      const payloadJson = await bridge.pull(
        String(pullRequestId),
        Number(message.streamId)
      );
      worker?.postMessage({
        type: 'streamPullResponse',
        pullRequestId,
        success: true,
        payloadJson,
      });
    } catch (error) {
      worker?.postMessage({
        type: 'streamPullResponse',
        pullRequestId,
        success: false,
        payloadJson: error instanceof Error ? error.message : String(error),
      });
    }
  }

  function handleStreamCancelRequest(message) {
    streamBridges.get(Number(message.runtimeId))?.cancel(Number(message.streamId));
  }

  async function handleSinkActionRequest(message) {
    const bridge = streamBridges.get(Number(message.runtimeId));
    const actionRequestId = message.actionRequestId;
    if (!bridge) {
      worker?.postMessage({
        type: 'sinkActionResponse',
        actionRequestId,
        success: false,
        payloadJson: `QuickJS stream bridge for runtime ${message.runtimeId} is not registered`,
      });
      return;
    }
    try {
      await bridge.sinkAction(
        Number(message.sinkId),
        String(message.action),
        message.payloadJson === undefined ? undefined : String(message.payloadJson)
      );
      worker?.postMessage({
        type: 'sinkActionResponse',
        actionRequestId,
        success: true,
      });
    } catch (error) {
      worker?.postMessage({
        type: 'sinkActionResponse',
        actionRequestId,
        success: false,
        payloadJson: error instanceof Error ? error.message : String(error),
      });
    }
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
          // 同步 WASM 无法被主线程打断时，terminate Worker 是当前 web 兜底策略。
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

    async runtimeNew(memoryLimitBytes = 0) {
      return post('runtimeNew', { memoryLimitBytes });
    },

    /** @param {number} id @param {string} code */
    async runtimeEval(id, code, timeoutMs = 0) {
      return post('runtimeEval', { runtimeId: id, code }, timeoutMs);
    },

    /** @param {number} id @param {string} code */
    async runtimeEvalAsync(id, code, timeoutMs = 0) {
      return post('runtimeEvalAsync', { runtimeId: id, code }, timeoutMs);
    },

    /**
     * @param {number} runtimeId
     * @param {number} callbackId
     * @param {string} name
     * @param {(argsJson: string) => Promise<string>} callback
     */
    async runtimeBindCallback(runtimeId, callbackId, name, callback) {
      callbacks.set(`${runtimeId}:${callbackId}`, callback);
      return post('runtimeBindCallback', { runtimeId, callbackId, name });
    },

    runtimeRegisterStreamBridge(runtimeId, pull, cancel, sinkAction) {
      streamBridges.set(runtimeId, { pull, cancel, sinkAction });
    },

    async runtimeBindSink(runtimeId, sinkId, name) {
      return post('runtimeBindSink', { runtimeId, sinkId, name });
    },

    async runtimeStop() {
      // stop 在 web 侧等价于终止 Worker；Dart backend 会随后重建 runtime。
      rejectAll(new Error(cancelledMessage));
    },

    /** @param {number} id */
    async runtimeDispose(id) {
      if (!worker) {
        return;
      }
      const prefix = `${id}:`;
      for (const key of callbacks.keys()) {
        if (key.startsWith(prefix)) {
          callbacks.delete(key);
        }
      }
      streamBridges.delete(id);
      await post('runtimeDispose', { runtimeId: id });
    },
  };
})();
