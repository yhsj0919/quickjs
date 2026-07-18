export type JsonValue =
  | null
  | boolean
  | number
  | string
  | JsonValue[]
  | { [key: string]: JsonValue };

export declare const quickjsUiRuntimeProtocol: 'quickjs_ui.runtime.v1';
export declare const quickjsUiSchemaVersion: 1;
export declare const quickjsUiHelperVersion: 1;

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
  | 'schemaVersion'
  | 'minimumQuickjsUiVersion'
  | 'minQuickjsUiVersion'
  | 'unknownProps'
  | 'deprecatedProps'
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
  schemaVersion?: number;
  minimumQuickjsUiVersion?: number;
  minQuickjsUiVersion?: number;
  unknownProps?: 'ignore' | 'warn' | 'error';
  deprecatedProps?: Record<string, string>;
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
    schemaVersion: number;
    helperVersion: number;
    minimumQuickjsUiVersion: number;
    unknownProps: 'ignore' | 'warn' | 'error';
    deprecatedProps: Record<string, string>;
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

export type FilterQuality = 'none' | 'low' | 'medium' | 'high';

export type StackFit = 'loose' | 'expand' | 'passthrough';

export type ClipBehavior =
  | 'none'
  | 'hardEdge'
  | 'antiAlias'
  | 'antiAliasWithSaveLayer';

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

export type SubmitFocusAction = 'none' | 'next' | 'previous' | 'unfocus';

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

export type ThemeSpaceToken =
  | '$space.none'
  | '$space.xxs'
  | '$space.xs'
  | '$space.sm'
  | '$space.md'
  | '$space.lg'
  | '$space.xl'
  | '$space.xxl';

export type ThemeRadiusToken =
  | '$radius.none'
  | '$radius.xs'
  | '$radius.sm'
  | '$radius.md'
  | '$radius.lg'
  | '$radius.xl'
  | '$radius.full';

export type ThemeElevationToken =
  | '$elevation.none'
  | '$elevation.xs'
  | '$elevation.sm'
  | '$elevation.md'
  | '$elevation.lg'
  | '$elevation.xl';

export type ColorValue = string | number | ThemeColorToken;
export type SpaceValue = number | ThemeSpaceToken | string;
export type RadiusValue = number | ThemeRadiusToken | string;
export type ElevationValue = number | ThemeElevationToken | string;

export type QuickjsUiResourceKind =
  | 'asset'
  | 'file'
  | 'network'
  | 'http'
  | 'https'
  | 'data'
  | 'custom';

export type QuickjsUiResourceReference =
  | string
  | {
      uri?: string;
      url?: string;
      src?: string;
      source?: string;
      path?: string;
      kind?: QuickjsUiResourceKind;
      type?: QuickjsUiResourceKind;
      mimeType?: string;
      mime?: string;
      sha256?: string;
      checksum?: string;
      cacheKey?: string;
      headers?: Record<string, string>;
    };

export type TextStyle = {
  color?: ColorValue;
  fontSize?: SpaceValue;
  fontWeight?: FontWeight;
  letterSpacing?: SpaceValue;
  height?: number;
};

export type EdgeInsets =
  | SpaceValue
  | {
      all?: SpaceValue;
      value?: SpaceValue;
      left?: SpaceValue;
      top?: SpaceValue;
      right?: SpaceValue;
      bottom?: SpaceValue;
      horizontal?: SpaceValue;
      vertical?: SpaceValue;
    };

export type BorderRadius =
  | RadiusValue
  | {
      all?: RadiusValue;
      radius?: RadiusValue;
      topLeft?: RadiusValue;
      topRight?: RadiusValue;
      bottomLeft?: RadiusValue;
      bottomRight?: RadiusValue;
    };

export type AccessibilityRole =
  | 'button'
  | 'image'
  | 'textField'
  | 'header';

