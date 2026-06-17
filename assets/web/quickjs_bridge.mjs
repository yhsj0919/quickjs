/**
 * Flutter Web 的 QuickJS WASM 薄桥接层。
 * 这里直接调用 quickjs-wasi，并维护 worker 内的 runtime registry。
 * @see https://www.npmjs.com/package/quickjs-wasi
 */
import { EvalFlags, JSValueHandle, QuickJS } from './quickjs_wasi.js';

/** @type {WebAssembly.Module | undefined} */
let wasmModule;

/** @type {Map<number, import('./quickjs_wasi.js').QuickJS>} */
const runtimes = new Map();
let nextRuntimeId = 1;
const exceptionSentinel = '\x1eQuickJS_EXCEPTION';

/** @type {((request: { runtimeId: number, callbackId: number, argsJson: string }) => Promise<{ ok: boolean, payloadJson: string }>) | null} */
let callbackDispatcher = null;
/** @type {((request: { runtimeId: number, streamId: number }) => Promise<string>) | null} */
let streamPullDispatcher = null;
/** @type {((request: { runtimeId: number, streamId: number }) => void) | null} */
let streamCancelDispatcher = null;
/** @type {((request: { runtimeId: number, sinkId: number, action: string, payloadJson?: string }) => Promise<void>) | null} */
let sinkActionDispatcher = null;

/**
 * 初始化 WASM module。
 *
 * @param {string} wasmUrl
 */
export async function init(wasmUrl) {
  if (wasmModule) {
    return;
  }
  // WASM module 只编译一次，后续 runtime 复用同一个 module 创建 VM。
  const response = await fetch(wasmUrl);
  if (!response.ok) {
    throw new Error(`Failed to load QuickJS WASM: ${response.status}`);
  }
  const bytes = await response.arrayBuffer();
  wasmModule = await WebAssembly.compile(bytes);
}

/**
 * 将 quickjs-wasi 的 JSValueHandle 转成当前阶段对外暴露的字符串结果。
 *
 * @param {import('./quickjs_wasi.js').QuickJS} vm
 * @param {import('./quickjs_wasi.js').JSValueHandle} handle
 */
function valueToString(vm, handle) {
  if (handle.isUndefined) {
    handle.dispose();
    return 'undefined';
  }
  if (handle.isNull) {
    handle.dispose();
    return 'null';
  }
  if (handle.promiseState === 0) {
    // Promise job pump 尚未实现，先返回占位文本，避免 handle 泄漏。
    handle.dispose();
    return '[Promise]';
  }
  try {
    const text = handle.toString();
    handle.dispose();
    return text;
  } catch (err) {
    handle.dispose();
    return err instanceof Error ? err.message : String(err);
  }
}

function encodeWireValue(value) {
  if (value instanceof ArrayBuffer) {
    return { __quickjsType: 'bytes', value: Array.from(new Uint8Array(value)) };
  }
  if (ArrayBuffer.isView(value)) {
    return {
      __quickjsType: 'bytes',
      value: Array.from(new Uint8Array(value.buffer, value.byteOffset, value.byteLength)),
    };
  }
  if (Array.isArray(value)) {
    return value.map(encodeWireValue);
  }
  if (value && typeof value === 'object') {
    const result = {};
    for (const [key, item] of Object.entries(value)) {
      result[key] = encodeWireValue(item);
    }
    return result;
  }
  return value;
}

function decodeWireValue(record, value) {
  if (Array.isArray(value)) {
    return value.map((item) => decodeWireValue(record, item));
  }
  if (value && typeof value === 'object') {
    if (value.__quickjsType === 'bytes') {
      return new Uint8Array(value.value || []);
    }
    if (value.__quickjsType === 'dartStream') {
      return createDartStreamHandle(record, Number(value.streamId));
    }
    const result = {};
    for (const [key, item] of Object.entries(value)) {
      result[key] = decodeWireValue(record, item);
    }
    return result;
  }
  return value;
}

