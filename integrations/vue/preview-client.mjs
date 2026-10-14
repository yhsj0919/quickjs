export const previewProtocol = 'quickjs-preview.v1';

/** Transport for one iframe. Messages are scoped by origin, window and channel. */
export function createPreviewClient({ eventTarget, getFrame, origin, channel, onEvent, timeoutMs = 65000 }) {
  let nextId = 0;
  let closed = false;
  const pending = new Map();
  function receive(event) {
    const message = event.data;
    if (event.source !== getFrame() || event.origin !== origin ||
        !message || message.protocol !== previewProtocol || message.channel !== channel) return;
    if (message.type === 'result') {
      const request = pending.get(message.requestId);
      if (!request) return;
      pending.delete(message.requestId);
      clearTimeout(request.timer);
      if (message.ok) request.resolve(message);
      else request.reject(new Error(message.error || 'Preview command failed'));
    } else {
      onEvent(message);
    }
  }
  eventTarget.addEventListener('message', receive);
  function post(command, data, requestId) {
    const frame = getFrame();
    if (closed || !frame) throw new Error('Preview iframe is unavailable');
    frame.postMessage({ ...data, command, requestId, protocol: previewProtocol, channel }, origin);
  }
  return {
    request(command, data = {}) {
      const requestId = ++nextId;
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          pending.delete(requestId);
          reject(new Error(`Preview ${command} timed out`));
        }, timeoutMs);
        pending.set(requestId, { resolve, reject, timer });
        try { post(command, data, requestId); }
        catch (error) {
          pending.delete(requestId);
          clearTimeout(timer);
          reject(error);
        }
      });
    },
    close() {
      if (closed) return;
      try { post('unload', {}, null); } catch (_) { /* iframe already removed */ }
      closed = true;
      eventTarget.removeEventListener('message', receive);
      for (const request of pending.values()) {
        clearTimeout(request.timer);
        request.reject(new Error('Preview closed'));
      }
      pending.clear();
    },
  };
}