export type Curve =
  | 'linear'
  | 'ease'
  | 'easeIn'
  | 'easeOut'
  | 'easeInOut'
  | 'fastOutSlowIn'
  | 'bounceIn'
  | 'bounceOut'
  | 'elasticIn'
  | 'elasticOut';

export type AccessibilityProps = {
  semanticLabel?: string;
  semanticsLabel?: string;
  semanticHint?: string;
  tooltip?: string;
  role?: AccessibilityRole;
  enabled?: boolean;
  focusOrder?: number;
  onTap?: QuickjsUiEvent;
  onLongPress?: QuickjsUiEvent;
  onDoubleTap?: QuickjsUiEvent;
  onDragStart?: QuickjsUiEvent;
  onDragUpdate?: QuickjsUiEvent;
  onDragEnd?: QuickjsUiEvent;
  onSwipe?: QuickjsUiEvent;
};

export type ScrollableProps = {
  initialScrollOffset?: number;
  scrollToOffset?: number;
  scrollToKey?: string;
  scrollToken?: number;
  scrollToToken?: number;
  scrollDurationMs?: number;
  scrollCurve?: Curve;
  onScroll?: QuickjsUiEvent;
};

export type TextProps = AccessibilityProps & {
  data?: string;
  text?: string;
  textAlign?: TextAlign;
  style?: TextStyle | ThemeTextStyleToken;
};

export type ButtonProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  label?: string;
  onPressed?: QuickjsUiEvent;
};

export type IconButtonProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  icon?: string;
  iconSize?: number;
  color?: ColorValue;
  onPressed?: QuickjsUiEvent;
};

export type FlexProps = AccessibilityProps & {
  mainAxisAlignment?: MainAxisAlignment;
  crossAxisAlignment?: CrossAxisAlignment;
  gap?: SpaceValue;
  children?: QuickjsUiNode[];
};

export type PositionedProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  left?: number;
  top?: number;
  right?: number;
  bottom?: number;
  width?: number;
  height?: number;
};

export type FlexChildProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  flex?: number;
  fit?: 'tight' | 'loose';
};

export type WrapProps = AccessibilityProps & {
  children?: QuickjsUiNode[];
  direction?: Axis;
  alignment?:
    | 'start'
    | 'end'
    | 'center'
    | 'spaceBetween'
    | 'spaceAround'
    | 'spaceEvenly';
  runAlignment?: WrapProps['alignment'];
  crossAxisAlignment?: 'start' | 'end' | 'center';
  spacing?: SpaceValue;
  runSpacing?: SpaceValue;
};

export type AspectRatioProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  aspectRatio: number;
};

export type ConstrainedBoxProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  minWidth?: number;
  maxWidth?: number;
  minHeight?: number;
  maxHeight?: number;
};

export type SafeAreaProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  left?: boolean;
  top?: boolean;
  right?: boolean;
  bottom?: boolean;
  minimum?: EdgeInsets;
};

export type ContainerProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  width?: number;
  height?: number;
  padding?: EdgeInsets;
  margin?: EdgeInsets;
  alignment?: Alignment;
  color?: ColorValue;
  backgroundColor?: ColorValue;
  borderRadius?: BorderRadius;
  borderColor?: ColorValue;
  borderWidth?: number;
  elevation?: ElevationValue;
};

export type ImageProps = AccessibilityProps & {
  src?: QuickjsUiResourceReference;
  source?: QuickjsUiResourceReference;
  uri?: QuickjsUiResourceReference;
  url?: QuickjsUiResourceReference;
  path?: QuickjsUiResourceReference;
  width?: number;
  height?: number;
  fit?: BoxFit;
  cacheWidth?: number;
  cacheHeight?: number;
  filterQuality?: FilterQuality;
  gaplessPlayback?: boolean;
  excludeFromSemantics?: boolean;
};

export type SvgProps = AccessibilityProps & {
  src?: QuickjsUiResourceReference;
  source?: QuickjsUiResourceReference;
  uri?: QuickjsUiResourceReference;
  url?: QuickjsUiResourceReference;
  path?: QuickjsUiResourceReference;
  data?: string;
  string?: string;
  svg?: string;
  width?: number;
  height?: number;
  fit?: BoxFit;
  color?: ColorValue;
  excludeFromSemantics?: boolean;
};

