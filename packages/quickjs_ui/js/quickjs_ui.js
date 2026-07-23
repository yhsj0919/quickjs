const MAX_DISPATCH_DEPTH = 64;
const MAX_RENDER_DEPTH = 64;
// Keep this below the QuickJS native call-stack limit. Component recursion is
// a protocol error and must be reported before the engine stack overflows.
const MAX_COMPONENT_RENDER_DEPTH = 16;
export const quickjsUiRuntimeProtocol = 'quickjs_ui.runtime.v1';
export const quickjsUiSchemaVersion = 1;
export const quickjsUiHelperVersion = 1;
let pageRenderDepth = 0;
let componentRenderDepth = 0;
let activeListBuilderContext = null;
const LIST_BUILDER_RANGE_METHOD = '__quickjsUiListBuilderRange';

export function Page(page) {
  if (page == null || typeof page !== 'object') {
    throw new TypeError('quickjs_ui Page definition must be an object');
  }
  if (typeof page.build !== 'function') {
    throw new TypeError('quickjs_ui Page requires build(state, props, actions)');
  }

  const methods = pageMethods(page);
  const actions = methodActions(methods);
  const context = pageContext(methods, dispatchRuntimeEvent);
  const lifecycleHooks = lifecycleHookTypes(page);
  let state;
  let props = {};
  let mounted = false;
  let dirty = true;
  let version = 0;
  let dispatchDepth = 0;
  const eventQueue = [];
  let drainingEvents = false;
  const listBuilderRanges = new Map();
  const listBuilderResetTokens = new Map();

  const runtime = {
    name: page.name,
    metadata: page.metadata,
    capabilities() {
      return {
        protocol: quickjsUiRuntimeProtocol,
        schemaVersion: page.schemaVersion ?? quickjsUiSchemaVersion,
        helperVersion: quickjsUiHelperVersion,
        minimumQuickjsUiVersion:
          page.minimumQuickjsUiVersion ?? page.minQuickjsUiVersion ?? 1,
        unknownProps: page.unknownProps ?? 'ignore',
        deprecatedProps: page.deprecatedProps ?? {},
        lifecycle: lifecycleHooks
      };
    },
    async mount(nextProps) {
      props = nextProps ?? {};
      if (typeof page.createState === 'function') {
        state = await page.createState(props);
      } else if (typeof page.state === 'function') {
        state = await page.state(props);
      } else {
        state = {};
      }
      assertPlainState(state);
      mounted = true;
      dirty = true;
      version += 1;
      return snapshot();
    },
    handleEvent(event) {
      requireMounted(mounted);
      if (event?.method === LIST_BUILDER_RANGE_METHOD) {
        return updateListBuilderRange(event);
      }
      const queued = {
        event
      };
      eventQueue.push(queued);
      if (drainingEvents) {
        return commitResult(false);
      }
      return drainEvents();
    },
    async lifecycle(event) {
      return runLifecycle(event);
    },
    setState(patch) {
      requireMounted(mounted);
      return commitStatePatch(patch);
    },
    commit() {
      requireMounted(mounted);
      if (!dirty) {
        return commitResult(false);
      }
      if (pageRenderDepth >= MAX_RENDER_DEPTH) {
        throw new RangeError('quickjs_ui page render recursion limit exceeded');
      }
      pageRenderDepth += 1;
      try {
        assertPlainState(state);
        const previousListBuilderContext = activeListBuilderContext;
        activeListBuilderContext = {
          ranges: listBuilderRanges,
          resetTokens: listBuilderResetTokens
        };
        let node;
        try {
          node = page.build(state, props, actions);
        } finally {
          activeListBuilderContext = previousListBuilderContext;
        }
        dirty = false;
        return {
          changed: true,
          version,
          node
        };
      } finally {
        pageRenderDepth -= 1;
      }
    },
    snapshot() {
      requireMounted(mounted);
      return snapshot();
    },
    dispose() {
      mounted = false;
      state = undefined;
      props = {};
      dirty = false;
      listBuilderRanges.clear();
      listBuilderResetTokens.clear();
      if (globalThis.__quickjsUiPageLifecycle === invokeLifecycle) {
        delete globalThis.__quickjsUiPageLifecycle;
      }
      return true;
    }
  };

  // Navigation providers are invoked while handleEvent is still active. A
  // second host-side client call would queue behind that event and deadlock if
  // push() is waiting for a child result. This private entry lets the injected
  // navigation facade run routeLeave/hide inside the current JS turn instead.
  const invokeLifecycle = (event, cancellation) =>
    runLifecycle(event, cancellation);
  Object.defineProperty(globalThis, '__quickjsUiPageLifecycle', {
    value: invokeLifecycle,
    configurable: true,
    writable: false,
    enumerable: false
  });
  return runtime;

  async function runLifecycle(event, cancellation) {
    requireMounted(mounted);
    const hook = getLifecycleHook(page, event?.type);
    if (typeof hook !== 'function') {
      return commitResult(false);
    }
    const normalized = normalizeDispatchEvent(event);
    const patch = await hook(
      state,
      normalized.data,
      props,
      normalized.event,
      context
    );
    if (cancellation?.cancelled === true) {
      return commitResult(false);
    }
    return commitStatePatch(patch);
  }

  function commitStatePatch(patch) {
    if (patch === state) {
      throw new TypeError(
        'quickjs_ui page handlers must return a state patch, not the current state'
      );
    }
    const nextState = applyStatePatch(state, patch);
    if (nextState == null) {
      return commitResult(false);
    }
    state = nextState;
    dirty = true;
    version += 1;
    return commitResult(true);
  }

  function updateListBuilderRange(event) {
    const listKey = event?.listKey;
    const start = Number.isInteger(event?.start) ? event.start : 0;
    const end = Number.isInteger(event?.end) ? event.end : 0;
    if (typeof listKey !== 'string' || listKey.length === 0 || start < 0 || end <= start) {
      return commitResult(false);
    }
    listBuilderRanges.set(listKey, { start, end });
    dirty = true;
    version += 1;
    return commitResult(true);
  }

  function commitResult(changed) {
    return { changed: changed === true, version };
  }

  function snapshot() {
    return {
      version,
      state
    };
  }

  async function drainEvents() {
    drainingEvents = true;
    let changed = false;
    try {
      while (eventQueue.length > 0) {
        const queued = eventQueue.shift();
        const patch = dispatchPageMethod(state, queued.event, props, methods, context, () => {
          dispatchDepth += 1;
        }, () => {
          dispatchDepth -= 1;
        }, () => dispatchDepth);
        const didChange = applyQueuedPatch(await patch);
        changed = didChange || changed;
      }
      return commitResult(changed);
    } finally {
      drainingEvents = false;
    }
  }

  function dispatchRuntimeEvent(event) {
    requireMounted(mounted);
    eventQueue.push({ event });
    if (drainingEvents) {
      return commitResult(false);
    }
    return drainEvents();
  }

  function applyQueuedPatch(patch) {
    const before = version;
    const result = commitStatePatch(patch);
    return result.changed === true && version != before;
  }
}

