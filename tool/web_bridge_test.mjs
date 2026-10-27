import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { QuickJS } from '../packages/lemon_js/assets/web/quickjs_wasi.js';
import * as bridge from '../packages/lemon_js/assets/web/quickjs_bridge.mjs';

// Exercise the shipped WASM and bridge without Flutter's browser asset server.
const bytes = await readFile(new URL('../packages/lemon_js/assets/web/quickjs.wasm', import.meta.url));
const originalFetch = globalThis.fetch;
globalThis.fetch = async () => new Response(bytes);
await bridge.init('quickjs.wasm');
globalThis.fetch = originalFetch;
const create = QuickJS.create;
let lastVm;
QuickJS.create = async function (options) {
  lastVm = await create.call(this, options);
  return lastVm;
};

test('stack limit rejects invalid sizes and catches recursion without destroying the VM', async () => {
  await assert.rejects(bridge.runtimeNew(undefined, 512 * 1024 + 1), /maxStackSize/);
  await assert.rejects(bridge.runtimeNew(undefined, -1), /maxStackSize/);
  const id = await bridge.runtimeNew(undefined, 64 * 1024);
  try {
    assert.match(bridge.runtimeEval(id, '(function recur() { return recur(); })()'), /stack overflow|maximum call stack size exceeded/i);
    assert.equal(bridge.runtimeEval(id, '6 * 7'), '42');
  } finally { bridge.runtimeDispose(id); }
});

test('module execution preserves undefined result, imports, top-level await and errors', async () => {
  const id = await bridge.runtimeNew();
  try {
    assert.equal(await bridge.runtimeEvalModule(id,
      'import {value} from "dep"; globalThis.result = await Promise.resolve(value); export default result;',
      'main.mjs', JSON.stringify({ dep: 'export const value = 42;' })), 'undefined');
    assert.equal(bridge.runtimeEval(id, 'result'), '42');
    assert.match(await bridge.runtimeEvalModule(id, 'throw new Error("module failed")', 'error.mjs', '{}'), /module failed/);
  } finally { bridge.runtimeDispose(id); }
});

test('completed and cancelled streams release host callbacks and remain valid iterators', async () => {
  const id = await bridge.runtimeNew();
  const vm = lastVm;
  const baseline = vm.hostCallbacks.size;
  let pulls = 0;
  let cancels = 0;
  bridge.setStreamDispatchers(async () => JSON.stringify(++pulls === 1
    ? { done: false, value: 7 } : { done: true }), () => { cancels++; }, async () => {});
  bridge.setCallbackDispatcher(async ({ callbackId }) => ({ ok: true,
    payloadJson: JSON.stringify({ __quickjsType: 'dartStream', streamId: callbackId }) }));
  bridge.runtimeBindCallback(id, 10, 'getStream');
  try {
    assert.equal(await bridge.runtimeEvalAsync(id, '(async () => { globalThis.stream = await getStream(); const values=[]; for await (const x of stream) values.push(x); return values.join(); })()'), '7');
    assert.equal(vm.hostCallbacks.size, baseline + 1);
    assert.equal(await bridge.runtimeEvalAsync(id, 'stream.next().then(x => x.done)'), 'true');
    assert.equal(await bridge.runtimeEvalAsync(id, 'stream.return().then(x => x.done)'), 'true');
    bridge.runtimeBindCallback(id, 11, 'getOtherStream');
    assert.equal(await bridge.runtimeEvalAsync(id, '(async () => { const other = await getOtherStream(); await other.return(); return (await other.next()).done; })()'), 'true');
    assert.equal(cancels, 1);
    assert.equal(vm.hostCallbacks.size, baseline + 2);
  } finally { bridge.runtimeDispose(id); }
});

test('sink close and error release callbacks while repeated close stays harmless', async () => {
  const id = await bridge.runtimeNew();
  const vm = lastVm;
  const baseline = vm.hostCallbacks.size;
  const actions = [];
  bridge.setStreamDispatchers(async () => '{}', () => {}, async request => { actions.push(request.action); });
  try {
    for (let i = 0; i < 20; i++) {
      bridge.runtimeBindSink(id, i, 'sink');
      assert.equal(await bridge.runtimeEvalAsync(id, '(async () => { await sink.emit(1); await sink.close(); await sink.close(); return "ok"; })()'), 'ok');
      assert.equal(vm.hostCallbacks.size, baseline);
    }
    bridge.runtimeBindSink(id, 20, 'sink');
    await bridge.runtimeEvalAsync(id, '(async () => { await sink.error("failed"); await sink.close(); })()');
    assert.equal(vm.hostCallbacks.size, baseline);
    assert.match(bridge.runtimeEval(id, 'sink.emit(2)'), /sink is closed/);
    assert.equal(actions.filter(x => x === 'close').length, 20);
    assert.equal(actions.filter(x => x === 'error').length, 1);
  } finally { bridge.runtimeDispose(id); }
});