export type ListViewProps = AccessibilityProps & ScrollableProps & {
  children?: QuickjsUiNode[];
  scrollDirection?: Axis;
  shrinkWrap?: boolean;
  padding?: EdgeInsets;
  gap?: SpaceValue;
  animateItems?: boolean;
  itemTransitionDurationMs?: number;
  itemTransitionCurve?: Curve;
  itemExtent?: number;
  cacheExtent?: number;
  addAutomaticKeepAlives?: boolean;
  addRepaintBoundaries?: boolean;
};

export type ListViewBuilderProps = Omit<ListViewProps, 'children' | 'animateItems'> & {
  key: string;
  itemCount: number;
  itemBuilder: (index: number) => QuickjsUiNode;
  itemKey?: (index: number) => string;
  prefetchItemCount?: number;
  estimatedItemExtent?: number;
  hasMore?: boolean;
  loading?: boolean;
  loadMoreThreshold?: number;
  loadingText?: string;
  onLoadMore?: QuickjsUiEvent;
  resetToken?: string | number;
};

export type GridViewProps = AccessibilityProps & ScrollableProps & {
  children?: QuickjsUiNode[];
  scrollDirection?: Axis;
  shrinkWrap?: boolean;
  padding?: EdgeInsets;
  crossAxisCount?: number;
  childAspectRatio?: number;
  crossAxisSpacing?: SpaceValue;
  mainAxisSpacing?: SpaceValue;
};

export type PageViewProps = AccessibilityProps & ScrollableProps & {
  children?: QuickjsUiNode[];
  scrollDirection?: Axis;
  pageSnapping?: boolean;
  onPageChanged?: QuickjsUiEvent;
};

export type RefreshIndicatorProps = AccessibilityProps & {
  child: QuickjsUiNode;
  onRefresh?: QuickjsUiEvent;
};

export type SingleChildScrollViewProps = AccessibilityProps & ScrollableProps & {
  children?: QuickjsUiNode[];
  padding?: EdgeInsets;
  gap?: SpaceValue;
};

export type TextFieldProps = AccessibilityProps & {
  focusId?: string;
  value?: string;
  initialValue?: string;
  labelText?: string;
  hintText?: string;
  helperText?: string;
  errorText?: string;
  enabled?: boolean;
  autofocus?: boolean;
  focusOnMount?: boolean;
  requestFocus?: boolean;
  clearFocus?: boolean;
  obscureText?: boolean;
  maxLines?: number;
  keyboardType?: TextInputType;
  textInputAction?: TextInputAction;
  submitFocusAction?: SubmitFocusAction;
  onChanged?: QuickjsUiEvent;
  onSubmitted?: QuickjsUiEvent;
  onEditingComplete?: QuickjsUiEvent;
  onFocus?: QuickjsUiEvent;
  onBlur?: QuickjsUiEvent;
  onSelectionChanged?: QuickjsUiEvent;
};

export type StackProps = AccessibilityProps & {
  children?: QuickjsUiNode[];
  alignment?: Alignment;
  fit?: StackFit;
};

export type PaddingProps = AccessibilityProps & {
  padding?: EdgeInsets;
  child?: QuickjsUiNode;
};

export type MarginProps = AccessibilityProps & {
  margin?: EdgeInsets;
  padding?: EdgeInsets;
  value?: EdgeInsets;
  child?: QuickjsUiNode;
};

export type CenterProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  widthFactor?: number;
  heightFactor?: number;
};

export type AlignProps = CenterProps & {
  alignment?: Alignment;
};