export function setState(state, patch) {
  const next = {};
  if (state != null && typeof state === 'object' && !Array.isArray(state)) {
    for (const key of Object.keys(state)) {
      const value = state[key];
      if (typeof value === 'function') {
        throw new TypeError(
          'quickjs_ui state.' + key + ' must not be a function'
        );
      }
      next[key] = value;
    }
  }
  if (patch != null && typeof patch === 'object' && !Array.isArray(patch)) {
    for (const key of Object.keys(patch)) {
      const value = patch[key];
      if (typeof value === 'function') {
        throw new TypeError(
          'quickjs_ui state patch.' + key + ' must not be a function'
        );
      }
      next[key] = value;
    }
  }
  return next;
}

function applyStatePatch(state, patch) {
  if (patch === undefined || patch === null) {
    return null;
  }
  assertPlainState(patch, 'state patch');
  return setState(state, patch);
}

export function eventField(event, name, fallback) {
  const normalized = normalizeDispatchEvent(event).event;
  if (normalized == null) {
    return fallback;
  }
  const value = normalized[name];
  return value === undefined ? fallback : value;
}

function dispatchPageMethod(state, event, props, methods, context, enter, leave, depth) {
  if (depth() >= MAX_DISPATCH_DEPTH) {
    throw new RangeError('quickjs_ui dispatch recursion limit exceeded');
  }
  const normalized = normalizeDispatchEvent(event);
  const name = normalized.method;
  const handler = methods?.[name];
  if (typeof handler !== 'function') {
    return null;
  }
  enter();
  try {
    return settleDispatchPatch(
      handler(state, normalized.data, props, normalized.event, context),
      leave
    );
  } catch (error) {
    leave();
    throw error;
  }
}

