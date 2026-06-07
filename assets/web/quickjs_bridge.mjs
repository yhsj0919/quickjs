/**
 * Thin bridge for Flutter web — wraps quickjs-wasi (QuickJS WASM).
 * @see https://www.npmjs.com/package/quickjs-wasi
 */
import { QuickJS } from './quickjs_wasi.js';

/** @type {WebAssembly.Module | undefined} */
let wasmModule;

/** @type {Map<number, import('./quickjs_wasi.js').QuickJS>} */
const runtimes = new Map();
let nextRuntimeId = 1;

/**
 * @param {string} wasmUrl
 */
export async function init(wasmUrl) {
  if (wasmModule) {
    return;
  }
  const response = await fetch(wasmUrl);
  if (!response.ok) {
    throw new Error(`Failed to load QuickJS WASM: ${response.status}`);
  }
  const bytes = await response.arrayBuffer();
  wasmModule = await WebAssembly.compile(bytes);
}

/**
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

/**
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
    if (err && typeof err === 'object' && 'message' in err) {
      return String(err.message);
    }
    return String(err);
  }
}

/**
 * @param {string} code
 */
export async function evalCode(code) {
  if (!wasmModule) {
    throw new Error('quickjs: WASM not initialized');
  }
  const vm = await QuickJS.create({ wasm: wasmModule });
  try {
    return evalOnVm(vm, code);
  } finally {
    vm[Symbol.dispose]();
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

/** @returns {Promise<number>} */
export async function runtimeNew() {
  if (!wasmModule) {
    throw new Error('quickjs: WASM not initialized');
  }
  const vm = await QuickJS.create({ wasm: wasmModule });
  const id = nextRuntimeId++;
  runtimes.set(id, vm);
  return id;
}

/**
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

/** @param {number} id */
export function runtimeDispose(id) {
  const vm = runtimes.get(id);
  if (vm) {
    vm[Symbol.dispose]();
    runtimes.delete(id);
  }
}
