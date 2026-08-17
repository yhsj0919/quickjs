export type JsonValue =
  | null
  | boolean
  | number
  | string
  | JsonValue[]
  | { [key: string]: JsonValue };

export declare const jsUiRuntimeProtocol: 'quickjs_ui.runtime.v1';
export declare const jsUiSchemaVersion: 1;
export declare const jsUiHelperVersion: 1;

export type JsUiEvent = {
  action?: string;
  method?: string;
  payload?: JsonValue;
  source?: string;
  timestamp?: number;
};

export type JsUiMethodActions = Record<
  string,
  (payload?: JsonValue) => JsUiEvent
>;

export type JsUiNode = {
  type: string;
  key?: string;
  child?: JsUiNode;
  children?: JsUiNode[];
  [key: string]: JsonValue | JsUiNode | JsUiNode[] | undefined;
};

export type JsUiReservedPageKeys =
  | 'name'
  | 'props'
  | 'metadata'
  | 'schemaVersion'
  | 'minimumJsUiVersion'
  | 'minJsUiVersion'
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

export type JsUiPageMethod<State, Props> = (
  state: State,
  payload?: JsonValue,
  props?: Props,
  event?: JsUiEvent
) => Partial<State> | undefined | null | Promise<Partial<State> | undefined | null>;

export type JsUiLifecycleType =
  | 'mount'
  | 'show'
  | 'hide'
  | 'pause'
  | 'resume'
  | 'routeEnter'
  | 'routeLeave'
  | 'routeResult'
  | 'dispose';

export type JsUiLifecycleEvent = {
  type: JsUiLifecycleType;
  payload?: JsonValue;
};

export type JsUiLifecycleHook<State, Props> = (
  state: State,
  payload?: JsonValue,
  props?: Props,
  event?: JsUiLifecycleEvent
) =>
  | Partial<State>
  | undefined
  | null
  | Promise<Partial<State> | undefined | null>;

export type JsUiPageActions<Page> = {
  [Key in keyof Page as Key extends JsUiReservedPageKeys
    ? never
    : Page[Key] extends (...args: any[]) => any
      ? Key
      : never]: (payload?: JsonValue) => JsUiEvent;
};

export type JsUiPage<State = JsonValue, Props = Record<string, JsonValue>> = {
  name?: string;
  props?: Record<string, string>;
  metadata?: Record<string, JsonValue>;
  schemaVersion?: number;
  minimumJsUiVersion?: number;
  minJsUiVersion?: number;
  unknownProps?: 'ignore' | 'warn' | 'error';
  deprecatedProps?: Record<string, string>;
  createState?: (props: Props) => State;
  state?: (props: Props) => State;
  build?: (
    state: State,
    props: Props,
    actions: JsUiMethodActions
  ) => JsUiNode;
  onMount?: JsUiLifecycleHook<State, Props>;
  onShow?: JsUiLifecycleHook<State, Props>;
  onHide?: JsUiLifecycleHook<State, Props>;
  onPause?: JsUiLifecycleHook<State, Props>;
  onResume?: JsUiLifecycleHook<State, Props>;
  onRouteEnter?: JsUiLifecycleHook<State, Props>;
  onRouteLeave?: JsUiLifecycleHook<State, Props>;
  onRouteResult?: JsUiLifecycleHook<State, Props>;
  onDispose?: JsUiLifecycleHook<State, Props>;
  [key: string]: unknown;
};

export type JsUiPageProtocol<
  State = JsonValue,
  Props = Record<string, JsonValue>
> = {
  name?: string;
  metadata?: Record<string, JsonValue>;
  capabilities: () => {
    protocol: 'quickjs_ui.runtime.v1';
    schemaVersion: number;
    helperVersion: number;
    minimumJsUiVersion: number;
    unknownProps: 'ignore' | 'warn' | 'error';
    deprecatedProps: Record<string, string>;
    lifecycle: JsUiLifecycleType[];
  };
  mount: (props: Props) => Promise<{ version: number; state: State }>;
  handleEvent: (
    event: JsUiEvent
  ) =>
    | { changed: boolean; version: number }
    | Promise<{ changed: boolean; version: number }>;
  commit: () =>
    | { changed: false; version: number }
    | { changed: true; version: number; node: JsUiNode };
  setState: (patch: Partial<State>) => { changed: boolean; version: number };
  lifecycle: (
    event: JsUiLifecycleEvent
  ) => Promise<{ changed: boolean; version: number }>;
  snapshot: () => { version: number; state: State };
  dispose: () => boolean;
};

export declare function Page<
  State,
  Props = Record<string, JsonValue>,
  Definition extends JsUiPage<State, Props> = JsUiPage<State, Props>
>(
  page: Definition & {
    build?: (
      state: State,
      props: Props,
      actions: JsUiPageActions<Definition>
    ) => JsUiNode;
  }
): JsUiPageProtocol<State, Props>;

export declare function Component<
  Props extends Record<string, JsonValue> = Record<string, JsonValue>,
  Actions extends JsUiMethodActions = JsUiMethodActions,
>(
  render: (props: Props, actions: Actions) => JsUiNode,
): (props?: Props, actions?: Actions) => JsUiNode;

export declare function setState<State extends Record<string, JsonValue>>(
  state: State,
  patch: Partial<State>
): State;

