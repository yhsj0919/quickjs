// QuickJS Web Worker 入口。
// Worker 持有 WASM bridge 和所有 runtime 实例，主线程只通过 postMessage 访问。
(function () {
  /** @type {import('./quickjs_bridge.mjs') | null} */
  let bridge = null;
  /** @type {MessageEvent[]} */
  const queue = [];
  let draining = false;

  self.onmessage = (event) => {
    // 所有消息进入 FIFO 队列，避免同一个 Worker 内的 QuickJS runtime 被并发重入。
    queue.push(event);
    void drainQueue();
  };

  async function drainQueue() {
    if (draining) {
      return;
    }
    draining = true;

    while (queue.length > 0) {
      const event = queue.shift();
      if (event) {
        await handleMessage(event);
      }
    }

    draining = false;
  }

  async function handleMessage(event) {
    const message = event.data || {};
    const id = message.id;
    const type = message.type;

    try {
      let result = null;
      switch (type) {
        case 'init':
          // 动态 import bridge，避免主线程直接加载 WASM 执行逻辑。
          bridge = await import(message.bridgeModuleUrl);
          await bridge.init(message.wasmUrl);
          result = String(await bridge.quickjsVersion());
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
      // 错误必须通过响应返回给 Dart pending Future，不能只写 console。
      self.postMessage({
        id,
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  function ensureBridge() {
    if (!bridge) {
      throw new Error('quickjs worker: call init first');
    }
  }
})();
