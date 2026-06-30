export function Page(page) {
  const methods = pageMethods(page);
  const actions = methodActions(methods);
  const defined = {
    ...page,
    init(props) {
      if (typeof page.createState === 'function') {
        return page.createState(props);
      }
      if (typeof page.state === 'function') {
        return page.state(props);
      }
      return {};
    },
    render(state, props) {
      return page.build(state, props, actions);
    }
  };
  if (!page.dispatch) {
    defined.dispatch = function dispatch(state, event, props) {
      const name = event?.method ?? event?.action;
      const handler = methods?.[name];
      if (typeof handler !== 'function') {
        return state;
      }
      return handler(state, event?.payload, props, event);
    };
  }
  return defined;
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

function pageMethods(page) {
  const reserved = new Set([
    'name',
    'props',
    'metadata',
    'state',
    'createState',
    'build',
    'render',
    'init',
    'dispatch',
    'dispose',
    'onInit',
    'onMount',
    'onShow',
    'onHide',
    'onPause',
    'onResume',
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

export function Text(dataOrProps, props = {}) {
  if (typeof dataOrProps === 'string') {
    return node('Text', { data: dataOrProps, ...props });
  }
  return node('Text', dataOrProps);
}

export function ElevatedButton(props) {
  return node('ElevatedButton', props);
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

export const ui = {
  Text,
  ElevatedButton,
  Row,
  Column,
  Container
};
