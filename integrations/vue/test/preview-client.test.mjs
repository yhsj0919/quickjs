import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import test from 'node:test';
import { createPreviewClient, previewProtocol } from '../preview-client.mjs';

function harness(timeoutMs = 1000) {
  let listener;
  const sent = [];
  const frame = { postMessage: (data, origin) => sent.push({ data, origin }) };
  const eventTarget = {
    addEventListener: (_, callback) => { listener = callback; },
    removeEventListener: () => { listener = null; },
  };
  const events = [];
  const client = createPreviewClient({ eventTarget, getFrame: () => frame,
    origin: 'https://player.example', channel: 'one', timeoutMs,
    onEvent: (event) => events.push(event) });
  return { client, events, sent, receive(data, overrides = {}) {
    listener?.({ source: frame, origin: 'https://player.example',
      data: { protocol: previewProtocol, channel: 'one', ...data }, ...overrides });
  } };
}

test('iframe requests reject unrelated sources, origins and channels', async () => {
  const h = harness();
  const result = h.client.request('load', { src: '/main.mjs' });
  const { requestId } = h.sent[0].data;
  h.receive({ type: 'ready' }, { source: {} });
  h.receive({ type: 'ready' }, { origin: 'https://other.example' });
  h.receive({ type: 'ready', channel: 'other' });
  assert.deepEqual(h.events, []);
  assert.equal(h.sent[0].origin, 'https://player.example');
  h.receive({ type: 'result', requestId, ok: true });
  assert.equal((await result).ok, true);
  h.client.close();
});

test('failed commands, timeout and dispose reject pending requests', async () => {
  const h = harness(20);
  const failed = h.client.request('load');
  h.receive({ type: 'result', requestId: h.sent[0].data.requestId, ok: false, error: 'Bad plugin' });
  await assert.rejects(failed, /Bad plugin/);
  await assert.rejects(h.client.request('pause'), /timed out/);
  const pending = h.client.request('play');
  h.client.close();
  await assert.rejects(pending, /closed/);
  await assert.rejects(h.client.request('load'), /unavailable/);
});

test('Web host accepts only its configured parent and tags responses', () => {
  let listener;
  let received;
  const sent = [];
  const parent = { postMessage: (data, origin) => sent.push({ data, origin }) };
  const window = { parent, location: { search: '?channel=abc&parentOrigin=https%3A%2F%2Fvue.example' },
    addEventListener: (_, callback) => { listener = callback; } };
  const source = readFileSync(new URL('../../../examples/lemon_js_example/web/quickjs_preview_host.js', import.meta.url), 'utf8');
  runInNewContext(source, { window, URL, URLSearchParams });
  window.quickjsPreviewHost.register((json) => { received = JSON.parse(json); });
  const data = { protocol: previewProtocol, channel: 'abc', command: 'load' };
  listener({ source: parent, origin: 'https://other.example', data });
  assert.equal(received, undefined);
  listener({ source: {}, origin: 'https://vue.example', data });
  assert.equal(received, undefined);
  listener({ source: parent, origin: 'https://vue.example', data });
  assert.equal(received.command, 'load');
  window.quickjsPreviewHost.emit(JSON.stringify({ type: 'ready' }));
  assert.equal(sent[0].origin, 'https://vue.example');
  assert.equal(sent[0].data.channel, 'abc');
});