export type SizedBoxProps = AccessibilityProps & {
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

export type IconProps = AccessibilityProps & {
  icon?: string;
  name?: string;
  size?: number;
  color?: ColorValue;
};

export type DividerProps = AccessibilityProps & {
  height?: number;
  thickness?: number;
  indent?: number;
  endIndent?: number;
  color?: ColorValue;
};

export type PlaceholderProps = AccessibilityProps & {
  color?: ColorValue;
  strokeWidth?: number;
  fallbackWidth?: number;
  fallbackHeight?: number;
};

export type GestureDetectorProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  onTap?: QuickjsUiEvent;
  onDoubleTap?: QuickjsUiEvent;
  onLongPress?: QuickjsUiEvent;
  onDragStart?: QuickjsUiEvent;
  onDragUpdate?: QuickjsUiEvent;
  onDragEnd?: QuickjsUiEvent;
  onSwipe?: QuickjsUiEvent;
};

export type TooltipProps = AccessibilityProps & {
  message: string;
  child?: QuickjsUiNode;
  waitDurationMs?: number;
  showDurationMs?: number;
};

export type CardProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  color?: ColorValue;
  elevation?: ElevationValue;
  margin?: EdgeInsets;
  clipBehavior?: ClipBehavior;
};

export type DecoratedBoxProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  position?: 'background' | 'foreground';
  color?: ColorValue;
  backgroundColor?: ColorValue;
  decoration?: JsonValue;
  borderRadius?: BorderRadius;
  borderColor?: ColorValue;
  borderWidth?: number;
};

export type ClipRRectProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  borderRadius?: BorderRadius;
  clipBehavior?: ClipBehavior;
};

export type TextSpanValue =
  | string
  | { text?: string; style?: TextStyle | ThemeTextStyleToken; children?: TextSpanValue[] };

export type RichTextProps = AccessibilityProps & {
  text?: string | TextSpanValue[];
  spans?: TextSpanValue[];
  textAlign?: TextAlign;
  style?: TextStyle | ThemeTextStyleToken;
};

export type ScaffoldProps = AccessibilityProps & {
  body?: QuickjsUiNode;
  child?: QuickjsUiNode;
  appBar?: QuickjsUiNode;
  drawer?: QuickjsUiNode;
  bottomNavigationBar?: QuickjsUiNode;
  floatingActionButton?: QuickjsUiNode;
  backgroundColor?: ColorValue;
  tabLength?: number;
  initialTabIndex?: number;
};

export type AppBarProps = AccessibilityProps & {
  title?: QuickjsUiNode;
  titleText?: string;
  leading?: QuickjsUiNode;
  actions?: QuickjsUiNode[];
  bottom?: QuickjsUiNode;
  backgroundColor?: ColorValue;
  foregroundColor?: ColorValue;
  centerTitle?: boolean;
  elevation?: ElevationValue;
};

export type BottomNavigationBarItemProps = {
  label: string;
  icon?: QuickjsUiNode;
  iconName?: string;
  activeIcon?: QuickjsUiNode;
  tooltip?: string;
};

export type BottomNavigationBarProps = AccessibilityProps & {
  currentIndex?: number;
  typeMode?: 'fixed' | 'shifting';
  items: BottomNavigationBarItemProps[];
  onTap?: QuickjsUiEvent;
};

export type TabValue =
  | string
  | { text?: string; label?: string; icon?: QuickjsUiNode; child?: QuickjsUiNode };

export type TabBarProps = AccessibilityProps & {
  tabs: TabValue[];
  isScrollable?: boolean;
  onTap?: QuickjsUiEvent;
};

export type TabBarViewProps = AccessibilityProps & {
  children?: QuickjsUiNode[];
};

export type DrawerProps = AccessibilityProps & {
  child?: QuickjsUiNode;
};

export type ProgressIndicatorProps = AccessibilityProps & {
  value?: number;
  color?: ColorValue;
  backgroundColor?: ColorValue;
  strokeWidth?: number;
  minHeight?: number;
};

export type SnackBarProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  content?: string;
  text?: string;
  visible?: boolean;
  durationMs?: number;
  backgroundColor?: ColorValue;
};