function settleDispatchPatch(patch, onDone) {
  if (isThenable(patch)) {
    return Promise.resolve(patch).then(
      (resolved) => finishDispatchPatch(resolved, onDone),
      (error) => {
        onDone();
        throw error;
      }
    );
  }
  return finishDispatchPatch(patch, onDone);
}

function finishDispatchPatch(patch, onDone) {
  try {
    assertPatchOrNoop(patch, 'state patch');
    return patch;
  } finally {
    onDone();
  }
}

function isThenable(value) {
  return value != null && typeof value.then === 'function';
}

function requireMounted(mounted) {
  if (!mounted) {
    throw new Error('quickjs_ui page runtime is not mounted');
  }
}

function assertPatchOrNoop(patch, label) {
  if (patch === undefined || patch === null) {
    return;
  }
  assertPlainState(patch, label);
}

function normalizeDispatchEvent(event) {
  if (event == null || typeof event !== 'object' || Array.isArray(event)) {
    return { method: undefined, data: {}, event: {} };
  }
  const {
    method,
    action,
    payload,
  } = event;
  const data = {};
  for (const key of Object.keys(event)) {
    if (
      key === 'method' ||
      key === 'action' ||
      key === 'payload' ||
      key === 'policy' ||
      key === 'throttleMs' ||
      key === 'debounceMs' ||
      key === 'dropMs' ||
      key === 'coalesceKey' ||
      key === 'source' ||
      key === 'timestamp'
    ) {
      continue;
    }
    data[key] = event[key];
  }
  if (payload != null && typeof payload === 'object' && !Array.isArray(payload)) {
    for (const key of Object.keys(payload)) {
      data[key] = payload[key];
    }
  }
  const resolvedMethod = method ?? action;
  const resolvedEvent = {
  };
  if (resolvedMethod != null) {
    resolvedEvent.method = resolvedMethod;
  }
  for (const key of Object.keys(data)) {
    resolvedEvent[key] = data[key];
  }
  return {
    method: resolvedMethod,
    data,
    event: resolvedEvent
  };
}

function assertPlainState(state, label) {
  const stateLabel = label == null ? 'state' : label;
  if (state == null || typeof state !== 'object' || Array.isArray(state)) {
    throw new TypeError('quickjs_ui ' + stateLabel + ' must be a plain object');
  }
  for (const key of Object.keys(state)) {
    if (typeof state[key] === 'function') {
      throw new TypeError(
        'quickjs_ui ' + stateLabel + '.' + key + ' must not be a function'
      );
    }
  }
  return state;
}

function getLifecycleHook(page, type) {
  switch (type) {
    case 'mount':
      return page.onMount;
    case 'show':
      return page.onShow;
    case 'hide':
      return page.onHide;
    case 'pause':
      return page.onPause;
    case 'resume':
      return page.onResume;
    case 'routeEnter':
      return page.onRouteEnter;
    case 'routeLeave':
      return page.onRouteLeave;
    case 'routeResult':
      return page.onRouteResult;
    case 'dispose':
      return page.onDispose;
    default:
      return undefined;
  }
}

