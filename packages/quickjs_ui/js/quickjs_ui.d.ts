export type JsonValue =
  | null
  | boolean
  | number
  | string
  | JsonValue[]
  | { [key: string]: JsonValue };

export type QuickjsUiEvent = {
  action?: string;
  method?: string;
  payload?: JsonValue;
  source?: string;
  timestamp?: number;
};

export type QuickjsUiMethodActions = Record<
  string,
  (payload?: JsonValue) => QuickjsUiEvent
>;

export type QuickjsUiNode = {
  type: string;
  key?: string;
  child?: QuickjsUiNode;
  children?: QuickjsUiNode[];
  [key: string]: JsonValue | QuickjsUiNode | QuickjsUiNode[] | undefined;
};

export type QuickjsUiReservedPageKeys =
  | 'name'
  | 'props'
  | 'metadata'
  | 'createState'
  | 'state'
  | 'build'
  | 'render'
  | 'init'
  | 'dispatch'
  | 'capabilities'
  | 'mount'
  | 'handleEvent'
  | 'commit'
  | 'setState'
  | 'lifecycle'
  | 'snapshot'
  | 'dispose'
  | 'onInit'
  | 'onMount'
  | 'onShow'
  | 'onHide'
  | 'onPause'
  | 'onResume'
  | 'onRouteEnter'
  | 'onRouteLeave'
  | 'onRouteResult'
  | 'onDispose'
  | 'methods';

export type QuickjsUiPageMethod<State, Props> = (
  state: State,
  payload?: JsonValue,
  props?: Props,
  event?: QuickjsUiEvent
) => Partial<State> | undefined | null | Promise<Partial<State> | undefined | null>;

export type QuickjsUiLifecycleType =
  | 'mount'
  | 'show'
  | 'hide'
  | 'pause'
  | 'resume'
  | 'routeEnter'
  | 'routeLeave'
  | 'routeResult'
  | 'dispose';

export type QuickjsUiLifecycleEvent = {
  type: QuickjsUiLifecycleType;
  payload?: JsonValue;
};

export type QuickjsUiLifecycleHook<State, Props> = (
  state: State,
  payload?: JsonValue,
  props?: Props,
  event?: QuickjsUiLifecycleEvent
) =>
  | Partial<State>
  | undefined
  | null
  | Promise<Partial<State> | undefined | null>;

export type QuickjsUiPageActions<Page> = {
  [Key in keyof Page as Key extends QuickjsUiReservedPageKeys
    ? never
    : Page[Key] extends (...args: any[]) => any
      ? Key
      : never]: (payload?: JsonValue) => QuickjsUiEvent;
};

export type QuickjsUiPage<State = JsonValue, Props = Record<string, JsonValue>> = {
  name?: string;
  props?: Record<string, string>;
  metadata?: Record<string, JsonValue>;
  createState?: (props: Props) => State;
  state?: (props: Props) => State;
  build?: (
    state: State,
    props: Props,
    actions: QuickjsUiMethodActions
  ) => QuickjsUiNode;
  onMount?: QuickjsUiLifecycleHook<State, Props>;
  onShow?: QuickjsUiLifecycleHook<State, Props>;
  onHide?: QuickjsUiLifecycleHook<State, Props>;
  onPause?: QuickjsUiLifecycleHook<State, Props>;
  onResume?: QuickjsUiLifecycleHook<State, Props>;
  onRouteEnter?: QuickjsUiLifecycleHook<State, Props>;
  onRouteLeave?: QuickjsUiLifecycleHook<State, Props>;
  onRouteResult?: QuickjsUiLifecycleHook<State, Props>;
  onDispose?: QuickjsUiLifecycleHook<State, Props>;
  [key: string]: unknown;
};

export type QuickjsUiPageProtocol<
  State = JsonValue,
  Props = Record<string, JsonValue>
