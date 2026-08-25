const host = globalThis.__jsHostMethods;
const command = (bridgeId, method, args = {}) =>
  host['quickjs_ui.webview.command'](bridgeId, method, args);

let nextBridgeId = 1;

class DomRule {
  constructor(path = [], operations = [], options = {}) {
    this._path = path;
    this._operations = operations;
    this._options = options;
  }

  _copy({ path = this._path, operations = this._operations, options = this._options } = {}) {
    return new DomRule(path, operations, options);
  }

  _step(selector, relation) {
    return this._copy({
      path: [...this._path, { selector, relation }]
    });
  }

  _operation(action, values = {}) {
    return this._copy({
      operations: [...this._operations, { action, ...values }]
    });
  }

  find(selector) { return this._step(selector, 'descendant'); }
  children(selector) { return this._step(selector, 'child'); }

  _selectIndex(index) {
    if (this._path.length === 0) throw new Error('A DOM selector is required before selecting an index');
    const path = this._path.slice();
    path[path.length - 1] = { ...path[path.length - 1], index };
    return this._copy({ path });
  }

  first() { return this._selectIndex(0); }
  last() { return this._selectIndex(-1); }
  at(index) { return this._selectIndex(index); }
  text(value) { return this._operation('setText', { value }); }
  html(value) { return this._operation('setHtml', { value }); }
  replaceText(find, replace, options = {}) {
    return this._operation('replaceText', { find, replace, all: options.all === true });
  }
  attr(name, value) { return this._operation('setAttribute', { name, value }); }
  attrs(attributes) { return this._operation('setAttributes', { attributes }); }
  removeAttr(name) { return this._operation('removeAttribute', { name }); }
  style(styles) { return this._operation('setStyle', { styles }); }
  css(name, value) { return this.style({ [name]: value }); }
  addClass(value) { return this._operation('addClass', { value }); }
  removeClass(value) { return this._operation('removeClass', { value }); }
  hide() { return this._operation('hide'); }
  show() { return this._operation('show'); }
  remove() { return this._operation('remove'); }
  replaceWith(html) { return this._operation('replaceElement', { html }); }
  isolate(options = {}) { return this._operation('isolate', { options }); }
  click() { return this._operation('click'); }
  focus() { return this._operation('focus'); }
  value(value) { return this._operation('setValue', { value }); }
  observe(enabled = true) { return this._copy({ options: { ...this._options, observe: enabled } }); }

  toRule() {
    return { path: this._path, operations: this._operations, ...this._options };
  }
}

export function dom(selector) {
  return new DomRule().find(selector);
}

export function webRules(...rules) {
  return rules.flat(Infinity).filter(Boolean).map(rule =>
    rule instanceof DomRule ? rule.toRule() : rule
  );
}

class WebBridge {
  constructor(id) {
    this.id = id;
    this._methods = new Map();
    this._listening = false;
  }

  expose(name, callback) {
    if (typeof callback !== 'function') throw new TypeError('Web bridge method must be a function');
    this._methods.set(name, callback);
    if (!this._listening) {
      this._listening = true;
      this._listen();
    }
    return this;
  }

  unexpose(name) {
    this._methods.delete(name);
    return this;
  }

  async _listen() {
    while (this._listening) {
      let call;
      try {
        call = await host['quickjs_ui.webview.nextCall'](this.id);
      } catch (_) {
        this._listening = false;
        return;
      }
      if (!call) continue;
      const callback = this._methods.get(call.method);
      let response;
      if (!callback) {
        response = { id: call.id, error: { code: 'METHOD_NOT_FOUND', message: `Method "${call.method}" is not exposed` } };
      } else {
        try {
          response = { id: call.id, result: await callback(call.arguments) };
        } catch (error) {
          response = { id: call.id, error: { code: error?.code ?? 'METHOD_FAILED', message: String(error?.message ?? error) } };
        }
      }
      await host['quickjs_ui.webview.respond'](this.id, response);
    }
  }

  callPage(method, args) { return command(this.id, 'callPage', { method, arguments: args }); }
  evaluate(source) { return command(this.id, 'evaluate', { source }); }
  apply(...rules) { return command(this.id, 'applyRules', { rules: webRules(...rules) }); }
  reload() { return command(this.id, 'reload'); }
  stop() { return command(this.id, 'stop'); }
  goBack() { return command(this.id, 'goBack'); }
  goForward() { return command(this.id, 'goForward'); }
  canGoBack() { return command(this.id, 'canGoBack'); }
  canGoForward() { return command(this.id, 'canGoForward'); }
  getUrl() { return command(this.id, 'getUrl'); }
  getTitle() { return command(this.id, 'getTitle'); }
  getCookies(url) { return command(this.id, 'getCookies', url ? { url } : {}); }
  setCookies(cookies) { return command(this.id, 'setCookies', { cookies }); }
  clearCookies() { return command(this.id, 'clearCookies'); }
  clearCache() { return command(this.id, 'clearCache'); }
  clearLocalStorage() { return command(this.id, 'clearLocalStorage'); }
  loadUrl(url, options = {}) { return command(this.id, 'loadUrl', { url, ...options }); }
  loadHtml(html, options = {}) { return command(this.id, 'loadHtml', { html, ...options }); }
}

export function createWebBridge(id) {
  return new WebBridge(id ?? `webview-bridge-${Date.now()}-${nextBridgeId++}`);
}

export function WebView(props = {}) {
  const bridge = props.bridge;
  const rules = props.rules == null ? undefined : webRules(props.rules);
  const node = {
    type: 'WebView',
    key: props.key ?? bridge?.id ?? 'webview',
    ...props,
    bridgeId: bridge?.id ?? props.bridgeId
  };
  delete node.bridge;
  if (rules === undefined) delete node.rules;
  else node.rules = rules;
  return node;
}