function lifecycleHookTypes(page) {
  const hooks = [];
  for (const [type, name] of [
    ['mount', 'onMount'],
    ['show', 'onShow'],
    ['hide', 'onHide'],
    ['pause', 'onPause'],
    ['resume', 'onResume'],
    ['routeEnter', 'onRouteEnter'],
    ['routeLeave', 'onRouteLeave'],
    ['routeResult', 'onRouteResult'],
    ['dispose', 'onDispose']
  ]) {
    if (typeof page[name] === 'function') {
      hooks.push(type);
    }
  }
  return Object.freeze(hooks);
}

function node(type, props = {}) {
  return { type, ...props };
}

function method(name, payload) {
  if (payload === undefined) {
    return { method: name };
  }
  return { method: name, payload };
}

export function action(name, payload) {
  return method(name, payload);
}

export const event = action;

export function Component(render) {
  if (typeof render !== 'function') {
    throw new TypeError('quickjs_ui Component render must be a function');
  }
  return function component(props = {}, actions = {}) {
    if (componentRenderDepth >= MAX_COMPONENT_RENDER_DEPTH) {
      throw new RangeError(
        'quickjs_ui component render recursion limit exceeded'
      );
    }
    componentRenderDepth += 1;
    try {
      const nodeValue = render(props ?? {}, actions ?? {});
      if (
        nodeValue == null ||
        typeof nodeValue !== 'object' ||
        typeof nodeValue.type !== 'string'
      ) {
        throw new TypeError('quickjs_ui Component must return a UI node object');
      }
      return nodeValue;
    } finally {
      componentRenderDepth -= 1;
    }
  };
}

export const defineComponent = Component;

function pageMethods(page) {
  const reserved = new Set([
    'name',
    'props',
    'metadata',
    'schemaVersion',
    'minimumQuickjsUiVersion',
    'minQuickjsUiVersion',
    'unknownProps',
    'deprecatedProps',
    'state',
    'createState',
    'build',
    'render',
    'init',
    'dispatch',
    'capabilities',
    'mount',
    'handleEvent',
    'commit',
    'setState',
    'lifecycle',
    'snapshot',
    'dispose',
    'onInit',
    'onMount',
    'onShow',
    'onHide',
    'onPause',
    'onResume',
    'onRouteEnter',
    'onRouteLeave',
    'onRouteResult',
    'onDispose',
    'methods'
  ]);
  return {
    ...(page.methods ?? {}),
    ...Object.fromEntries(
      Object.entries(page).filter(([name, value]) => {
        return !reserved.has(name) && typeof value === 'function';
      })
    )
  };
}

function methodActions(methods = {}) {
  const actions = {};
  for (const name of Object.keys(methods)) {
    actions[name] = (payload) => method(name, payload);
  }
  return actions;
}

function pageContext(methods, dispatch) {
  return {
    dispatch,
    call(name, payload) {
      return dispatch(method(name, payload));
    },
    actions: methodDispatchActions(methods, dispatch)
  };
}

function methodDispatchActions(methods = {}, dispatch) {
  const actions = {};
  for (const name of Object.keys(methods)) {
    actions[name] = (payload) => dispatch(method(name, payload));
  }
  return actions;
}

export function Text(dataOrProps, props = {}) {
  if (typeof dataOrProps === 'string') {
    return node('Text', { data: dataOrProps, ...props });
  }
  return node('Text', dataOrProps);
}

export function ElevatedButton(props) {
  return node('ElevatedButton', props);
}

export function TextButton(props) {
  return node('TextButton', props);
}

export function OutlinedButton(props) {
  return node('OutlinedButton', props);
}