> = {
  name?: string;
  metadata?: Record<string, JsonValue>;
  capabilities: () => {
    protocol: 'quickjs_ui.runtime.v1';
    lifecycle: QuickjsUiLifecycleType[];
  };
  mount: (props: Props) => Promise<{ version: number; state: State }>;
  handleEvent: (
    event: QuickjsUiEvent
  ) =>
    | { changed: boolean; version: number }
    | Promise<{ changed: boolean; version: number }>;
  commit: () =>
    | { changed: false; version: number }
    | { changed: true; version: number; node: QuickjsUiNode };
  setState: (patch: Partial<State>) => { changed: boolean; version: number };
  lifecycle: (
    event: QuickjsUiLifecycleEvent
  ) => Promise<{ changed: boolean; version: number }>;
  snapshot: () => { version: number; state: State };
  dispose: () => boolean;
};

export declare function Page<
  State,
  Props = Record<string, JsonValue>,
  Definition extends QuickjsUiPage<State, Props> = QuickjsUiPage<State, Props>
>(
  page: Definition & {
    build?: (
      state: State,
      props: Props,
      actions: QuickjsUiPageActions<Definition>
    ) => QuickjsUiNode;
  }
): QuickjsUiPageProtocol<State, Props>;

export declare function setState<State extends Record<string, JsonValue>>(
  state: State,
  patch: Partial<State>
): State;

export declare function eventField(
  event: QuickjsUiEvent | undefined,
  name: string,
  fallback?: JsonValue
): JsonValue | undefined;

export type MainAxisAlignment =
  | 'start'
  | 'end'
  | 'center'
  | 'spaceBetween'
  | 'spaceAround'
  | 'spaceEvenly';

export type CrossAxisAlignment =
  | 'start'
  | 'end'
  | 'center'
  | 'stretch'
  | 'baseline';

export type Alignment =
  | 'topLeft'
  | 'topCenter'
  | 'topRight'
  | 'centerLeft'
  | 'center'
  | 'centerRight'
  | 'bottomLeft'
  | 'bottomCenter'
  | 'bottomRight';

export type BoxFit =
  | 'fill'
  | 'contain'
  | 'cover'
  | 'fitWidth'
  | 'fitHeight'
  | 'none'
  | 'scaleDown';

export type Axis = 'vertical' | 'horizontal';

export type StackFit = 'loose' | 'expand' | 'passthrough';

export type TextAlign =
  | 'left'
  | 'right'
  | 'center'
  | 'justify'
  | 'start'
  | 'end';

export type FontWeight =
  | 100
  | 200
  | 300
  | 400
  | 500
  | 600
  | 700
  | 800
  | 900
  | 'normal'
  | 'bold'
  | 'w100'
  | 'w200'
  | 'w300'
  | 'w400'
  | 'w500'
  | 'w600'
  | 'w700'
  | 'w800'
  | 'w900';

export type TextInputType =
  | 'text'
  | 'multiline'
  | 'number'
  | 'phone'
  | 'datetime'
  | 'emailAddress'
  | 'url'
  | 'visiblePassword';

export type TextInputAction =
  | 'none'
  | 'unspecified'
  | 'done'
  | 'go'
  | 'search'
  | 'send'
  | 'next'
  | 'previous'
  | 'continueAction'
  | 'join'
  | 'route'
  | 'emergencyCall'
  | 'newline';

export type ThemeColorToken =
  | '$primary'
  | '$onPrimary'
  | '$primaryContainer'
  | '$onPrimaryContainer'
  | '$secondary'
  | '$onSecondary'
  | '$secondaryContainer'
  | '$onSecondaryContainer'
  | '$tertiary'
  | '$onTertiary'
  | '$surface'
  | '$onSurface'
  | '$surfaceVariant'
  | '$background'
  | '$onBackground'
  | '$error'
  | '$onError'
  | '$outline';

export type ThemeTextStyleToken =
  | '$text.displayLarge'
  | '$text.displayMedium'
  | '$text.displaySmall'
  | '$text.headlineLarge'
  | '$text.headlineMedium'
  | '$text.headlineSmall'
  | '$text.titleLarge'
  | '$text.titleMedium'
  | '$text.titleSmall'
  | '$text.bodyLarge'
  | '$text.bodyMedium'
  | '$text.bodySmall'
  | '$text.labelLarge'
  | '$text.labelMedium'
  | '$text.labelSmall';

export type ColorValue = string | number | ThemeColorToken;

export type TextStyle = {
  color?: ColorValue;
  fontSize?: number;
  fontWeight?: FontWeight;
};

export type EdgeInsets =
  | number
  | {
      all?: number;
      left?: number;
      top?: number;
      right?: number;
      bottom?: number;
      horizontal?: number;
      vertical?: number;
    };