function createDartStreamHandle(record, streamId) {
  const vm = record.vm;
  const iterable = vm.newObject();
  const next = vm.newFunction(`__quickjsStreamNext_${streamId}`, () => {
    const deferred = vm.newPromise();
    let deferredSettled = false;
    (async () => {
      if (!streamPullDispatcher) {
        throw new Error('quickjs: stream pull dispatcher is not registered');
      }
      const payloadJson = await streamPullDispatcher({
        runtimeId: record.id,
        streamId,
      });
      const payload = JSON.parse(payloadJson);
      if (payload.done) {
        return createIteratorResult(record, true, undefined);
      }
      return createIteratorResult(record, false, decodeWireValue(record, payload.value));
    })().then((value) => {
      settleDeferred(deferred, () => deferredSettled, () => {
        deferredSettled = true;
      }, () => {
        resolveDeferredWithHostValue(vm, deferred, value);
      });
    }).catch((error) => {
      settleDeferred(deferred, () => deferredSettled, () => {
        deferredSettled = true;
      }, () => {
        rejectDeferredWithHostValue(vm, deferred, error);
      });
    });
    return deferred.handle;
  });
  const cancel = vm.newFunction(`__quickjsStreamReturn_${streamId}`, () => {
    const deferred = vm.newPromise();
    let deferredSettled = false;
    (async () => {
      if (streamCancelDispatcher) {
        streamCancelDispatcher({ runtimeId: record.id, streamId });
      }
      return createIteratorResult(record, true, undefined);
    })().then((value) => {
      settleDeferred(deferred, () => deferredSettled, () => {
        deferredSettled = true;
      }, () => {
        resolveDeferredWithHostValue(vm, deferred, value);
      });
    }).catch((error) => {
      settleDeferred(deferred, () => deferredSettled, () => {
        deferredSettled = true;
      }, () => {
        rejectDeferredWithHostValue(vm, deferred, error);
      });
    });
    return deferred.handle;
  });
  const asyncIterator = vm.newFunction(
    `__quickjsStreamAsyncIterator_${streamId}`,
    function () {
      return this.dup();
    },
  );
  const asyncIteratorSymbol = vm.evalCode('Symbol.asyncIterator');

  iterable.setProp('next', next);
  iterable.setProp('return', cancel);
  vm.setProp(iterable, asyncIteratorSymbol, asyncIterator);
  next.dispose();
  cancel.dispose();
  asyncIterator.dispose();
  asyncIteratorSymbol.dispose();
  return iterable;
}

function createIteratorResult(record, done, value) {
  const vm = record.vm;
  const result = vm.newObject();
  const doneHandle = vm.hostToHandle(done);
  result.setProp('done', doneHandle);
  if (!done) {
    const valueHandle = value instanceof JSValueHandle ? value : vm.hostToHandle(value);
    result.setProp('value', valueHandle);
  }
  return result;
}

function resolveDeferredWithHostValue(vm, deferred, value) {
  const handle = value instanceof JSValueHandle ? value : vm.hostToHandle(value);
  try {
    deferred.resolve(handle);
    vm.executePendingJobs();
  } finally {
    handle.dispose();
  }
}

function rejectDeferredWithHostValue(vm, deferred, value) {
  const handle = value instanceof JSValueHandle ? value : vm.hostToHandle(value);
  try {
    deferred.reject(handle);
    vm.executePendingJobs();
  } finally {
    handle.dispose();
  }
}

function settleDeferred(deferred, isSettled, markSettled, settle) {
  if (isSettled()) {
    return;
  }
  markSettled();
  try {
    settle();
  } finally {
    deferred.handle.dispose();
  }
}

function readStringProperty(value, property) {
  if (!value || typeof value !== 'object' || !(property in value)) {
    return null;
  }
  const propertyValue = value[property];
  return typeof propertyValue === 'string' ? propertyValue : null;
}

function readNumberProperty(value, property) {
  if (!value || typeof value !== 'object' || !(property in value)) {
    return null;
  }
  const propertyValue = value[property];
  return Number.isFinite(propertyValue) ? propertyValue : null;
}

function exceptionToPayload(err) {
  const message =
    err && typeof err === 'object' && 'message' in err
      ? String(err.message)
      : String(err);
  return JSON.stringify({
    message,
    name: readStringProperty(err, 'name'),
    stack: readStringProperty(err, 'stack'),
    fileName: readStringProperty(err, 'fileName'),
    line: readNumberProperty(err, 'lineNumber'),
    column: readNumberProperty(err, 'columnNumber'),
  });
}