export function IconButton(props) {
  return node('IconButton', props);
}

export function InkWell(props) {
  return node('InkWell', props);
}

export function FloatingActionButton(props) {
  return node('FloatingActionButton', props);
}

export function Row(props) {
  return node('Row', props);
}

export function Column(props) {
  return node('Column', props);
}

export function Container(props) {
  return node('Container', props);
}

export function Image(props) {
  return node('Image', props);
}

export function Svg(props) {
  return node('Svg', props);
}

export function animate(from, to, options = {}) {
  return { from, to, ...options };
}

export function canvasCommands(draw) {
  if (typeof draw !== 'function') {
    throw new TypeError('quickjs_ui canvasCommands requires draw(ctx)');
  }
  const context = new Canvas2DContext();
  draw(context);
  return context.commands;
}

export function Canvas(props = {}) {
  const { draw, staticDraw, commands, staticCommands, ...canvasProps } = props;
  const retained = canvasProps.sceneKey != null;
  const result = { ...canvasProps };
  if (!retained || draw != null || commands != null) {
    result.commands = draw == null ? (commands ?? []) : canvasCommands(draw);
  }
  if (staticDraw != null || staticCommands != null) {
    result.staticCommands =
      staticDraw == null ? staticCommands : canvasCommands(staticDraw);
  }
  return node('Canvas', result);
}

export function SnapshotBoundary(props = {}) {
  return node('SnapshotBoundary', props);
}

export class Canvas2DContext {
  constructor() {
    this.commands = [];
    this.fillStyle = '#000000';
    this.strokeStyle = '#000000';
    this.lineWidth = 1;
    this.lineCap = 'butt';
    this.lineJoin = 'miter';
    this.globalAlpha = 1;
    this.globalCompositeOperation = 'srcOver';
    this.font = '14px sans-serif';
    this.textAlign = 'left';
    this.textBaseline = 'alphabetic';
    this._path = [];
    this._stateStack = [];
  }