export type AlertDialogProps = AccessibilityProps & {
  visible?: boolean;
  title?: QuickjsUiNode;
  titleText?: string;
  content?: QuickjsUiNode;
  contentText?: string;
  actions?: QuickjsUiNode[];
  backgroundColor?: ColorValue;
};

export type BottomSheetProps = AccessibilityProps & {
  visible?: boolean;
  child?: QuickjsUiNode;
  onClosing?: QuickjsUiEvent;
  backgroundColor?: ColorValue;
};

export type AnimatedAlignProps = AlignProps & {
  durationMs?: number;
  animationDurationMs?: number;
  animationCurve?: Curve;
};

export type AnimatedContainerProps = ContainerProps & {
  durationMs?: number;
  animationDurationMs?: number;
  animationCurve?: Curve;
};

export type AnimatedOpacityProps = AccessibilityProps & {
  opacity: number;
  child?: QuickjsUiNode;
  durationMs?: number;
  animationDurationMs?: number;
  animationCurve?: Curve;
};

export type AnimatedPaddingProps = PaddingProps & {
  durationMs?: number;
  animationDurationMs?: number;
  animationCurve?: Curve;
};

export type HeroProps = AccessibilityProps & {
  tag: string | number | boolean;
  child: QuickjsUiNode;
  transitionOnUserGestures?: boolean;
};

export type AnimatedSwitcherProps = AccessibilityProps & {
  child?: QuickjsUiNode;
  durationMs?: number;
  animationDurationMs?: number;
  reverseDurationMs?: number;
  switchInCurve?: Curve;
  switchOutCurve?: Curve;
};