function resolveModuleName(baseName, specifier) {
  if (!specifier.startsWith('./') && !specifier.startsWith('../')) {
    return specifier;
  }
  const slash = baseName.lastIndexOf('/');
  const base = slash < 0 ? '' : baseName.slice(0, slash + 1);
  const parts = [];
  for (const part of `${base}${specifier}`.split('/')) {
    if (!part || part === '.') {
      continue;
    }
    if (part === '..') {
      parts.pop();
      continue;
    }
    parts.push(part);
  }
  return parts.join('/');
}

/**
 * 在指定 VM 中执行 JS，并用 sentinel 区分 JS throw 和普通字符串结果。
 *
 * @param {import('./quickjs_wasi.js').QuickJS} vm
 * @param {string} code
 * @param {string} name
 */
function evalOnVm(vm, code, name = '<eval>') {
  let handle;
  try {
    handle = vm.evalCode(code, name || '<eval>');
    return valueToString(vm, handle);
  } catch (err) {
    if (handle) {
      handle.dispose();
    }
    // 与 native bridge 对齐：JS throw 用 sentinel 返回给 Dart 映射成 JsException。
    return `${exceptionSentinel}${exceptionToPayload(err)}`;
  }
}

function runtimeRecord(id) {
  const record = runtimes.get(id);
  if (!record) {
    throw new Error(`quickjs: invalid runtime id ${id}`);
  }
  return record;
}

function disposeTimer(vm, timer) {
  if (!timer || timer.disposed) {
    return;
  }
  timer.disposed = true;
  timer.callback.dispose();
  for (const arg of timer.args) {
    arg.dispose();
  }
}

function clearRuntimeTimer(record, timerId) {
  const timer = record.timers.get(timerId);
  if (!timer) {
    return;
  }
  timer.cancelled = true;
  if (timer.repeat) {
    clearInterval(timer.hostId);
  } else {
    clearTimeout(timer.hostId);
  }
  if (!timer.running) {
    record.timers.delete(timerId);
    disposeTimer(record.vm, timer);
  }
}

function installTimers(record) {
  const vm = record.vm;
  const setTimer = (repeat, args) => {
    if (!args.length) {
      throw new TypeError('QuickJS timer callback must be a function');
    }
    const callback = args[0].dup();
    const delay = Math.max(0, Number(args[1] ? vm.dump(args[1]) : 0) || 0);
    const timerArgs = args.slice(2).map((arg) => arg.dup());

    const timerId = record.nextTimerId++;
    const timer = {
      id: timerId,
      hostId: 0,
      repeat,
      callback,
      args: timerArgs,
      running: false,
      cancelled: false,
      disposed: false,
    };
    const fire = () => {
      if (timer.cancelled || timer.disposed) {
        return;
      }
      timer.running = true;
      try {
        const result = vm.callFunction(callback, vm.undefined, ...timerArgs);
        result.dispose();
        vm.executePendingJobs();
      } finally {
        timer.running = false;
        if (!repeat || timer.cancelled) {
          clearRuntimeTimer(record, timerId);
        }
      }
    };
    timer.hostId = repeat
      ? setInterval(fire, delay === 0 ? 1 : delay)
      : setTimeout(fire, delay);
    record.timers.set(timerId, timer);
    return vm.hostToHandle(timerId);
  };

  const setTimeoutFn = vm.newFunction('setTimeout', (...args) => setTimer(false, args));
  const setIntervalFn = vm.newFunction('setInterval', (...args) => setTimer(true, args));
  const clearTimeoutFn = vm.newFunction('clearTimeout', (...args) => {
    const timerId = args.length ? Number(vm.dump(args[0])) : 0;
    clearRuntimeTimer(record, timerId);
    return vm.undefined;
  });
  const clearIntervalFn = vm.newFunction('clearInterval', (...args) => {
    const timerId = args.length ? Number(vm.dump(args[0])) : 0;
    clearRuntimeTimer(record, timerId);
    return vm.undefined;
  });
  const global = vm.global;
  global.setProp('setTimeout', setTimeoutFn);
  global.setProp('setInterval', setIntervalFn);
  global.setProp('clearTimeout', clearTimeoutFn);
  global.setProp('clearInterval', clearIntervalFn);
  setTimeoutFn.dispose();
  setIntervalFn.dispose();
  clearTimeoutFn.dispose();
  clearIntervalFn.dispose();
}

