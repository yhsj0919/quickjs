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
  | 'dispose'
  | 'onInit'
  | 'onMount'
  | 'onShow'
  | 'onHide'
  | 'onPause'
  | 'onResume'
  | 'onDispose'
  | 'methods';

export type QuickjsUiPageMethod<State, Props> = (
  state: State,
  payload?: JsonValue,
  props?: Props,
  event?: QuickjsUiEvent
) => State | Promise<State>;

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
    page: QuickjsUiMethodActions
  ) => QuickjsUiNode;
  [key: string]: unknown;
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
      page: QuickjsUiPageActions<Definition>
    ) => QuickjsUiNode;
  }
): Definition;

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
};
