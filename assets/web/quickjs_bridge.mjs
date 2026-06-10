/**
 * Flutter Web 的 QuickJS WASM 薄桥接层。
 * 这里直接调用 quickjs-wasi，并维护 worker 内的 runtime registry。
 * @see https://www.npmjs.com/package/quickjs-wasi
 */
import { QuickJS } from './quickjs_wasi.js';

/** @type {WebAssembly.Module | undefined} */
let wasmModule;

/** @type {Map<number, import('./quickjs_wasi.js').QuickJS>} */
const runtimes = new Map();
let nextRuntimeId = 1;
const exceptionSentinel = '\x1eQuickJS_EXCEPTION';

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

/**
 * 在指定 VM 中执行 JS，并用 sentinel 区分 JS throw 和普通字符串结果。
 *
 * @param {import('./quickjs_wasi.js').QuickJS} vm
 * @param {string} code
 */
function evalOnVm(vm, code) {
  let handle;
  try {
    handle = vm.evalCode(code);
    return valueToString(vm, handle);
  } catch (err) {
    if (handle) {
      handle.dispose();
    }
    // 与 native bridge 对齐：JS throw 用 sentinel 返回给 Dart 映射成 JsException。
    return `${exceptionSentinel}${exceptionToPayload(err)}`;
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
  const options = { wasm: wasmModule };
  if (Number.isFinite(memoryLimitBytes) && memoryLimitBytes > 0) {
    options.memoryLimit = memoryLimitBytes;
  }
  const vm = await QuickJS.create(options);
  const id = nextRuntimeId++;
  // runtime id 是 Dart 侧唯一可见的 handle，真实 VM 只保存在 Worker 内。
  runtimes.set(id, vm);
  return id;
}

/**
 * 在指定 runtime 中执行 JS。
 *
 * @param {number} id
 * @param {string} code
 */
export function runtimeEval(id, code) {
  const vm = runtimes.get(id);
  if (!vm) {
    throw new Error(`quickjs: invalid runtime id ${id}`);
  }
  return evalOnVm(vm, code);
}

/**
 * 释放指定 runtime。
 *
 * @param {number} id
 */
export function runtimeDispose(id) {
  const vm = runtimes.get(id);
  if (vm) {
    // runtime 必须显式 dispose，避免 WASM 侧 handle 和内存泄漏。
    vm[Symbol.dispose]();
    runtimes.delete(id);
  }
}