async function evalAsyncOnVm(vm, code, name = '<evalAsync>') {
  let handle;
  try {
    handle = vm.evalCode(code, name || '<evalAsync>');
    vm.executePendingJobs();
    const settled = await vm.resolvePromise(handle);
    vm.executePendingJobs();
    if (settled.error) {
      const payload = exceptionToPayload(vm.dump(settled.error));
      settled.error.dispose();
      return `${exceptionSentinel}${payload}`;
    }
    return valueToString(vm, settled.value);
  } catch (err) {
    return `${exceptionSentinel}${exceptionToPayload(err)}`;
  } finally {
    if (handle) {
      handle.dispose();
    }
  }
}

/** @returns {Promise<string>} */
export async function quickjsVersion() {
  if (!wasmModule) {
    throw new Error('quickjs: WASM not initialized');
  }
  const vm = await QuickJS.create({ wasm: wasmModule });
  try {
    return vm.versions.quickjs;
  } finally {
    vm[Symbol.dispose]();
  }
}

/**
 * @param {number | undefined} memoryLimitBytes
 * @returns {Promise<number>}
 */
export async function runtimeNew(memoryLimitBytes) {
  if (!wasmModule) {
    throw new Error('quickjs: WASM not initialized');
  }
  const moduleSources = new Map();
  const options = {
    wasm: wasmModule,
    moduleLoader: {
      normalize(baseName, specifier) {
        return resolveModuleName(baseName || '', specifier);
      },
      load(name) {
        if (!moduleSources.has(name)) {
          throw new Error(`quickjs: module not found: ${name}`);
        }
        return moduleSources.get(name);
      },
    },
  };
  if (Number.isFinite(memoryLimitBytes) && memoryLimitBytes > 0) {
    options.memoryLimit = memoryLimitBytes;
  }
  const vm = await QuickJS.create(options);
  const id = nextRuntimeId++;
  // runtime id 是 Dart 侧唯一可见的 handle，真实 VM 只保存在 Worker 内。
  const record = {
    id,
    vm,
    callbackIds: new Map(),
    timers: new Map(),
    nextTimerId: 1,
    moduleSources,
  };
  installTimers(record);
  runtimes.set(id, record);
  return id;
}

/**
 * 在指定 runtime 中执行 JS。
 *
 * @param {number} id
 * @param {string} code
 * @param {string} name
 */
export function runtimeEval(id, code, name = '<eval>') {
  return evalOnVm(runtimeRecord(id).vm, code, name);
}

/**
 * @param {number} id
 * @param {string} source
 * @param {string} name
 */
export async function runtimeEvalModule(id, source, name, modulesJson) {
  const record = runtimeRecord(id);
  const vm = record.vm;
  let handle;
  try {
    const modules = JSON.parse(modulesJson || '{}');
    record.moduleSources.clear();
    for (const [moduleName, moduleSource] of Object.entries(modules)) {
      record.moduleSources.set(moduleName, String(moduleSource));
    }
    record.moduleSources.set(name || '<module>', source);
    handle = vm.evalCode(
      source,
      name || '<module>',
      EvalFlags.TYPE_MODULE | EvalFlags.STRICT
    );
    vm.executePendingJobs();
    const settled = await vm.resolvePromise(handle);
    vm.executePendingJobs();
    if (settled.error) {
      const payload = exceptionToPayload(vm.dump(settled.error));
      settled.error.dispose();
      return `${exceptionSentinel}${payload}`;
    }
    return valueToString(vm, settled.value);
  } catch (err) {
    if (handle) {
      handle.dispose();
    }
    return `${exceptionSentinel}${exceptionToPayload(err)}`;
  }
}

/**
 * @param {(request: { runtimeId: number, callbackId: number, argsJson: string }) => Promise<{ ok: boolean, payloadJson: string }>} dispatcher
 */
