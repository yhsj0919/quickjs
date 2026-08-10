// QuickJS Web Worker 入口。
// Worker 持有 WASM bridge 和所有 runtime 实例，主线程只通过 postMessage 访问。
(function () {
  /** @type {import('./quickjs_bridge.mjs') | null} */
  let bridge = null;
  /** @type {MessageEvent[]} */
  const queue = [];
  let draining = false;

  self.onmessage = (event) => {
    if (
      (event.data || {}).type === 'callbackResponse' ||
      (event.data || {}).type === 'streamPullResponse' ||
      (event.data || {}).type === 'sinkActionResponse'
    ) {
      return;
    }
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
          result = await bridge.runtimeNew(message.memoryLimitBytes);
          break;
        case 'runtimeEval':
          ensureBridge();
          result = bridge.runtimeEval(
            message.runtimeId,
            message.code,
            message.name
          );
          break;
        case 'runtimeEvalModule':
          ensureBridge();
          result = await bridge.runtimeEvalModule(
            message.runtimeId,
            message.source,
            message.name,
            message.modulesJson
          );
          break;
        case 'runtimeEvalAsync':
          ensureBridge();
          result = await bridge.runtimeEvalAsync(
            message.runtimeId,
            message.code,
            message.name
          );
          break;
        case 'runtimeBindCallback':
          ensureBridge();
          bridge.runtimeBindCallback(
            message.runtimeId,
            message.callbackId,
            message.name
          );
          break;
        case 'runtimeBindSink':
          ensureBridge();
          bridge.runtimeBindSink(
            message.runtimeId,
            message.sinkId,
            message.name
          );
          break;
        case 'callbackResponse':
          ensureBridge();
          // callback responses are consumed by the dispatcher promise below.
          // They do not correspond to a normal request/response id.
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
    bridge.setCallbackDispatcher(async (request) => {
      const callbackRequestId = `${request.runtimeId}:${request.callbackId}:${Date.now()}:${Math.random()}`;
      return new Promise((resolve) => {
        const listener = (event) => {
          const message = event.data || {};
          if (
            message.type !== 'callbackResponse' ||
            message.callbackRequestId !== callbackRequestId
          ) {
            return;
          }
          self.removeEventListener('message', listener);
          resolve({
            ok: Boolean(message.success),
            payloadJson: String(message.payloadJson ?? ''),
          });
        };
        self.addEventListener('message', listener);
        self.postMessage({
          type: 'callbackRequest',
          callbackRequestId,
          runtimeId: request.runtimeId,
          callbackId: request.callbackId,
          argsJson: request.argsJson,
        });
      });
    });
    bridge.setStreamDispatchers(
      async (request) => {
        const pullRequestId = `${request.runtimeId}:${request.streamId}:${Date.now()}:${Math.random()}`;
        return new Promise((resolve, reject) => {
          const listener = (event) => {
            const message = event.data || {};
            if (
              message.type !== 'streamPullResponse' ||
              message.pullRequestId !== pullRequestId
            ) {
              return;
            }
            self.removeEventListener('message', listener);
            if (message.success) {
              resolve(String(message.payloadJson ?? '{"done":true}'));
            } else {
              reject(new Error(String(message.payloadJson ?? 'QuickJS stream pull failed')));
            }
          };
          self.addEventListener('message', listener);
          self.postMessage({
            type: 'streamPullRequest',
            pullRequestId,
            runtimeId: request.runtimeId,
            streamId: request.streamId,
          });
        });
      },
      (request) => {
        self.postMessage({
          type: 'streamCancelRequest',
          runtimeId: request.runtimeId,
          streamId: request.streamId,
        });
      },
      async (request) => {
        const actionRequestId = `${request.runtimeId}:${request.sinkId}:${Date.now()}:${Math.random()}`;
        return new Promise((resolve, reject) => {
          const listener = (event) => {
            const message = event.data || {};
            if (
              message.type !== 'sinkActionResponse' ||
              message.actionRequestId !== actionRequestId
            ) {
              return;
            }
            self.removeEventListener('message', listener);
            if (message.success) {
              resolve();
            } else {
              reject(new Error(String(message.payloadJson ?? 'QuickJS sink action failed')));
            }
          };
          self.addEventListener('message', listener);
          self.postMessage({
            type: 'sinkActionRequest',
            actionRequestId,
            runtimeId: request.runtimeId,
            sinkId: request.sinkId,
            action: request.action,
            payloadJson: request.payloadJson,
          });
        });
      }
    );
  }
})();
