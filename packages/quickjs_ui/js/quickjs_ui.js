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
    },
    lifecycle(state, event, props) {
      const type = event?.type;
      const hook =
        type === 'mount' ? page.onMount :
        type === 'show' ? page.onShow :
        type === 'hide' ? page.onHide :
        type === 'pause' ? page.onPause :
        type === 'resume' ? page.onResume :
        type === 'routeEnter' ? page.onRouteEnter :
        type === 'routeLeave' ? page.onRouteLeave :
        type === 'routeResult' ? page.onRouteResult :
        type === 'dispose' ? page.onDispose :
        undefined;
      if (typeof hook !== 'function') {
        return null;
      }
      const result = hook(state, event?.payload, props, event);
      return result === undefined ? null : result;
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

export function action(name, payload) {
  return method(name, payload);
}

export const event = action;

export function Component(render) {
  if (typeof render !== 'function') {
    throw new TypeError('quickjs_ui Component render must be a function');
  }
  return function component(props = {}, actions = {}) {
    const node = render(props ?? {}, actions ?? {});
    if (node == null || typeof node !== 'object' || typeof node.type !== 'string') {
      throw new TypeError('quickjs_ui Component must return a UI node object');
    }
    return node;
  };
}

export const defineComponent = Component;

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

export function Image(props) {
  return node('Image', props);
}

export function ListView(props) {
  return node('ListView', props);
}

export function TextField(props) {
  return node('TextField', props);
}

export function Stack(props) {
  return node('Stack', props);
}

export function Padding(props) {
  return node('Padding', props);
}

export function Center(props) {
  return node('Center', props);
}

export function SizedBox(props) {
  return node('SizedBox', props);
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

export function Radio(props) {
  return node('Radio', props);
}

export function DropdownButton(props) {
  return node('DropdownButton', props);
}

export const ui = {
  Component,
  defineComponent,
  action,
  event,
  Text,
  ElevatedButton,
  Row,
  Column,
  Container,
  Image,
  ListView,
  TextField,
  Stack,
  Padding,
  Center,
  SizedBox,
  Form,
  Checkbox,
  Switch,
  Radio,
  DropdownButton
};