export type TextProps = {
  data?: string;
  text?: string;
  textAlign?: TextAlign;
  style?: TextStyle | ThemeTextStyleToken;
};

export type ButtonProps = {
  child: QuickjsUiNode;
  onPressed?: QuickjsUiEvent;
};

export type FlexProps = {
  mainAxisAlignment?: MainAxisAlignment;
  crossAxisAlignment?: CrossAxisAlignment;
  gap?: number;
  children?: QuickjsUiNode[];
};

export type ContainerProps = {
  child?: QuickjsUiNode;
  width?: number;
  height?: number;
  padding?: EdgeInsets;
  margin?: EdgeInsets;
  alignment?: Alignment;
  color?: ColorValue;
  backgroundColor?: ColorValue;
};

export type ImageProps = {
  src: string;
  width?: number;
  height?: number;
  fit?: BoxFit;
};

export type ListViewProps = {
  children?: QuickjsUiNode[];
  scrollDirection?: Axis;
  shrinkWrap?: boolean;
  padding?: EdgeInsets;
  gap?: number;
};

export type TextFieldProps = {
  value?: string;
  initialValue?: string;
  labelText?: string;
  hintText?: string;
  enabled?: boolean;
  autofocus?: boolean;
  obscureText?: boolean;
  maxLines?: number;
  keyboardType?: TextInputType;
  textInputAction?: TextInputAction;
  onChanged?: QuickjsUiEvent;
  onSubmitted?: QuickjsUiEvent;
  onFocus?: QuickjsUiEvent;
  onBlur?: QuickjsUiEvent;
};

export type StackProps = {
  children?: QuickjsUiNode[];
  alignment?: Alignment;
  fit?: StackFit;
};

export type PaddingProps = {
  padding?: EdgeInsets;
  child?: QuickjsUiNode;
};

export type CenterProps = {
  child?: QuickjsUiNode;
  widthFactor?: number;
  heightFactor?: number;
};

export type SizedBoxProps = {
  child?: QuickjsUiNode;
  width?: number;
  height?: number;
};

export type FormProps = {
  child?: QuickjsUiNode;
  autovalidateMode?: string;
  [key: string]: JsonValue | QuickjsUiNode | undefined;
};

export type CheckboxProps = {
  value?: boolean;
  tristate?: boolean;
  onChanged?: QuickjsUiEvent;
  [key: string]: JsonValue | QuickjsUiEvent | undefined;
};

export type SwitchProps = {
  value?: boolean;
  onChanged?: QuickjsUiEvent;
  [key: string]: JsonValue | QuickjsUiEvent | undefined;
};

export type SliderProps = {
  value?: number;
  min?: number;
  max?: number;
  divisions?: number;
  label?: string;
  onChanged?: QuickjsUiEvent;
  onChangeStart?: QuickjsUiEvent;
  onChangeEnd?: QuickjsUiEvent;
  [key: string]: JsonValue | QuickjsUiEvent | undefined;
};

export type RadioProps = {
  value?: JsonValue;
  groupValue?: JsonValue;
  onChanged?: QuickjsUiEvent;
  [key: string]: JsonValue | QuickjsUiEvent | undefined;
};

export type DropdownButtonProps = {
  value?: JsonValue;
  items?: JsonValue[];
  onChanged?: QuickjsUiEvent;
  hint?: QuickjsUiNode;
  [key: string]: JsonValue | QuickjsUiEvent | QuickjsUiNode | undefined;
};

export declare function Text(
  data: string,
  props?: Omit<TextProps, 'data'>
): QuickjsUiNode;
export declare function Text(props: TextProps): QuickjsUiNode;
export declare function ElevatedButton(props: ButtonProps): QuickjsUiNode;
export declare function Row(props: FlexProps): QuickjsUiNode;
export declare function Column(props: FlexProps): QuickjsUiNode;
export declare function Container(props: ContainerProps): QuickjsUiNode;
export declare function Image(props: ImageProps): QuickjsUiNode;
export declare function ListView(props: ListViewProps): QuickjsUiNode;
export declare function TextField(props: TextFieldProps): QuickjsUiNode;
export declare function Stack(props: StackProps): QuickjsUiNode;
export declare function Padding(props: PaddingProps): QuickjsUiNode;
export declare function Center(props: CenterProps): QuickjsUiNode;
export declare function SizedBox(props: SizedBoxProps): QuickjsUiNode;
export declare function Form(props: FormProps): QuickjsUiNode;
export declare function Checkbox(props: CheckboxProps): QuickjsUiNode;
export declare function Switch(props: SwitchProps): QuickjsUiNode;
export declare function Slider(props: SliderProps): QuickjsUiNode;
export declare function Radio(props: RadioProps): QuickjsUiNode;
export declare function DropdownButton(
  props: DropdownButtonProps
): QuickjsUiNode;