export declare function Text(
  data: string,
  props?: Omit<TextProps, 'data'>
): QuickjsUiNode;
export declare function Text(props: TextProps): QuickjsUiNode;
export declare function ElevatedButton(props: ButtonProps): QuickjsUiNode;
export declare function TextButton(props: ButtonProps): QuickjsUiNode;
export declare function OutlinedButton(props: ButtonProps): QuickjsUiNode;
export declare function IconButton(props: IconButtonProps): QuickjsUiNode;
export declare function InkWell(props: AccessibilityProps & { child?: QuickjsUiNode }): QuickjsUiNode;
export declare function FloatingActionButton(props: IconButtonProps): QuickjsUiNode;
export declare function Row(props: FlexProps): QuickjsUiNode;
export declare function Column(props: FlexProps): QuickjsUiNode;
export declare function Container(props: ContainerProps): QuickjsUiNode;
export declare function Image(props: ImageProps): QuickjsUiNode;
export declare function Svg(props: SvgProps): QuickjsUiNode;
export declare function ListView(props: ListViewProps): QuickjsUiNode;
export declare namespace ListView {
  function builder(props: ListViewBuilderProps): QuickjsUiNode;
}
export declare function SingleChildScrollView(
  props: SingleChildScrollViewProps
): QuickjsUiNode;
export declare function GridView(props: GridViewProps): QuickjsUiNode;
export declare function PageView(props: PageViewProps): QuickjsUiNode;
export declare function RefreshIndicator(
  props: RefreshIndicatorProps
): QuickjsUiNode;
export declare function TextField(props: TextFieldProps): QuickjsUiNode;
export declare function TextFormField(props: TextFieldProps): QuickjsUiNode;
export declare function GestureDetector(props: GestureDetectorProps): QuickjsUiNode;
export declare function Stack(props: StackProps): QuickjsUiNode;
export declare function Positioned(props: PositionedProps): QuickjsUiNode;
export declare function Padding(props: PaddingProps): QuickjsUiNode;
export declare function Margin(props: MarginProps): QuickjsUiNode;
export declare function Align(props: AlignProps): QuickjsUiNode;
export declare function Center(props: CenterProps): QuickjsUiNode;
export declare function SizedBox(props: SizedBoxProps): QuickjsUiNode;
export declare function Expanded(props: FlexChildProps): QuickjsUiNode;
export declare function Flexible(props: FlexChildProps): QuickjsUiNode;
export declare function Spacer(props?: { flex?: number }): QuickjsUiNode;
export declare function Wrap(props: WrapProps): QuickjsUiNode;
export declare function AspectRatio(props: AspectRatioProps): QuickjsUiNode;
export declare function ConstrainedBox(
  props: ConstrainedBoxProps
): QuickjsUiNode;
export declare function SafeArea(props: SafeAreaProps): QuickjsUiNode;
export declare function Form(props: FormProps): QuickjsUiNode;
export declare function Checkbox(props: CheckboxProps): QuickjsUiNode;
export declare function Switch(props: SwitchProps): QuickjsUiNode;
export declare function Slider(props: SliderProps): QuickjsUiNode;
export declare function Radio(props: RadioProps): QuickjsUiNode;
export declare function DropdownButton(
  props: DropdownButtonProps
): QuickjsUiNode;
export declare function Icon(props: IconProps): QuickjsUiNode;
export declare function Divider(props?: DividerProps): QuickjsUiNode;
export declare function VerticalDivider(props?: DividerProps): QuickjsUiNode;
export declare function Placeholder(props?: PlaceholderProps): QuickjsUiNode;
export declare function Tooltip(props: TooltipProps): QuickjsUiNode;
export declare function Card(props: CardProps): QuickjsUiNode;
export declare function ClipRRect(props: ClipRRectProps): QuickjsUiNode;
export declare function DecoratedBox(props: DecoratedBoxProps): QuickjsUiNode;
export declare function RichText(props: RichTextProps): QuickjsUiNode;
export declare function Scaffold(props: ScaffoldProps): QuickjsUiNode;
export declare function AppBar(props: AppBarProps): QuickjsUiNode;
export declare function BottomNavigationBar(
  props: BottomNavigationBarProps
): QuickjsUiNode;
export declare function TabBar(props: TabBarProps): QuickjsUiNode;
export declare function TabBarView(props: TabBarViewProps): QuickjsUiNode;
export declare function Drawer(props: DrawerProps): QuickjsUiNode;
export declare function CircularProgressIndicator(
  props?: ProgressIndicatorProps
): QuickjsUiNode;
export declare function LinearProgressIndicator(
  props?: ProgressIndicatorProps
): QuickjsUiNode;
export declare function SnackBar(props: SnackBarProps): QuickjsUiNode;
export declare function AlertDialog(props: AlertDialogProps): QuickjsUiNode;
export declare function BottomSheet(props: BottomSheetProps): QuickjsUiNode;
export declare function AnimatedAlign(props: AnimatedAlignProps): QuickjsUiNode;
export declare function AnimatedContainer(props: AnimatedContainerProps): QuickjsUiNode;
export declare function AnimatedOpacity(props: AnimatedOpacityProps): QuickjsUiNode;
export declare function AnimatedPadding(props: AnimatedPaddingProps): QuickjsUiNode;
export declare function AnimatedSwitcher(
  props: AnimatedSwitcherProps
): QuickjsUiNode;
export declare function Hero(props: HeroProps): QuickjsUiNode;