  save() {
    this._stateStack.push({
      fillStyle: this.fillStyle,
      strokeStyle: this.strokeStyle,
      lineWidth: this.lineWidth,
      lineCap: this.lineCap,
      lineJoin: this.lineJoin,
      globalAlpha: this.globalAlpha,
      globalCompositeOperation: this.globalCompositeOperation,
      font: this.font,
      textAlign: this.textAlign,
      textBaseline: this.textBaseline
    });
    this.commands.push({ op: 'save' });
  }
  restore() {
    const state = this._stateStack.pop();
    if (state == null) {
      throw new RangeError('quickjs_ui Canvas2D restore has no matching save');
    }
    Object.assign(this, state);
    this.commands.push({ op: 'restore' });
  }
  translate(x, y) { this.commands.push({ op: 'translate', x, y }); }
  rotate(radians) { this.commands.push({ op: 'rotate', radians }); }
  scale(x, y = x) { this.commands.push({ op: 'scale', x, y }); }
  clear(color = '#00000000') { this.commands.push({ op: 'clear', color }); }
  clearRect(x, y, width, height) {
    this.commands.push({
      op: 'rect', x, y, width, height,
      fill: '#00000000', blendMode: 'clear'
    });
  }
  clipRect(x, y, width, height) {
    this.commands.push({ op: 'clipRect', x, y, width, height });
  }
  fillRect(x, y, width, height, radius = 0) {
    this.commands.push({
      op: 'rect', x, y, width, height, radius,
      ...this._fillPaint()
    });
  }
  strokeRect(x, y, width, height, radius = 0) {
    this.commands.push({
      op: 'rect', x, y, width, height, radius,
      ...this._strokePaint()
    });
  }
  fillCircle(cx, cy, radius) {
    this.commands.push({ op: 'circle', cx, cy, radius, ...this._fillPaint() });
  }
  strokeCircle(cx, cy, radius) {
    this.commands.push({ op: 'circle', cx, cy, radius, ...this._strokePaint() });
  }
  drawLine(x1, y1, x2, y2) {
    this.commands.push({
      op: 'line', x1, y1, x2, y2, ...this._strokePaint()
    });
  }
  drawImage(image, ...args) {
    const snapshotId = typeof image === 'string'
      ? image
      : image?.snapshotId ?? image?.id;
    const imageSlot = image?.slot;
    if (
      (typeof snapshotId !== 'string' || snapshotId.length === 0) &&
      (typeof imageSlot !== 'string' || imageSlot.length === 0)
    ) {
      throw new TypeError(
        'quickjs_ui drawImage requires a snapshot id or image slot'
      );
    }
    let command;
    if (args.length === 2) {
      command = { dx: args[0], dy: args[1] };
    } else if (args.length === 4) {
      command = {
        dx: args[0], dy: args[1], dWidth: args[2], dHeight: args[3]
      };
    } else if (args.length === 8) {
      command = {
        sx: args[0], sy: args[1], sWidth: args[2], sHeight: args[3],
        dx: args[4], dy: args[5], dWidth: args[6], dHeight: args[7]
      };
    } else {
      throw new TypeError(
        'quickjs_ui drawImage expects 3, 5 or 9 total arguments'
      );
    }
    this.commands.push({
      op: 'image',
      ...(snapshotId == null ? { imageSlot } : { snapshotId }),
      ...command,
      globalAlpha: this.globalAlpha,
      blendMode: this.globalCompositeOperation
    });
  }
  beginPath() { this._path = []; }
  moveTo(x, y) { this._path.push({ op: 'moveTo', x, y }); }
  lineTo(x, y) { this._path.push({ op: 'lineTo', x, y }); }
  quadraticCurveTo(cx, cy, x, y) {
    this._path.push({ op: 'quadraticTo', cx, cy, x, y });
  }
  bezierCurveTo(cx1, cy1, cx2, cy2, x, y) {
    this._path.push({ op: 'cubicTo', cx1, cy1, cx2, cy2, x, y });
  }
  arc(cx, cy, radius, start, end, counterclockwise = false) {
    this._path.push({
      op: 'arc', cx, cy, radius, start, end, counterclockwise
    });
  }
  closePath() { this._path.push({ op: 'close' }); }
  fill() {
    this.commands.push({
      op: 'path', segments: this._path.map((item) => ({ ...item })),
      ...this._fillPaint()
    });
  }
  stroke() {
    this.commands.push({
      op: 'path', segments: this._path.map((item) => ({ ...item })),
      ...this._strokePaint()
    });
  }
  fillText(text, x, y, maxWidth) {
    const font = /^(\d+(?:\.\d+)?)px(?:\s+(.+))?$/.exec(this.font);
    this.commands.push({
      op: 'text', text: String(text), x, y,
      color: this.fillStyle,
      globalAlpha: this.globalAlpha,
      blendMode: this.globalCompositeOperation,
      fontSize: font == null ? 14 : Number(font[1]),
      fontFamily: font?.[2],
      align: this.textAlign,
      baseline: this.textBaseline,
      ...(maxWidth == null ? {} : { maxWidth })
    });
  }

  _fillPaint() {
    return {
      fill: this.fillStyle,
      globalAlpha: this.globalAlpha,
      blendMode: this.globalCompositeOperation
    };
  }
  _strokePaint() {
    return {
      stroke: this.strokeStyle,
      strokeWidth: this.lineWidth,
      strokeCap: this.lineCap,
      strokeJoin: this.lineJoin,
      globalAlpha: this.globalAlpha,
      blendMode: this.globalCompositeOperation
    };
  }
}

export function ListView(props) {
  return node('ListView', props);
}