export function setCallbackDispatcher(dispatcher) {
  callbackDispatcher = dispatcher;
}

/**
 * @param {(request: { runtimeId: number, streamId: number }) => Promise<string>} pull
 * @param {(request: { runtimeId: number, streamId: number }) => void} cancel
 * @param {(request: { runtimeId: number, sinkId: number, action: string, payloadJson?: string }) => Promise<void>} sinkAction
 */
export function setStreamDispatchers(pull, cancel, sinkAction) {
  streamPullDispatcher = pull;
  streamCancelDispatcher = cancel;
  sinkActionDispatcher = sinkAction;
}

/**
 * @param {number} id
 * @param {number} callbackId
 * @param {string} name
 */
export function runtimeBindCallback(id, callbackId, name) {
  const record = runtimeRecord(id);
  const vm = record.vm;
  record.callbackIds.set(name, callbackId);
  const hostFunction = vm.newFunction(name, (...args) => {
    if (!callbackDispatcher) {
      throw new Error('quickjs: callback dispatcher is not registered');
    }
    const values = args.map((arg) => encodeWireValue(vm.dump(arg)));
    const deferred = vm.newPromise();
    let deferredSettled = false;
    callbackDispatcher({
      runtimeId: id,
      callbackId,
      argsJson: JSON.stringify(values),
    }).then((response) => {
      settleDeferred(deferred, () => deferredSettled, () => {
        deferredSettled = true;
      }, () => {
        if (response.ok) {
          resolveDeferredWithHostValue(
            vm,
            deferred,
            decodeWireValue(record, JSON.parse(response.payloadJson)),
          );
          return;
        }
        rejectDeferredWithHostValue(vm, deferred, new Error(response.payloadJson));
      });
    }).catch((error) => {
      settleDeferred(deferred, () => deferredSettled, () => {
        deferredSettled = true;
      }, () => {
        rejectDeferredWithHostValue(vm, deferred, error);
      });
    });
    return deferred.handle;
  });
  const global = vm.global;
  global.setProp(name, hostFunction);
  hostFunction.dispose();
}

/**
 * @param {number} id
 * @param {string} code
 * @param {string} name
 */
export async function runtimeEvalAsync(id, code, name = '<evalAsync>') {
  return evalAsyncOnVm(runtimeRecord(id).vm, code, name);
}

/**
 * @param {number} id
 * @param {number} sinkId
 * @param {string} name
 */
export function runtimeBindSink(id, sinkId, name) {
  const record = runtimeRecord(id);
  const vm = record.vm;
  const sinkObject = vm.newObject();
  const actionFunction = (action) => (...args) => {
    if (!sinkActionDispatcher) {
      throw new Error('quickjs: sink action dispatcher is not registered');
    }
    let payloadJson;
    if (args.length > 0) {
      payloadJson = JSON.stringify(encodeWireValue(vm.dump(args[0])));
    }
    return vm.hostToHandle(sinkActionDispatcher({
      runtimeId: id,
      sinkId,
      action,
      payloadJson,
    }));
  };
  const emit = vm.newFunction(`__quickjsSinkEmit_${sinkId}`, actionFunction('emit'));
  const close = vm.newFunction(`__quickjsSinkClose_${sinkId}`, actionFunction('close'));
  const error = vm.newFunction(`__quickjsSinkError_${sinkId}`, actionFunction('error'));
  sinkObject.setProp('emit', emit);
  sinkObject.setProp('close', close);
  sinkObject.setProp('error', error);
  const global = vm.global;
  global.setProp(name, sinkObject);
  emit.dispose();
  close.dispose();
  error.dispose();
  sinkObject.dispose();
}

/**
 * 释放指定 runtime。
 *
 * @param {number} id
 */
export function runtimeDispose(id) {
  const record = runtimes.get(id);
  if (record) {
    for (const timerId of Array.from(record.timers.keys())) {
      clearRuntimeTimer(record, timerId);
    }
    // runtime 必须显式 dispose，避免 WASM 侧 handle 和内存泄漏。
    record.vm[Symbol.dispose]();
    runtimes.delete(id);
  }
}