export declare function eventField(
  event: JsUiEvent | undefined,
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

export type JsUiResourceKind =
  | 'asset'
  | 'file'
  | 'network'
  | 'http'
  | 'https'
  | 'data'
  | 'custom';

export type JsUiResourceReference =
  | string
  | {
      uri?: string;
      url?: string;
      src?: string;
      source?: string;
      path?: string;
      kind?: JsUiResourceKind;
      type?: JsUiResourceKind;
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

export type NodeEffectProps = {
  opacity?: CanvasNumber;
  transform?: {
    translate?: { x?: CanvasNumber; y?: CanvasNumber };
    scale?: CanvasNumber | { x?: CanvasNumber; y?: CanvasNumber };
    /** Rotation in radians, matching Flutter Transform.rotate. */
    rotate?: CanvasNumber;
    alignment?: Alignment;
  };
  translate?: { x?: CanvasNumber; y?: CanvasNumber };
  scale?: CanvasNumber | { x?: CanvasNumber; y?: CanvasNumber };
  rotate?: CanvasNumber;
  rotation?: CanvasNumber;
  transformAlignment?: Alignment;
  clipRadius?: CanvasNumber;
  clipBehavior?: 'none' | 'hardEdge' | 'antiAlias' | 'antiAliasWithSaveLayer';
  blur?: CanvasNumber | {
    sigma?: CanvasNumber;
    sigmaX?: CanvasNumber;
    sigmaY?: CanvasNumber;
  };
  backdropBlur?: CanvasNumber | {
    sigma?: CanvasNumber;
    sigmaX?: CanvasNumber;
    sigmaY?: CanvasNumber;
  };
  colorFilter?: {
    color: string | number;
    blendMode?: CanvasBlendMode;
  };
  paused?: boolean;
  playToken?: JsonValue;
  reverse?: boolean;
  /** Overrides the renderer frame interval for this animated node. */
  animationFrameIntervalMs?: number;
  onAnimationEnd?: JsUiEvent;
};

export type MouseCursor = 'defer' | 'default' | 'basic' | 'click' | 'pointer' | 'text' | 'move' | 'grab' | 'grabbing' | 'forbidden' | 'notAllowed' | 'wait' | 'progress' | 'resizeLeftRight' | 'resizeUpDown' | 'resizeUpLeftDownRight' | 'resizeUpRightDownLeft' | 'resizeColumn' | 'resizeRow';

export type AccessibilityProps = NodeEffectProps & {
  semanticLabel?: string;
  semanticsLabel?: string;
  semanticHint?: string;
  tooltip?: string;
  role?: AccessibilityRole;
  enabled?: boolean;
  hitTestBehavior?: 'deferToChild' | 'opaque' | 'translucent';
  ignorePointer?: boolean;
  absorbPointer?: boolean;
  autofocus?: boolean;
  canRequestFocus?: boolean;
  onFocus?: JsUiEvent;
  onBlur?: JsUiEvent;
  onKeyDown?: JsUiEvent;
  onKeyUp?: JsUiEvent;
  focusOrder?: number;
  onTap?: JsUiEvent;
  onLongPress?: JsUiEvent;
  onDoubleTap?: JsUiEvent;
  onDragStart?: JsUiEvent;
  onDragUpdate?: JsUiEvent;
  onDragEnd?: JsUiEvent;
  onSwipe?: JsUiEvent;
  onMouseEnter?: JsUiEvent;
  onMouseExit?: JsUiEvent;
  onMouseHover?: JsUiEvent;
  onMouseScroll?: JsUiEvent;
  onPointerDown?: JsUiEvent;
  onPointerMove?: JsUiEvent;
  onPointerUp?: JsUiEvent;
  onPointerCancel?: JsUiEvent;
  mouseCursor?: MouseCursor;
  cursor?: MouseCursor;
};

export type ScrollableProps = {
  initialScrollOffset?: number;
  scrollToOffset?: number;
  scrollToKey?: string;
  scrollToken?: number;
  scrollToToken?: number;
  scrollDurationMs?: number;
  scrollCurve?: Curve;
  onScroll?: JsUiEvent;
  physics?: 'platform' | 'always' | 'alwaysScrollable' | 'bouncing' | 'clamping' | 'never' | 'neverScrollable';
  scrollbar?: boolean;
};

export type TextProps = AccessibilityProps & {
  data?: string;
  text?: string;
  textAlign?: TextAlign;
  maxLines?: number;
  softWrap?: boolean;
  overflow?: 'clip' | 'fade' | 'ellipsis' | 'visible';
  style?: TextStyle | ThemeTextStyleToken;
};

export type AutoRefreshProps = AccessibilityProps & {
  intervalMs: number;
  paused?: boolean;
  child: JsUiNode;
};

export type DateTimeTextProps = Omit<TextProps, 'data' | 'text'> & {
  format?: string;
};

export type ControlVisualStyle = {
  backgroundColor?: ColorValue;
  foregroundColor?: ColorValue;
  overlayColor?: ColorValue;
  shadowColor?: ColorValue;
  surfaceTintColor?: ColorValue;
  borderColor?: ColorValue;
  borderWidth?: number;
  borderRadius?: BorderRadius;
  elevation?: number;
  padding?: EdgeInsets;
  textStyle?: TextStyle | ThemeTextStyleToken;
  fillColor?: ColorValue;
  thumbColor?: ColorValue;
  trackColor?: ColorValue;
  activeTrackColor?: ColorValue;
  inactiveTrackColor?: ColorValue;
  trackOutlineColor?: ColorValue;
  trackOutlineWidth?: number;
  valueIndicatorColor?: ColorValue;
  trackHeight?: number;
  thumbRadius?: number;
  overlayRadius?: number;
  scale?: number;
  opacity?: number;
};

export type ControlStateTransition = {
  durationMs?: number;
  curve?: Curve;
} | false;

export type ControlStateStyles = {
  normal?: ControlVisualStyle;
  hovered?: ControlVisualStyle;
  focused?: ControlVisualStyle;
  selected?: ControlVisualStyle;
  pressed?: ControlVisualStyle;
  disabled?: ControlVisualStyle;
};

export type ControlPartStyle = {
  normal?: ControlVisualStyle;
  hovered?: ControlVisualStyle;
  focused?: ControlVisualStyle;
  selected?: ControlVisualStyle;
  pressed?: ControlVisualStyle;
  disabled?: ControlVisualStyle;
};

export type ButtonProps = AccessibilityProps & {
  child?: JsUiNode;
  content?: JsUiNode;
  leading?: JsUiNode;
  trailing?: JsUiNode;
  label?: string;
  gap?: SpaceValue;
  stateStyles?: ControlStateStyles;
  stateTransition?: ControlStateTransition;
  onPressed?: JsUiEvent;
};

export type IconButtonProps = AccessibilityProps & {
  child?: JsUiNode;
  icon?: string;
  iconSize?: number;
  color?: ColorValue;
  onPressed?: JsUiEvent;
};

export type FlexProps = AccessibilityProps & {
  mainAxisAlignment?: MainAxisAlignment;
  crossAxisAlignment?: CrossAxisAlignment;
  gap?: SpaceValue;
  children?: JsUiNode[];
};

export type PositionedProps = AccessibilityProps & {
  child?: JsUiNode;
  left?: number;
  top?: number;
  right?: number;
  bottom?: number;
  width?: number;
  height?: number;
};

export type FlexChildProps = AccessibilityProps & {
  child?: JsUiNode;
  flex?: number;
  fit?: 'tight' | 'loose';
};

export type WrapProps = AccessibilityProps & {
  children?: JsUiNode[];
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
  child?: JsUiNode;
  aspectRatio: number;
};

export type ConstrainedBoxProps = AccessibilityProps & {
  child?: JsUiNode;
  minWidth?: number;
  maxWidth?: number;
  minHeight?: number;
  maxHeight?: number;
};

export type SafeAreaProps = AccessibilityProps & {
  child?: JsUiNode;
  left?: boolean;
  top?: boolean;
  right?: boolean;
  bottom?: boolean;
  minimum?: EdgeInsets;
};

export type ContainerProps = AccessibilityProps & {
  child?: JsUiNode;
  width?: number;
  height?: number;
  minWidth?: number;
  maxWidth?: number;
  minHeight?: number;
  maxHeight?: number;
  padding?: EdgeInsets;
  margin?: EdgeInsets;
  alignment?: Alignment;
  color?: ColorValue;
  backgroundColor?: ColorValue;
  decoration?: BoxDecorationValue;
  borderRadius?: BorderRadius;
  borderColor?: ColorValue;
  borderWidth?: number;
  elevation?: ElevationValue;
  shape?: 'rectangle' | 'circle';
  backgroundBlendMode?: CanvasBlendMode;
};

export type ImageProps = AccessibilityProps & {
  src?: JsUiResourceReference;
  source?: JsUiResourceReference;
  uri?: JsUiResourceReference;
  url?: JsUiResourceReference;
  path?: JsUiResourceReference;
  width?: number;
  height?: number;
  fit?: BoxFit;
  alignment?: Alignment;
  repeat?: 'noRepeat' | 'repeat' | 'repeatX' | 'repeatY';
  color?: ColorValue;
  blendMode?: 'srcIn' | 'srcOver' | 'multiply' | 'screen' | 'overlay' | 'darken' | 'lighten';
  cacheWidth?: number;
  cacheHeight?: number;
  filterQuality?: FilterQuality;
  gaplessPlayback?: boolean;
  excludeFromSemantics?: boolean;
};

export type SvgProps = AccessibilityProps & {
  src?: JsUiResourceReference;
  source?: JsUiResourceReference;
  uri?: JsUiResourceReference;
  url?: JsUiResourceReference;
  path?: JsUiResourceReference;
  data?: string;
  string?: string;
  svg?: string;
  width?: number;
  height?: number;
  fit?: BoxFit;
  color?: ColorValue;
  renderingStrategy?: 'raster' | 'picture';
  excludeFromSemantics?: boolean;
};

export type ParticleFlowParticle = {
  fromX: number;
  toX: number;
  fromY: number;
  toY: number;
  fromOpacity?: number;
  toOpacity?: number;
  fromScale?: number;
  toScale?: number;
  /** Rotation in radians. */
  fromRotation?: number;
  /** Rotation in radians. */
  toRotation?: number;
  durationMs: number;
  phaseMs?: number;
};

export type ParticleFlowProps = AccessibilityProps & {
  width: number;
  height: number;
  particles: ParticleFlowParticle[];
  children: JsUiNode[];
  frameIntervalMs?: number;
  paused?: boolean;
  playToken?: JsonValue;
};

export type GradientValue = {
  type?: 'linear' | 'radial';
  colors: ColorValue[];
  stops?: number[];
  begin?: Alignment;
  end?: Alignment;
  center?: Alignment;
  radius?: number;
  tileMode?: 'clamp' | 'repeat' | 'mirror' | 'decal';
};

export type BoxShadowValue = {
  color?: ColorValue;
  offset?: { x?: number; y?: number };
  offsetX?: number;
  offsetY?: number;
  blurRadius?: number;
  blur?: number;
  spreadRadius?: number;
  spread?: number;
};

export type BoxDecorationValue = {
  color?: ColorValue;
  gradient?: GradientValue;
  borderRadius?: BorderRadius;
  border?: {
    color?: ColorValue;
    width?: number;
    left?: BorderSideValue;
    top?: BorderSideValue;
    right?: BorderSideValue;
    bottom?: BorderSideValue;
  };
  shape?: 'rectangle' | 'circle';
  backgroundBlendMode?: CanvasBlendMode;
  boxShadow?: BoxShadowValue | BoxShadowValue[];
  boxShadows?: BoxShadowValue[];
  shadows?: BoxShadowValue[];
};

export type BorderSideValue = {
  color?: ColorValue;
  width?: number;
  style?: 'solid' | 'none';
};

export type CanvasPathSegment =
  | { op: 'moveTo' | 'lineTo'; x: CanvasNumber; y: CanvasNumber }
  | { op: 'quadraticTo'; cx: CanvasNumber; cy: CanvasNumber; x: CanvasNumber; y: CanvasNumber }
  | {
      op: 'cubicTo';
      cx1: CanvasNumber;
      cy1: CanvasNumber;
      cx2: CanvasNumber;
      cy2: CanvasNumber;
      x: CanvasNumber;
      y: CanvasNumber;
    }
  | {
      op: 'arc';
      cx: CanvasNumber;
      cy: CanvasNumber;
      radius: CanvasNumber;
      start: CanvasNumber;
      end: CanvasNumber;
      counterclockwise?: boolean;
    }
  | { op: 'close' };

export type CanvasPaint = {
  fill?: CanvasPaintStyle;
  stroke?: CanvasPaintStyle;
  strokeWidth?: number;
  strokeCap?: 'butt' | 'round' | 'square';
  strokeJoin?: 'miter' | 'round' | 'bevel';
  antiAlias?: boolean;
  lineDash?: CanvasNumber[];
  lineDashOffset?: CanvasNumber;
  globalAlpha?: CanvasNumber;
  blendMode?: 'srcOver' | 'clear' | 'multiply' | 'screen' | 'overlay' | 'darken' | 'lighten' | 'plus' | 'add' | 'difference';
};

export type NumericKeyframe = {
  offset: number;
  value: number;
};

export type CanvasAnimation = {
  from: number;
  to: number;
  durationMs: number;
  delayMs?: number;
  phaseMs?: number;
  repeat?: boolean;
  autoreverse?: boolean;
  timeSource?: 'elapsed' | 'epoch';
  curve?: 'linear' | 'easeIn' | 'easeOut' | 'easeInOut';
  keyframes?: ReadonlyArray<NumericKeyframe>;
};

export type CanvasNumber = number | CanvasAnimation;

export type CanvasGradientStop = {
  offset: number;
  color: string | number;
};

export type CanvasGradient = {
  type: 'linear' | 'radial';
  x0: CanvasNumber;
  y0: CanvasNumber;
  x1: CanvasNumber;
  y1: CanvasNumber;
  r0?: CanvasNumber;
  r1?: CanvasNumber;
  stops: CanvasGradientStop[];
  addColorStop(offset: number, color: string | number): void;
};

export type CanvasPaintStyle = string | number | CanvasGradient;

export type CanvasTextMetrics = {
  width: number;
  actualBoundingBoxAscent: number;
  actualBoundingBoxDescent: number;
  estimated: true;
};

export declare class Canvas2DContext {
  readonly commands: CanvasCommand[];
  fillStyle: CanvasPaintStyle;
  strokeStyle: CanvasPaintStyle;
  lineWidth: number;
  lineCap: 'butt' | 'round' | 'square';
  lineJoin: 'miter' | 'round' | 'bevel';
  lineDashOffset: CanvasNumber;
  globalAlpha: CanvasNumber;
  globalCompositeOperation: CanvasPaint['blendMode'];
  font: string;
  textAlign: 'left' | 'center' | 'right';
  textBaseline: 'top' | 'hanging' | 'middle' | 'alphabetic' | 'ideographic' | 'bottom';
  save(): void;
  restore(): void;
  translate(x: CanvasNumber, y: CanvasNumber): void;
  rotate(radians: CanvasNumber): void;
  scale(x: CanvasNumber, y?: CanvasNumber): void;
  clear(color?: string | number): void;
  clearRect(x: CanvasNumber, y: CanvasNumber, width: CanvasNumber, height: CanvasNumber): void;
  clipRect(x: CanvasNumber, y: CanvasNumber, width: CanvasNumber, height: CanvasNumber): void;
  clipProgress(progress: CanvasNumber): void;
  createLinearGradient(x0: CanvasNumber, y0: CanvasNumber, x1: CanvasNumber, y1: CanvasNumber): CanvasGradient;
  createRadialGradient(x0: CanvasNumber, y0: CanvasNumber, r0: CanvasNumber, x1: CanvasNumber, y1: CanvasNumber, r1: CanvasNumber): CanvasGradient;
  setLineDash(segments: number[]): void;
  getLineDash(): number[];
  fillRect(x: CanvasNumber, y: CanvasNumber, width: CanvasNumber, height: CanvasNumber, radius?: CanvasNumber): void;
  strokeRect(x: CanvasNumber, y: CanvasNumber, width: CanvasNumber, height: CanvasNumber, radius?: CanvasNumber): void;
  fillCircle(cx: CanvasNumber, cy: CanvasNumber, radius: CanvasNumber): void;
  strokeCircle(cx: CanvasNumber, cy: CanvasNumber, radius: CanvasNumber): void;
  drawLine(x1: CanvasNumber, y1: CanvasNumber, x2: CanvasNumber, y2: CanvasNumber): void;
  drawImage(image: CanvasImageSource, dx: CanvasNumber, dy: CanvasNumber): void;
  drawImage(
    image: CanvasImageSource,
    dx: CanvasNumber,
    dy: CanvasNumber,
    dWidth: CanvasNumber,
    dHeight: CanvasNumber
  ): void;
  drawSnapshotParticleGrid(options: {
    sourceSlot: string;
    targetSlot: string;
    x?: number;
    y?: number;
    width: number;
    height: number;
    columns?: number;
    rows?: number;
    bucketCount?: number;
    direction?: 'transition' | 'destroy' | 'create';
    staggerMs?: number;
    travelMs?: number;
    fadeMs?: number;
  }): void;
  drawImage(
    image: CanvasImageSource,
    sx: CanvasNumber,
    sy: CanvasNumber,
    sWidth: CanvasNumber,
    sHeight: CanvasNumber,
    dx: CanvasNumber,
    dy: CanvasNumber,
    dWidth: CanvasNumber,
    dHeight: CanvasNumber
  ): void;
  beginPath(): void;
  moveTo(x: CanvasNumber, y: CanvasNumber): void;
  lineTo(x: CanvasNumber, y: CanvasNumber): void;
  quadraticCurveTo(cx: CanvasNumber, cy: CanvasNumber, x: CanvasNumber, y: CanvasNumber): void;
  bezierCurveTo(cx1: CanvasNumber, cy1: CanvasNumber, cx2: CanvasNumber, cy2: CanvasNumber, x: CanvasNumber, y: CanvasNumber): void;
  arc(cx: CanvasNumber, cy: CanvasNumber, radius: CanvasNumber, start: CanvasNumber, end: CanvasNumber, counterclockwise?: boolean): void;
  closePath(): void;
  fill(): void;
  stroke(): void;
  fillText(text: unknown, x: CanvasNumber, y: CanvasNumber, maxWidth?: CanvasNumber): void;
  measureText(text: unknown): CanvasTextMetrics;
}

export declare function animate(
  from: number,
  to: number,
  options: Omit<CanvasAnimation, 'from' | 'to'>
): CanvasAnimation;

export declare function keyframes(
  frames: ReadonlyArray<NumericKeyframe>,
  options: Omit<CanvasAnimation, 'from' | 'to' | 'keyframes'>
): CanvasAnimation;

export declare function canvasCommands(
  draw: (context: Canvas2DContext) => void
): CanvasCommand[];

export type CanvasCommand =
  | { op: 'clear'; color?: string | number }
  | { op: 'save' | 'restore' }
  | { op: 'translate'; x: CanvasNumber; y: CanvasNumber }
  | { op: 'rotate'; radians: CanvasNumber }
  | { op: 'scale'; x: CanvasNumber; y?: CanvasNumber }
  | { op: 'clipRect'; x: CanvasNumber; y: CanvasNumber; width: CanvasNumber; height: CanvasNumber }
  | { op: 'clipProgress'; progress: CanvasNumber }
  | ({ op: 'line'; x1: CanvasNumber; y1: CanvasNumber; x2: CanvasNumber; y2: CanvasNumber } & CanvasPaint)
  | ({ op: 'rect'; x: CanvasNumber; y: CanvasNumber; width: CanvasNumber; height: CanvasNumber; radius?: CanvasNumber } & CanvasPaint)
  | ({ op: 'circle'; cx: CanvasNumber; cy: CanvasNumber; radius: CanvasNumber } & CanvasPaint)
  | ({ op: 'arc'; cx: CanvasNumber; cy: CanvasNumber; radius: CanvasNumber; start: CanvasNumber; sweep: CanvasNumber; useCenter?: boolean } & CanvasPaint)
  | ({ op: 'path'; segments: CanvasPathSegment[] } & CanvasPaint)
  | ({
      op: 'image';
      snapshotId: string;
      sx?: CanvasNumber;
      sy?: CanvasNumber;
      sWidth?: CanvasNumber;
      sHeight?: CanvasNumber;
      dx: CanvasNumber;
      dy: CanvasNumber;
      dWidth?: CanvasNumber;
      dHeight?: CanvasNumber;
      filterQuality?: 'none' | 'low' | 'medium' | 'high';
    } & Pick<CanvasPaint, 'globalAlpha' | 'blendMode'>)
  | {
      op: 'snapshotParticleGrid';
      sourceSlot: string;
      targetSlot: string;
      x?: number;
      y?: number;
      width: number;
      height: number;
      columns: number;
      rows: number;
      bucketCount: number;
      direction?: 'transition' | 'destroy' | 'create';
      staggerMs: number;
      travelMs: number;
      fadeMs: number;
    }
  | {
      op: 'text';
      text: string;
      x: CanvasNumber;
      y: CanvasNumber;
      color?: string | number;
      globalAlpha?: CanvasNumber;
      blendMode?: CanvasBlendMode;
      fontSize?: number;
      fontWeight?: 'normal' | 'bold';
      fontFamily?: string;
      align?: 'left' | 'center' | 'right';
      baseline?: 'top' | 'hanging' | 'middle' | 'alphabetic' | 'ideographic' | 'bottom';
      maxWidth?: number;
    };

export type CanvasProps = AccessibilityProps & {
  width?: number;
  height?: number;
  backgroundColor?: string | number;
  /** Registers or reuses a page-scoped retained command scene. */
  sceneKey?: string;
  /** Binds retained image slots to versioned snapshot handles. */
  resources?: Record<string, string>;
  commands?: CanvasCommand[];
  /** Recorded once into a ui.Picture and reused on every animation frame. */
  staticCommands?: CanvasCommand[];
  /** Familiar Canvas 2D-style callback compiled into commands once in JS. */
  draw?: (context: Canvas2DContext) => void;
  /** Canvas 2D-style callback recorded into the cached static picture. */
  staticDraw?: (context: Canvas2DContext) => void;
  /** Stops local time without discarding the retained scene. */
  paused?: boolean;
  /** Restarts local time whenever this value changes. */
  playToken?: JsonValue;
  /** Plays a finite retained scene from its end back to its beginning. */
  reverse?: boolean;
  /** Overrides the renderer frame interval for this animated canvas. */
  animationFrameIntervalMs?: number;
  willChange?: boolean;
  /** Requests sampled frame events. Minimum interval is 16ms. */
  onFrame?: JsUiEvent;
  /** Dispatched after the final frame of all finite local animations paints. */
  onAnimationEnd?: JsUiEvent;
  frameIntervalMs?: number;
  onTap?: JsUiEvent;
  onDoubleTap?: JsUiEvent;
  onLongPress?: JsUiEvent;
  onPointerDown?: JsUiEvent;
  onPointerMove?: JsUiEvent;
  onPointerUp?: JsUiEvent;
  onPointerCancel?: JsUiEvent;
};

export type SnapshotReference = {
  snapshotId: string;
  width: number;
  height: number;
  pixelWidth: number;
  pixelHeight: number;
  pixelRatio: number;
};

export type CanvasImageSource =
  | string
  | SnapshotReference
  | { snapshotId: string }
  | { id: string }
  | { slot: string };

export type SnapshotBoundaryProps = AccessibilityProps & {
  key: string;
  snapshotKey?: string;
  captureToken?: JsonValue;
  pixelRatio?: number;
  onCaptured?: JsUiEvent;
  onCaptureError?: JsUiEvent;
  child?: JsUiNode;
};

export type ListViewProps = AccessibilityProps & ScrollableProps & {
  children?: JsUiNode[];
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
  itemBuilder: (index: number) => JsUiNode;
  itemKey?: (index: number) => string;
  prefetchItemCount?: number;
  estimatedItemExtent?: number;
  hasMore?: boolean;
  loading?: boolean;
  loadMoreThreshold?: number;
  loadingText?: string;
  onLoadMore?: JsUiEvent;
  resetToken?: string | number;
};

export type GridViewProps = AccessibilityProps & ScrollableProps & {
  children?: JsUiNode[];
  scrollDirection?: Axis;
  shrinkWrap?: boolean;
  padding?: EdgeInsets;
  crossAxisCount?: number;
  childAspectRatio?: number;
  crossAxisSpacing?: SpaceValue;
  mainAxisSpacing?: SpaceValue;
};

export type PageViewProps = AccessibilityProps & ScrollableProps & {
  children?: JsUiNode[];
  scrollDirection?: Axis;
  pageSnapping?: boolean;
  onPageChanged?: JsUiEvent;
};

export type RefreshIndicatorProps = AccessibilityProps & {
  child: JsUiNode;
  onRefresh?: JsUiEvent;
};

export type SingleChildScrollViewProps = AccessibilityProps & ScrollableProps & {
  children?: JsUiNode[];
  padding?: EdgeInsets;
  gap?: SpaceValue;
};

export type TextFieldProps = AccessibilityProps & {
  leading?: JsUiNode;
  prefix?: JsUiNode;
  suffix?: JsUiNode;
  trailing?: JsUiNode;
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
  style?: TextStyle | ThemeTextStyleToken;
  stateStyles?: ControlStateStyles;
  stateTransition?: ControlStateTransition;
  onChanged?: JsUiEvent;
  onSubmitted?: JsUiEvent;
  onEditingComplete?: JsUiEvent;
  onFocus?: JsUiEvent;
  onBlur?: JsUiEvent;
  onSelectionChanged?: JsUiEvent;
};

export type StackProps = AccessibilityProps & {
  children?: JsUiNode[];
  alignment?: Alignment;
  fit?: StackFit;
  clipBehavior?: ClipBehavior;
};

export type PaddingProps = AccessibilityProps & {
  padding?: EdgeInsets;
  child?: JsUiNode;
};

export type MarginProps = AccessibilityProps & {
  margin?: EdgeInsets;
  padding?: EdgeInsets;
  value?: EdgeInsets;
  child?: JsUiNode;
};

export type CenterProps = AccessibilityProps & {
  child?: JsUiNode;
  widthFactor?: number;
  heightFactor?: number;
};

export type AlignProps = CenterProps & {
  alignment?: Alignment;
};

export type SizedBoxProps = AccessibilityProps & {
  child?: JsUiNode;
  width?: number;
  height?: number;
};

export type FormProps = {
  child?: JsUiNode;
  autovalidateMode?: string;
  [key: string]: JsonValue | JsUiNode | undefined;
};

export type CheckboxProps = {
  value?: boolean;
  tristate?: boolean;
  onChanged?: JsUiEvent;
  [key: string]: JsonValue | JsUiEvent | undefined;
};

export type SwitchProps = AccessibilityProps & {
  value?: boolean;
  stateStyles?: ControlStateStyles;
  stateTransition?: ControlStateTransition;
  thumbStyle?: ControlPartStyle;
  trackStyle?: ControlPartStyle;
  overlayStyle?: ControlPartStyle;
  onChanged?: JsUiEvent;
  [key: string]:
    | JsonValue
    | JsUiEvent
    | ControlStateStyles
    | ControlStateTransition
    | ControlPartStyle
    | undefined;
};

export type ResponsiveViewportProps = AccessibilityProps & {
  designWidth: number;
  designHeight: number;
  fit?: BoxFit;
  alignment?: Alignment;
  child?: JsUiNode;
};

export type RepaintBoundaryProps = AccessibilityProps & {
  child?: JsUiNode;
};

export type SliderProps = AccessibilityProps & {
  value?: number;
  min?: number;
  max?: number;
  divisions?: number;
  label?: string;
  stateStyles?: ControlStateStyles;
  stateTransition?: ControlStateTransition;
  thumbStyle?: ControlPartStyle;
  trackStyle?: ControlPartStyle;
  overlayStyle?: ControlPartStyle;
  onChanged?: JsUiEvent;
  onChangeStart?: JsUiEvent;
  onChangeEnd?: JsUiEvent;
  [key: string]:
    | JsonValue
    | JsUiEvent
    | ControlStateStyles
    | ControlStateTransition
    | ControlPartStyle
    | undefined;
};

export type RadioProps = {
  value?: JsonValue;
  groupValue?: JsonValue;
  onChanged?: JsUiEvent;
  [key: string]: JsonValue | JsUiEvent | undefined;
};

export type DropdownButtonProps = {
  value?: JsonValue;
  items?: JsonValue[];
  onChanged?: JsUiEvent;
  hint?: JsUiNode;
  [key: string]: JsonValue | JsUiEvent | JsUiNode | undefined;
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
  child?: JsUiNode;
  onTap?: JsUiEvent;
  onDoubleTap?: JsUiEvent;
  onLongPress?: JsUiEvent;
  onDragStart?: JsUiEvent;
  onDragUpdate?: JsUiEvent;
  onDragEnd?: JsUiEvent;
  onSwipe?: JsUiEvent;
};

export type TooltipProps = AccessibilityProps & {
  message: string;
  child?: JsUiNode;
  waitDurationMs?: number;
  showDurationMs?: number;
};

export type CardProps = AccessibilityProps & {
  child?: JsUiNode;
  color?: ColorValue;
  elevation?: ElevationValue;
  margin?: EdgeInsets;
  clipBehavior?: ClipBehavior;
};

export type DecoratedBoxProps = AccessibilityProps & {
  child?: JsUiNode;
  position?: 'background' | 'foreground';
  color?: ColorValue;
  backgroundColor?: ColorValue;
  decoration?: BoxDecorationValue;
  borderRadius?: BorderRadius;
  borderColor?: ColorValue;
  borderWidth?: number;
};

export type ClipRRectProps = AccessibilityProps & {
  child?: JsUiNode;
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
  body?: JsUiNode;
  child?: JsUiNode;
  appBar?: JsUiNode;
  drawer?: JsUiNode;
  bottomNavigationBar?: JsUiNode;
  floatingActionButton?: JsUiNode;
  backgroundColor?: ColorValue;
  tabLength?: number;
  initialTabIndex?: number;
};

export type AppBarProps = AccessibilityProps & {
  title?: JsUiNode;
  titleText?: string;
  leading?: JsUiNode;
  actions?: JsUiNode[];
  bottom?: JsUiNode;
  backgroundColor?: ColorValue;
  foregroundColor?: ColorValue;
  centerTitle?: boolean;
  elevation?: ElevationValue;
};

export type BottomNavigationBarItemProps = {
  label: string;
  icon?: JsUiNode;
  iconName?: string;
  activeIcon?: JsUiNode;
  tooltip?: string;
};

export type BottomNavigationBarProps = AccessibilityProps & {
  currentIndex?: number;
  typeMode?: 'fixed' | 'shifting';
  items: BottomNavigationBarItemProps[];
  onTap?: JsUiEvent;
};

export type TabValue =
  | string
  | { text?: string; label?: string; icon?: JsUiNode; child?: JsUiNode };

export type TabBarProps = AccessibilityProps & {
  tabs: TabValue[];
  isScrollable?: boolean;
  onTap?: JsUiEvent;
};

export type TabBarViewProps = AccessibilityProps & {
  children?: JsUiNode[];
};

export type DrawerProps = AccessibilityProps & {
  child?: JsUiNode;
};

export type ProgressIndicatorProps = AccessibilityProps & {
  value?: number;
  color?: ColorValue;
  backgroundColor?: ColorValue;
  strokeWidth?: number;
  minHeight?: number;
};

export type SnackBarProps = AccessibilityProps & {
  child?: JsUiNode;
  content?: string;
  text?: string;
  visible?: boolean;
  durationMs?: number;
  backgroundColor?: ColorValue;
};

export type OverlayProps = AccessibilityProps & {
  visible?: boolean;
  child?: JsUiNode;
  alignment?: Alignment;
  padding?: EdgeInsetsValue;
  barrierDismissible?: boolean;
  barrierColor?: ColorValue;
  transition?: "fade" | "scale" | "fadeScale" | "slideDown" | "slideUp" | "none";
  durationMs?: number;
  curve?: Curve;
  onDismissed?: JsUiEvent;
  onClosing?: JsUiEvent;
};

export type AnchoredOverlayProps = AccessibilityProps & {
  visible?: boolean;
  anchor: JsUiNode;
  overlay: JsUiNode;
  content?: JsUiNode;
  placement?: 'auto' | 'topStart' | 'top' | 'topCenter' | 'topEnd' | 'bottomStart' | 'bottom' | 'bottomCenter' | 'bottomEnd' | 'left' | 'centerLeft' | 'right' | 'centerRight' | 'center';
  offset?: { x?: number; y?: number };
  gap?: number;
  screenPadding?: EdgeInsetsValue;
  consumeOutsideTap?: boolean;
  dismissOnTapOutside?: boolean;
  useRootOverlay?: boolean;
  animated?: boolean;
  matchAnchorWidth?: boolean;
  onDismissed?: JsUiEvent;
};

export type AlertDialogProps = AccessibilityProps & {
  visible?: boolean;
  title?: JsUiNode;
  titleText?: string;
  content?: JsUiNode;
  contentText?: string;
  actions?: JsUiNode[];
  backgroundColor?: ColorValue;
};

export type BottomSheetProps = AccessibilityProps & {
  visible?: boolean;
  child?: JsUiNode;
  onClosing?: JsUiEvent;
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
  child?: JsUiNode;
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
  child: JsUiNode;
  transitionOnUserGestures?: boolean;
};

export type AnimatedSwitcherProps = AccessibilityProps & {
  child?: JsUiNode;
  durationMs?: number;
  animationDurationMs?: number;
  reverseDurationMs?: number;
  switchInCurve?: Curve;
  switchOutCurve?: Curve;
};

export declare function Text(
  data: string,
  props?: Omit<TextProps, 'data'>
): JsUiNode;
export declare function Text(props: TextProps): JsUiNode;
export declare function AutoRefresh(props: AutoRefreshProps): JsUiNode;
export declare function DateTimeText(props: DateTimeTextProps): JsUiNode;
export declare function ElevatedButton(props: ButtonProps): JsUiNode;
export declare function TextButton(props: ButtonProps): JsUiNode;
export declare function OutlinedButton(props: ButtonProps): JsUiNode;
export declare function IconButton(props: IconButtonProps): JsUiNode;
export declare function InkWell(props: AccessibilityProps & { child?: JsUiNode }): JsUiNode;
export declare function FloatingActionButton(props: IconButtonProps): JsUiNode;
export declare function Row(props: FlexProps): JsUiNode;
export declare function Column(props: FlexProps): JsUiNode;
export declare function Container(props: ContainerProps): JsUiNode;
export declare function Image(props: ImageProps): JsUiNode;
export declare function Svg(props: SvgProps): JsUiNode;
export declare function ParticleFlow(props: ParticleFlowProps): JsUiNode;
export declare function Canvas(props: CanvasProps): JsUiNode;
export declare function SnapshotBoundary(
  props: SnapshotBoundaryProps
): JsUiNode;
export declare function ListView(props: ListViewProps): JsUiNode;
export declare namespace ListView {
  function builder(props: ListViewBuilderProps): JsUiNode;
}
export declare function SingleChildScrollView(
  props: SingleChildScrollViewProps
): JsUiNode;
export declare function GridView(props: GridViewProps): JsUiNode;
export declare function PageView(props: PageViewProps): JsUiNode;
export declare function RefreshIndicator(
  props: RefreshIndicatorProps
): JsUiNode;
export declare function TextField(props: TextFieldProps): JsUiNode;
export declare function TextFormField(props: TextFieldProps): JsUiNode;
export declare function GestureDetector(props: GestureDetectorProps): JsUiNode;
export declare function Stack(props: StackProps): JsUiNode;
export declare function Positioned(props: PositionedProps): JsUiNode;
export declare function Padding(props: PaddingProps): JsUiNode;
export declare function Margin(props: MarginProps): JsUiNode;
export declare function Align(props: AlignProps): JsUiNode;
export declare function Center(props: CenterProps): JsUiNode;
export declare function SizedBox(props: SizedBoxProps): JsUiNode;
export declare function ResponsiveViewport(
  props: ResponsiveViewportProps
): JsUiNode;
export declare function RepaintBoundary(
  props: RepaintBoundaryProps
): JsUiNode;
export declare function Expanded(props: FlexChildProps): JsUiNode;
export declare function Flexible(props: FlexChildProps): JsUiNode;
export declare function Spacer(props?: { flex?: number }): JsUiNode;
export declare function Wrap(props: WrapProps): JsUiNode;
export declare function AspectRatio(props: AspectRatioProps): JsUiNode;
export declare function ConstrainedBox(
  props: ConstrainedBoxProps
): JsUiNode;
export declare function SafeArea(props: SafeAreaProps): JsUiNode;
export declare function Form(props: FormProps): JsUiNode;
export declare function Checkbox(props: CheckboxProps): JsUiNode;
export declare function Switch(props: SwitchProps): JsUiNode;
export declare function Slider(props: SliderProps): JsUiNode;
export declare function Radio(props: RadioProps): JsUiNode;
export declare function DropdownButton(
  props: DropdownButtonProps
): JsUiNode;
export declare function Icon(props: IconProps): JsUiNode;
export declare function Divider(props?: DividerProps): JsUiNode;
export declare function VerticalDivider(props?: DividerProps): JsUiNode;
export declare function Placeholder(props?: PlaceholderProps): JsUiNode;
export declare function Tooltip(props: TooltipProps): JsUiNode;
export declare function Card(props: CardProps): JsUiNode;
export declare function ClipRRect(props: ClipRRectProps): JsUiNode;
export declare function DecoratedBox(props: DecoratedBoxProps): JsUiNode;
export declare function RichText(props: RichTextProps): JsUiNode;
export declare function Scaffold(props: ScaffoldProps): JsUiNode;
export declare function AppBar(props: AppBarProps): JsUiNode;
export declare function BottomNavigationBar(
  props: BottomNavigationBarProps
): JsUiNode;
export declare function TabBar(props: TabBarProps): JsUiNode;
export declare function TabBarView(props: TabBarViewProps): JsUiNode;
export declare function Drawer(props: DrawerProps): JsUiNode;
export declare function CircularProgressIndicator(
  props?: ProgressIndicatorProps
): JsUiNode;
export declare function LinearProgressIndicator(
  props?: ProgressIndicatorProps
): JsUiNode;
export declare function SnackBar(props: SnackBarProps): JsUiNode;
export declare function Overlay(props: OverlayProps): JsUiNode;
export declare function AnchoredOverlay(props: AnchoredOverlayProps): JsUiNode;
export declare function AlertDialog(props: AlertDialogProps): JsUiNode;
export declare function BottomSheet(props: BottomSheetProps): JsUiNode;
export declare function AnimatedAlign(props: AnimatedAlignProps): JsUiNode;
export declare function AnimatedContainer(props: AnimatedContainerProps): JsUiNode;
export declare function AnimatedOpacity(props: AnimatedOpacityProps): JsUiNode;
export declare function AnimatedPadding(props: AnimatedPaddingProps): JsUiNode;
export declare function AnimatedSwitcher(
  props: AnimatedSwitcherProps
): JsUiNode;
export declare function Hero(props: HeroProps): JsUiNode;

export declare const ui: {
  Text(data: string, props?: Omit<TextProps, 'data'>): JsUiNode;
  Text(props: TextProps): JsUiNode;
  AutoRefresh(props: AutoRefreshProps): JsUiNode;
  DateTimeText(props: DateTimeTextProps): JsUiNode;
  ElevatedButton(props: ButtonProps): JsUiNode;
  TextButton(props: ButtonProps): JsUiNode;
  OutlinedButton(props: ButtonProps): JsUiNode;
  IconButton(props: IconButtonProps): JsUiNode;
  InkWell(props: AccessibilityProps & { child?: JsUiNode }): JsUiNode;
  FloatingActionButton(props: IconButtonProps): JsUiNode;
  Row(props: FlexProps): JsUiNode;
  Column(props: FlexProps): JsUiNode;
  Container(props: ContainerProps): JsUiNode;
  Image(props: ImageProps): JsUiNode;
  Svg(props: SvgProps): JsUiNode;
  ParticleFlow(props: ParticleFlowProps): JsUiNode;
  Canvas(props: CanvasProps): JsUiNode;
  SnapshotBoundary(props: SnapshotBoundaryProps): JsUiNode;
  animate: typeof animate;
  canvasCommands: typeof canvasCommands;
  Canvas2DContext: typeof Canvas2DContext;
  ListView(props: ListViewProps): JsUiNode;
  SingleChildScrollView(props: SingleChildScrollViewProps): JsUiNode;
  GridView(props: GridViewProps): JsUiNode;
  PageView(props: PageViewProps): JsUiNode;
  RefreshIndicator(props: RefreshIndicatorProps): JsUiNode;
  TextField(props: TextFieldProps): JsUiNode;
  TextFormField(props: TextFieldProps): JsUiNode;
  GestureDetector(props: GestureDetectorProps): JsUiNode;
  Stack(props: StackProps): JsUiNode;
  Positioned(props: PositionedProps): JsUiNode;
  Padding(props: PaddingProps): JsUiNode;
  Margin(props: MarginProps): JsUiNode;
  Align(props: AlignProps): JsUiNode;
  Center(props: CenterProps): JsUiNode;
  SizedBox(props: SizedBoxProps): JsUiNode;
  ResponsiveViewport(props: ResponsiveViewportProps): JsUiNode;
  RepaintBoundary(props: RepaintBoundaryProps): JsUiNode;
  Expanded(props: FlexChildProps): JsUiNode;
  Flexible(props: FlexChildProps): JsUiNode;
  Spacer(props?: { flex?: number }): JsUiNode;
  Wrap(props: WrapProps): JsUiNode;
  AspectRatio(props: AspectRatioProps): JsUiNode;
  ConstrainedBox(props: ConstrainedBoxProps): JsUiNode;
  SafeArea(props: SafeAreaProps): JsUiNode;
  Form(props: FormProps): JsUiNode;
  Checkbox(props: CheckboxProps): JsUiNode;
  Switch(props: SwitchProps): JsUiNode;
  Slider(props: SliderProps): JsUiNode;
  Radio(props: RadioProps): JsUiNode;
  DropdownButton(props: DropdownButtonProps): JsUiNode;
  Icon(props: IconProps): JsUiNode;
  Divider(props?: DividerProps): JsUiNode;
  VerticalDivider(props?: DividerProps): JsUiNode;
  Placeholder(props?: PlaceholderProps): JsUiNode;
  Tooltip(props: TooltipProps): JsUiNode;
  Card(props: CardProps): JsUiNode;
  ClipRRect(props: ClipRRectProps): JsUiNode;
  DecoratedBox(props: DecoratedBoxProps): JsUiNode;
  RichText(props: RichTextProps): JsUiNode;
  Scaffold(props: ScaffoldProps): JsUiNode;
  AppBar(props: AppBarProps): JsUiNode;
  BottomNavigationBar(props: BottomNavigationBarProps): JsUiNode;
  TabBar(props: TabBarProps): JsUiNode;
  TabBarView(props: TabBarViewProps): JsUiNode;
  Drawer(props: DrawerProps): JsUiNode;
  CircularProgressIndicator(props?: ProgressIndicatorProps): JsUiNode;
  LinearProgressIndicator(props?: ProgressIndicatorProps): JsUiNode;
  SnackBar(props: SnackBarProps): JsUiNode;
  Overlay(props: OverlayProps): JsUiNode;
  AnchoredOverlay(props: AnchoredOverlayProps): JsUiNode;
  AlertDialog(props: AlertDialogProps): JsUiNode;
  BottomSheet(props: BottomSheetProps): JsUiNode;
  AnimatedAlign(props: AnimatedAlignProps): JsUiNode;
  AnimatedContainer(props: AnimatedContainerProps): JsUiNode;
  AnimatedOpacity(props: AnimatedOpacityProps): JsUiNode;
  AnimatedPadding(props: AnimatedPaddingProps): JsUiNode;
  AnimatedSwitcher(props: AnimatedSwitcherProps): JsUiNode;
  Hero(props: HeroProps): JsUiNode;
};

export type JsUiHostApi = {
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
    content?: JsUiNode;
    actions?: JsonValue[];
    [key: string]: JsonValue | JsUiNode | undefined;
  }) => Promise<JsonValue>;
  snackbar?: (payload: {
    message: string;
    [key: string]: JsonValue | undefined;
  }) => Promise<JsonValue>;
  bottomSheet?: (payload: {
    title?: string;
    message?: string;
    content?: JsUiNode;
    [key: string]: JsonValue | JsUiNode | undefined;
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

export type JsUiNavigationTarget =
  | string
  | {
      route?: string;
      path?: string;
      params?: Record<string, JsonValue>;
      [key: string]: JsonValue | undefined;
    };

export type JsUiNavigationApi = {
  push?: (
    target: JsUiNavigationTarget,
    params?: Record<string, JsonValue>
  ) => Promise<JsonValue>;
  replace?: (
    target: JsUiNavigationTarget,
    params?: Record<string, JsonValue>
  ) => Promise<boolean>;
  pop?: (result?: JsonValue) => boolean;
};

declare global {
  var jsUiHost: JsUiHostApi | undefined;
  var jsUiNavigation: JsUiNavigationApi | undefined;
}