ListView.builder = function builder(props = {}) {
  const {
    itemCount,
    itemBuilder,
    itemKey,
    prefetchItemCount = 20,
    resetToken = 0,
    key,
    ...listProps
  } = props;
  if (!Number.isInteger(itemCount) || itemCount < 0) {
    throw new TypeError('quickjs_ui ListView.builder itemCount must be a non-negative integer');
  }
  if (typeof itemBuilder !== 'function') {
    throw new TypeError('quickjs_ui ListView.builder requires itemBuilder(index)');
  }
  if (itemKey != null && typeof itemKey !== 'function') {
    throw new TypeError('quickjs_ui ListView.builder itemKey must be a function');
  }
  if (typeof key !== 'string' || key.length === 0) {
    throw new TypeError('quickjs_ui ListView.builder requires a stable string key');
  }
  const batchSize = Number.isInteger(prefetchItemCount) && prefetchItemCount > 0
    ? prefetchItemCount
    : 20;
  const initialEnd = itemCount <= 100 ? itemCount : Math.min(itemCount, batchSize * 2);
  const context = activeListBuilderContext;
  if (context != null && !Object.is(context.resetTokens.get(key), resetToken)) {
    context.resetTokens.set(key, resetToken);
    context.ranges.delete(key);
  }
  const range = context?.ranges.get(key) ?? { start: 0, end: initialEnd };
  const start = Math.max(0, Math.min(range.start, itemCount));
  const end = Math.max(start, Math.min(range.end, itemCount));
  const children = [];
  for (let index = start; index < end; index += 1) {
    const child = itemBuilder(index);
    if (child == null || typeof child !== 'object' || typeof child.type !== 'string') {
      throw new TypeError('quickjs_ui ListView.builder itemBuilder must return a UI node');
    }
    if (itemKey != null && (typeof child.key !== 'string' || child.key.length === 0)) {
      const resolvedKey = itemKey(index);
      if (typeof resolvedKey !== 'string' || resolvedKey.length === 0) {
        throw new TypeError('quickjs_ui ListView.builder itemKey must return a non-empty string');
      }
      child.key = resolvedKey;
    }
    children.push(child);
  }
  return node('ListViewBuilder', {
    ...listProps,
    key,
    itemCount,
    batchStart: start,
    batchEnd: end,
    prefetchItemCount: batchSize,
    resetToken,
    children
  });
};

export function SingleChildScrollView(props) {
  return node('SingleChildScrollView', props);
}

export function GridView(props) {
  return node('GridView', props);
}

export function PageView(props) {
  return node('PageView', props);
}

export function RefreshIndicator(props) {
  return node('RefreshIndicator', props);
}

export function TextField(props) {
  return node('TextField', props);
}

export function TextFormField(props) {
  return node('TextFormField', props);
}

export function GestureDetector(props) {
  return node('GestureDetector', props);
}

export function Stack(props) {
  return node('Stack', props);
}

export function Positioned(props) {
  return node('Positioned', props);
}

export function Padding(props) {
  return node('Padding', props);
}

export function Margin(props) {
  return node('Margin', props);
}

export function Align(props) {
  return node('Align', props);
}

export function Center(props) {
  return node('Center', props);
}

export function SizedBox(props) {
  return node('SizedBox', props);
}

export function Expanded(props) {
  return node('Expanded', props);
}

export function Flexible(props) {
  return node('Flexible', props);
}

export function Spacer(props) {
  return node('Spacer', props);
}

export function Wrap(props) {
  return node('Wrap', props);
}

export function AspectRatio(props) {
  return node('AspectRatio', props);
}

export function ConstrainedBox(props) {
  return node('ConstrainedBox', props);
}

export function SafeArea(props) {
  return node('SafeArea', props);
}

export function Form(props) {
  return node('Form', props);
}

export function Checkbox(props) {
  return node('Checkbox', props);
}

export function Switch(props) {
  return node('Switch', props);
}

export function Slider(props) {
  return node('Slider', props);
}

export function Radio(props) {
  return node('Radio', props);
}

export function DropdownButton(props) {
  return node('DropdownButton', props);
}