export declare const ui: {
  Text(data: string, props?: Omit<TextProps, 'data'>): QuickjsUiNode;
  Text(props: TextProps): QuickjsUiNode;
  ElevatedButton(props: ButtonProps): QuickjsUiNode;
  Row(props: FlexProps): QuickjsUiNode;
  Column(props: FlexProps): QuickjsUiNode;
  Container(props: ContainerProps): QuickjsUiNode;
  Image(props: ImageProps): QuickjsUiNode;
  ListView(props: ListViewProps): QuickjsUiNode;
  TextField(props: TextFieldProps): QuickjsUiNode;
  Stack(props: StackProps): QuickjsUiNode;
  Padding(props: PaddingProps): QuickjsUiNode;
  Center(props: CenterProps): QuickjsUiNode;
  SizedBox(props: SizedBoxProps): QuickjsUiNode;
  Form(props: FormProps): QuickjsUiNode;
  Checkbox(props: CheckboxProps): QuickjsUiNode;
  Switch(props: SwitchProps): QuickjsUiNode;
  Slider(props: SliderProps): QuickjsUiNode;
  Radio(props: RadioProps): QuickjsUiNode;
  DropdownButton(props: DropdownButtonProps): QuickjsUiNode;
};

export type QuickjsUiHostApi = {
  toast?: (
    message: string,
    options?: Record<string, JsonValue>
  ) => Promise<JsonValue>;
  confirm?: (
    message: string,
    options?: Record<string, JsonValue>
  ) => Promise<boolean>;
  dialog?: (payload: {
    title?: string;
    message?: string;
    content?: QuickjsUiNode;
    actions?: JsonValue[];
    [key: string]: JsonValue | QuickjsUiNode | undefined;
  }) => Promise<JsonValue>;
  snackbar?: (payload: {
    message: string;
    [key: string]: JsonValue | undefined;
  }) => Promise<JsonValue>;
  bottomSheet?: (payload: {
    title?: string;
    message?: string;
    content?: QuickjsUiNode;
    [key: string]: JsonValue | QuickjsUiNode | undefined;
  }) => Promise<JsonValue>;
  navigationIntent?: (
    intent: Record<string, JsonValue>
  ) => Promise<JsonValue>;
  clipboard?: {
    readText(): Promise<string | null>;
    writeText(text: string): Promise<JsonValue>;
  };
  storage?: {
    getItem(key: string): Promise<JsonValue>;
    setItem(key: string, value: JsonValue): Promise<boolean>;
    removeItem(key: string): Promise<JsonValue>;
  };
  network?: (request: Record<string, JsonValue>) => Promise<JsonValue>;
  fileSystem?: (operation: Record<string, JsonValue>) => Promise<JsonValue>;
  nativeCall?: (method: string, payload?: JsonValue) => Promise<JsonValue>;
};

export type QuickjsUiNavigationTarget =
  | string
  | {
      route?: string;
      path?: string;
      params?: Record<string, JsonValue>;
      [key: string]: JsonValue | undefined;
    };

export type QuickjsUiNavigationApi = {
  push?: (
    target: QuickjsUiNavigationTarget,
    params?: Record<string, JsonValue>
  ) => Promise<JsonValue>;
  replace?: (
    target: QuickjsUiNavigationTarget,
    params?: Record<string, JsonValue>
  ) => Promise<boolean>;
  pop?: (result?: JsonValue) => boolean;
};

declare global {
  var quickjsUiHost: QuickjsUiHostApi | undefined;
  var quickjsUiNavigation: QuickjsUiNavigationApi | undefined;
}