export declare const ui: {
  Text(data: string, props?: Omit<TextProps, 'data'>): QuickjsUiNode;
  Text(props: TextProps): QuickjsUiNode;
  ElevatedButton(props: ButtonProps): QuickjsUiNode;
  TextButton(props: ButtonProps): QuickjsUiNode;
  OutlinedButton(props: ButtonProps): QuickjsUiNode;
  IconButton(props: IconButtonProps): QuickjsUiNode;
  InkWell(props: AccessibilityProps & { child?: QuickjsUiNode }): QuickjsUiNode;
  FloatingActionButton(props: IconButtonProps): QuickjsUiNode;
  Row(props: FlexProps): QuickjsUiNode;
  Column(props: FlexProps): QuickjsUiNode;
  Container(props: ContainerProps): QuickjsUiNode;
  Image(props: ImageProps): QuickjsUiNode;
  Svg(props: SvgProps): QuickjsUiNode;
  ListView(props: ListViewProps): QuickjsUiNode;
  SingleChildScrollView(props: SingleChildScrollViewProps): QuickjsUiNode;
  GridView(props: GridViewProps): QuickjsUiNode;
  PageView(props: PageViewProps): QuickjsUiNode;
  RefreshIndicator(props: RefreshIndicatorProps): QuickjsUiNode;
  TextField(props: TextFieldProps): QuickjsUiNode;
  TextFormField(props: TextFieldProps): QuickjsUiNode;
  GestureDetector(props: GestureDetectorProps): QuickjsUiNode;
  Stack(props: StackProps): QuickjsUiNode;
  Positioned(props: PositionedProps): QuickjsUiNode;
  Padding(props: PaddingProps): QuickjsUiNode;
  Margin(props: MarginProps): QuickjsUiNode;
  Align(props: AlignProps): QuickjsUiNode;
  Center(props: CenterProps): QuickjsUiNode;
  SizedBox(props: SizedBoxProps): QuickjsUiNode;
  Expanded(props: FlexChildProps): QuickjsUiNode;
  Flexible(props: FlexChildProps): QuickjsUiNode;
  Spacer(props?: { flex?: number }): QuickjsUiNode;
  Wrap(props: WrapProps): QuickjsUiNode;
  AspectRatio(props: AspectRatioProps): QuickjsUiNode;
  ConstrainedBox(props: ConstrainedBoxProps): QuickjsUiNode;
  SafeArea(props: SafeAreaProps): QuickjsUiNode;
  Form(props: FormProps): QuickjsUiNode;
  Checkbox(props: CheckboxProps): QuickjsUiNode;
  Switch(props: SwitchProps): QuickjsUiNode;
  Slider(props: SliderProps): QuickjsUiNode;
  Radio(props: RadioProps): QuickjsUiNode;
  DropdownButton(props: DropdownButtonProps): QuickjsUiNode;
  Icon(props: IconProps): QuickjsUiNode;
  Divider(props?: DividerProps): QuickjsUiNode;
  VerticalDivider(props?: DividerProps): QuickjsUiNode;
  Placeholder(props?: PlaceholderProps): QuickjsUiNode;
  Tooltip(props: TooltipProps): QuickjsUiNode;
  Card(props: CardProps): QuickjsUiNode;
  ClipRRect(props: ClipRRectProps): QuickjsUiNode;
  DecoratedBox(props: DecoratedBoxProps): QuickjsUiNode;
  RichText(props: RichTextProps): QuickjsUiNode;
  Scaffold(props: ScaffoldProps): QuickjsUiNode;
  AppBar(props: AppBarProps): QuickjsUiNode;
  BottomNavigationBar(props: BottomNavigationBarProps): QuickjsUiNode;
  TabBar(props: TabBarProps): QuickjsUiNode;
  TabBarView(props: TabBarViewProps): QuickjsUiNode;
  Drawer(props: DrawerProps): QuickjsUiNode;
  CircularProgressIndicator(props?: ProgressIndicatorProps): QuickjsUiNode;
  LinearProgressIndicator(props?: ProgressIndicatorProps): QuickjsUiNode;
  SnackBar(props: SnackBarProps): QuickjsUiNode;
  AlertDialog(props: AlertDialogProps): QuickjsUiNode;
  BottomSheet(props: BottomSheetProps): QuickjsUiNode;
  AnimatedAlign(props: AnimatedAlignProps): QuickjsUiNode;
  AnimatedContainer(props: AnimatedContainerProps): QuickjsUiNode;
  AnimatedOpacity(props: AnimatedOpacityProps): QuickjsUiNode;
  AnimatedPadding(props: AnimatedPaddingProps): QuickjsUiNode;
  AnimatedSwitcher(props: AnimatedSwitcherProps): QuickjsUiNode;
  Hero(props: HeroProps): QuickjsUiNode;
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