export function Icon(props) {
  return node('Icon', props);
}

export function Divider(props) {
  return node('Divider', props);
}

export function VerticalDivider(props) {
  return node('VerticalDivider', props);
}

export function Placeholder(props) {
  return node('Placeholder', props);
}

export function Tooltip(props) {
  return node('Tooltip', props);
}

export function Card(props) {
  return node('Card', props);
}

export function ClipRRect(props) {
  return node('ClipRRect', props);
}

export function BackdropFilter(props) {
  return node('BackdropFilter', props);
}

export function ImageFilter(props = {}) {
  return imageFilter('blur', props);
}

ImageFilter.blur = function blur(props = {}) {
  return imageFilter('blur', props);
};

function imageFilter(type, props = {}) {
  return { type, ...props };
}

export function DecoratedBox(props) {
  return node('DecoratedBox', props);
}

export function RichText(props) {
  return node('RichText', props);
}

export function Scaffold(props) {
  return node('Scaffold', props);
}

export function AppBar(props) {
  return node('AppBar', props);
}

export function BottomNavigationBar(props) {
  return node('BottomNavigationBar', props);
}

export function TabBar(props) {
  return node('TabBar', props);
}

export function TabBarView(props) {
  return node('TabBarView', props);
}

export function Drawer(props) {
  return node('Drawer', props);
}

export function CircularProgressIndicator(props) {
  return node('CircularProgressIndicator', props);
}

export function LinearProgressIndicator(props) {
  return node('LinearProgressIndicator', props);
}

export function SnackBar(props) {
  return node('SnackBar', props);
}

export function Overlay(props) {
  return node('Overlay', props);
}

export function AlertDialog(props) {
  return node('AlertDialog', props);
}

export function BottomSheet(props) {
  return node('BottomSheet', props);
}

export function AnimatedAlign(props) {
  return node('AnimatedAlign', props);
}

export function AnimatedContainer(props) {
  return node('AnimatedContainer', props);
}

export function AnimatedOpacity(props) {
  return node('AnimatedOpacity', props);
}

export function AnimatedPadding(props) {
  return node('AnimatedPadding', props);
}

export function AnimatedSwitcher(props) {
  return node('AnimatedSwitcher', props);
}

export function Hero(props) {
  return node('Hero', props);
}

export const ui = {
  Component,
  defineComponent,
  action,
  event,
  setState,
  eventField,
  Text,
  ElevatedButton,
  TextButton,
  OutlinedButton,
  IconButton,
  InkWell,
  FloatingActionButton,
  Row,
  Column,
  Container,
  Image,
  Svg,
  Canvas,
  SnapshotBoundary,
  animate,
  canvasCommands,
  Canvas2DContext,
  ListView,
  SingleChildScrollView,
  GridView,
  PageView,
  RefreshIndicator,
  TextField,
  TextFormField,
  GestureDetector,
  Stack,
  Positioned,
  Padding,
  Margin,
  Align,
  Center,
  SizedBox,
  Expanded,
  Flexible,
  Spacer,
  Wrap,
  AspectRatio,
  ConstrainedBox,
  SafeArea,
  Form,
  Checkbox,
  Switch,
  Slider,
  Radio,
  DropdownButton,
  Icon,
  Divider,
  VerticalDivider,
  Placeholder,
  Tooltip,
  Card,
  ClipRRect,
  BackdropFilter,
  ImageFilter,
  DecoratedBox,
  RichText,
  Scaffold,
  AppBar,
  BottomNavigationBar,
  TabBar,
  TabBarView,
  Drawer,
  CircularProgressIndicator,
  LinearProgressIndicator,
  Overlay,
  SnackBar,
  AlertDialog,
  BottomSheet,
  AnimatedAlign,
  AnimatedContainer,
  AnimatedOpacity,
  AnimatedPadding,
  AnimatedSwitcher,
  Hero
};
