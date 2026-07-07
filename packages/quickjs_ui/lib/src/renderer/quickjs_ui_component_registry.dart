import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../resource/quickjs_ui_resource.dart';
import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_overlay_layer.dart';
import 'quickjs_ui_render_context.dart';
import 'quickjs_ui_scrollable.dart';

typedef QuickjsUiComponentBuilder =
    Widget Function(QuickjsUiRenderContext context, QuickjsUiNode node);

typedef QuickjsUiComponentControllerFactory =
    QuickjsUiComponentController Function(QuickjsUiNode node);

typedef QuickjsUiLifecycleComponentBuilder<
  T extends QuickjsUiComponentController
> =
    Widget Function(
      QuickjsUiRenderContext context,
      QuickjsUiNode node,
      T controller,
    );

base class QuickjsUiComponentController {
  void mount(QuickjsUiNode node) {}

  void update(QuickjsUiNode previous, QuickjsUiNode next) {}

  void show() {}

  void hide() {}

  void pause() {}

  void resume() {}

  void dispose() {}
}

final class QuickjsUiComponentRegistry {
  QuickjsUiComponentRegistry([Map<String, QuickjsUiComponentBuilder>? builders])
    : _components = <String, _QuickjsUiComponentDefinition>{
        for (final entry in builders?.entries ?? const Iterable.empty())
          entry.key: _QuickjsUiComponentDefinition.builder(entry.value),
      };

  factory QuickjsUiComponentRegistry.defaults() {
    return QuickjsUiComponentRegistry(<String, QuickjsUiComponentBuilder>{
      'Text': _buildText,
      'ElevatedButton': _buildElevatedButton,
      'TextButton': _buildTextButton,
      'OutlinedButton': _buildOutlinedButton,
      'IconButton': _buildIconButton,
      'InkWell': _buildInkWell,
      'FloatingActionButton': _buildFloatingActionButton,
      'Row': _buildRow,
      'Column': _buildColumn,
      'Container': _buildContainer,
      'Image': _buildImage,
      'ListView': _buildListView,
      'SingleChildScrollView': _buildSingleChildScrollView,
      'GridView': _buildGridView,
      'PageView': _buildPageView,
      'RefreshIndicator': _buildRefreshIndicator,
      'TextField': _buildTextField,
      'Stack': _buildStack,
      'Positioned': _buildPositioned,
      'Padding': _buildPadding,
      'Margin': _buildMargin,
      'Align': _buildAlign,
      'Center': _buildCenter,
      'SizedBox': _buildSizedBox,
      'Expanded': _buildExpanded,
      'Flexible': _buildFlexible,
      'Spacer': _buildSpacer,
      'Wrap': _buildWrap,
      'AspectRatio': _buildAspectRatio,
      'ConstrainedBox': _buildConstrainedBox,
      'SafeArea': _buildSafeArea,
      'Form': _buildForm,
      'Checkbox': _buildCheckbox,
      'Switch': _buildSwitch,
      'Slider': _buildSlider,
      'Radio': _buildRadio,
      'DropdownButton': _buildDropdownButton,
      'Icon': _buildIcon,
      'Divider': _buildDivider,
      'Card': _buildCard,
      'ClipRRect': _buildClipRRect,
      'BackdropFilter': _buildBackdropFilter,
      'DecoratedBox': _buildDecoratedBox,
      'RichText': _buildRichText,
      'Scaffold': _buildScaffold,
      'AppBar': _buildAppBar,
      'BottomNavigationBar': _buildBottomNavigationBar,
      'TabBar': _buildTabBar,
      'TabBarView': _buildTabBarView,
      'Drawer': _buildDrawer,
      'CircularProgressIndicator': _buildCircularProgressIndicator,
      'LinearProgressIndicator': _buildLinearProgressIndicator,
      'SnackBar': _buildSnackBar,
      'AlertDialog': _buildAlertDialog,
      'BottomSheet': _buildBottomSheet,
      'AnimatedAlign': _buildAnimatedAlign,
      'AnimatedSwitcher': _buildAnimatedSwitcher,
    });
  }

  final Map<String, _QuickjsUiComponentDefinition> _components;

  Iterable<String> get types => _components.keys;

  bool contains(String type) {
    return _components.containsKey(type);
  }

  void register(String type, QuickjsUiComponentBuilder builder) {
    _components[type] = _QuickjsUiComponentDefinition.builder(builder);
  }

  void registerLifecycle<T extends QuickjsUiComponentController>(
    String type, {
    required T Function(QuickjsUiNode node) createController,
    required QuickjsUiLifecycleComponentBuilder<T> build,
  }) {
    _components[type] = _QuickjsUiComponentDefinition.lifecycle(
      createController: createController,
      build: build,
    );
  }

  void unregister(String type) {
    _components.remove(type);
  }

  bool hasLifecycle(String type) {
    return _components[type]?.hasLifecycle == true;
  }

  QuickjsUiComponentController createController(QuickjsUiNode node) {
    final component = _components[node.type];
    if (component == null) {
      throw FormatException('Unknown quickjs_ui node type: ${node.type}');
    }
    final create = component.createController;
    if (create == null) {
      throw FormatException(
        'quickjs_ui node type ${node.type} does not define a controller',
      );
    }
    return create(node);
  }

  Widget build(
    QuickjsUiRenderContext context,
    QuickjsUiNode node, {
    QuickjsUiComponentController? controller,
  }) {
    if (context.buildContext != null && isQuickjsUiOverlayNode(node.type)) {
      return const SizedBox.shrink();
    }
    final component = _components[node.type];
    if (component == null) {
      throw FormatException('Unknown quickjs_ui node type: ${node.type}');
    }
    return component.build(context, node, controller);
  }
}

final class _QuickjsUiComponentDefinition {
  _QuickjsUiComponentDefinition.builder(QuickjsUiComponentBuilder builder)
    : createController = null,
      _build = ((context, node, _) => builder(context, node));

  _QuickjsUiComponentDefinition._({
    required this.createController,
    required this._build,
  });

  static _QuickjsUiComponentDefinition
  lifecycle<T extends QuickjsUiComponentController>({
    required T Function(QuickjsUiNode node) createController,
    required QuickjsUiLifecycleComponentBuilder<T> build,
  }) {
    return _QuickjsUiComponentDefinition._(
      createController: createController,
      build: (context, node, controller) {
        if (controller is! T) {
          throw StateError(
            'quickjs_ui lifecycle controller type mismatch for ${node.type}',
          );
        }
        return build(context, node, controller);
      },
    );
  }

  final QuickjsUiComponentControllerFactory? createController;
  final Widget Function(
    QuickjsUiRenderContext context,
    QuickjsUiNode node,
    QuickjsUiComponentController? controller,
  )
  _build;

  bool get hasLifecycle => createController != null;

  Widget build(
    QuickjsUiRenderContext context,
    QuickjsUiNode node,
    QuickjsUiComponentController? controller,
  ) {
    if (hasLifecycle && controller == null) {
      throw StateError(
        'quickjs_ui lifecycle component ${node.type} has no controller',
      );
    }
    return _build(context, node, controller);
  }
}

Widget _buildText(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final data =
      QuickjsUiProps.string(node.props['data'] ?? node.props['text']) ?? '';
  return Text(
    data,
    textAlign: QuickjsUiProps.textAlign(node.props['textAlign']),
    style: context.textStyle(node.props['style']),
  );
}

Widget _buildElevatedButton(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final event = QuickjsUiProps.event(node.props['onPressed']);
  return ElevatedButton(
    onPressed: event == null ? null : () => context.dispatch(event),
    child: _buttonChild(context, node),
  );
}

Widget _buildTextButton(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final event = QuickjsUiProps.event(node.props['onPressed']);
  return TextButton(
    onPressed: event == null ? null : () => context.dispatch(event),
    child: _buttonChild(context, node),
  );
}

Widget _buildOutlinedButton(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final event = QuickjsUiProps.event(node.props['onPressed']);
  return OutlinedButton(
    onPressed: event == null ? null : () => context.dispatch(event),
    child: _buttonChild(context, node),
  );
}

Widget _buildIconButton(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final event = QuickjsUiProps.event(node.props['onPressed']);
  final tooltip = QuickjsUiProps.string(node.props['tooltip']);
  return IconButton(
    tooltip: tooltip,
    iconSize: QuickjsUiProps.doubleValue(node.props['iconSize']),
    color: context.color(node.props['color']),
    onPressed: event == null ? null : () => context.dispatch(event),
    icon:
        context.child(node) ??
        Icon(_iconData(QuickjsUiProps.string(node.props['icon']) ?? 'help')),
  );
}

Widget _buildInkWell(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return _withGestures(context, node, context.child(node) ?? const SizedBox());
}

Widget _buildFloatingActionButton(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final event = QuickjsUiProps.event(node.props['onPressed']);
  return FloatingActionButton(
    onPressed: event == null ? null : () => context.dispatch(event),
    tooltip: QuickjsUiProps.string(node.props['tooltip']),
    backgroundColor: context.color(node.props['backgroundColor']),
    foregroundColor: context.color(node.props['foregroundColor']),
    child:
        context.child(node) ??
        Icon(_iconData(QuickjsUiProps.string(node.props['icon']) ?? 'add')),
  );
}

Widget _buttonChild(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return context.child(node) ??
      Text(QuickjsUiProps.string(node.props['label']) ?? '');
}

Widget _buildRow(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Row(
    mainAxisAlignment: QuickjsUiProps.mainAxisAlignment(
      node.props['mainAxisAlignment'],
    ),
    crossAxisAlignment: QuickjsUiProps.crossAxisAlignment(
      node.props['crossAxisAlignment'],
    ),
    spacing: _gap(context, node),
    children: context.children(node),
  );
}

Widget _buildColumn(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Column(
    mainAxisAlignment: QuickjsUiProps.mainAxisAlignment(
      node.props['mainAxisAlignment'],
    ),
    crossAxisAlignment: QuickjsUiProps.crossAxisAlignment(
      node.props['crossAxisAlignment'],
    ),
    spacing: _gap(context, node),
    children: context.children(node),
  );
}

Widget _buildContainer(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final decoration = context.boxDecoration(node.props);
  final opacity = QuickjsUiProps.opacity(node.props['opacity']);
  final animationDuration = _animationDuration(node);
  final curve = QuickjsUiProps.curve(node.props['animationCurve']);
  final width = QuickjsUiProps.doubleValue(node.props['width']);
  final height = QuickjsUiProps.doubleValue(node.props['height']);
  final padding = context.edgeInsets(node.props['padding']);
  final margin = context.edgeInsets(node.props['margin']);
  final alignment = QuickjsUiProps.alignment(node.props['alignment']);
  final elevation = context.elevation(node.props['elevation']);
  final color = decoration == null
      ? context.color(node.props['color'] ?? node.props['backgroundColor'])
      : null;
  final nodeChild = context.child(node);
  Widget child = animationDuration == null
      ? Container(
          width: width,
          height: height,
          padding: padding,
          margin: margin,
          alignment: alignment,
          decoration: decoration,
          color: color,
          child: nodeChild,
        )
      : AnimatedContainer(
          duration: animationDuration,
          curve: curve,
          width: width,
          height: height,
          padding: padding,
          margin: margin,
          alignment: alignment,
          decoration: decoration,
          color: color,
          child: nodeChild,
        );
  if (opacity != 1) {
    child = animationDuration == null
        ? Opacity(opacity: opacity, child: child)
        : AnimatedOpacity(
            opacity: opacity,
            duration: animationDuration,
            curve: curve,
            child: child,
          );
  }
  if (elevation != null && elevation > 0) {
    child = Material(
      elevation: elevation,
      color: Colors.transparent,
      child: child,
    );
  }
  return _withGestures(context, node, child);
}

Widget _buildImage(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final resource = context.resource(
    node.props['src'] ?? node.props['source'],
    name: 'Image src',
  );
  final width = QuickjsUiProps.doubleValue(node.props['width']);
  final height = QuickjsUiProps.doubleValue(node.props['height']);
  final fit = QuickjsUiProps.boxFit(node.props['fit']);
  final image = switch (resource.kind) {
    QuickjsUiResourceKind.asset => Image.asset(
      resource.location,
      width: width,
      height: height,
      fit: fit,
    ),
    QuickjsUiResourceKind.file => Image.file(
      File(_filePath(resource.location)),
      width: width,
      height: height,
      fit: fit,
    ),
    QuickjsUiResourceKind.network => Image.network(
      resource.location,
      headers: resource.headers.isEmpty ? null : resource.headers,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) {
        return SizedBox(width: width, height: height);
      },
    ),
    QuickjsUiResourceKind.data => Image.memory(
      _dataUriBytes(resource.location),
      width: width,
      height: height,
      fit: fit,
    ),
    QuickjsUiResourceKind.custom => throw FormatException(
      'quickjs_ui Image does not support custom resource: ${resource.location}',
    ),
  };
  return _withGestures(context, node, image);
}

String _filePath(String location) {
  final uri = Uri.tryParse(location);
  if (uri != null && uri.scheme == 'file') {
    return uri.toFilePath();
  }
  return location;
}

Uint8List _dataUriBytes(String location) {
  final comma = location.indexOf(',');
  if (!location.startsWith('data:') || comma == -1) {
    throw const FormatException('quickjs_ui Image data resource is invalid');
  }
  final metadata = location.substring(5, comma);
  final data = location.substring(comma + 1);
  if (metadata.split(';').contains('base64')) {
    return base64Decode(data);
  }
  return Uint8List.fromList(utf8.encode(Uri.decodeComponent(data)));
}

Widget _buildListView(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final axis = QuickjsUiProps.axis(node.props['scrollDirection']);
  final rawChildren = context.children(node);
  final rawKeys = quickjsUiChildKeys(node);
  final gap = _gap(context, node);
  final children = <Widget>[];
  final childKeys = <String?>[];
  for (var index = 0; index < rawChildren.length; index++) {
    if (index > 0 && gap > 0) {
      children.add(
        axis == Axis.horizontal ? SizedBox(width: gap) : SizedBox(height: gap),
      );
      childKeys.add(null);
    }
    children.add(rawChildren[index]);
    childKeys.add(rawKeys[index]);
  }
  final animateItems =
      QuickjsUiProps.boolValue(node.props['animateItems']) ?? false;
  if (animateItems && childKeys.any((key) => key == null || key.isEmpty)) {
    throw const FormatException(
      'quickjs_ui ListView animateItems requires stable string keys on children',
    );
  }
  final listView = QuickjsUiScrollableList(
    axis: axis,
    shrinkWrap:
        QuickjsUiProps.boolValue(node.props['shrinkWrap']) ??
        (node.props['shrinkWrap'] == null),
    padding: context.edgeInsets(node.props['padding']),
    childKeys: childKeys,
    scroll: QuickjsUiScrollCommand.fromNode(node),
    animateItems: animateItems,
    itemDuration: quickjsUiItemTransitionDuration(node),
    itemCurve: quickjsUiItemTransitionCurve(node),
    children: children,
  );
  final withGestures = _withGestures(context, node, listView);
  return quickjsUiWrapScrollNotifications(
    context: context,
    node: node,
    child: withGestures,
  );
}

Widget _buildSingleChildScrollView(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final scrollView = QuickjsUiScrollableColumn(
    padding: context.edgeInsets(node.props['padding']),
    scroll: QuickjsUiScrollCommand.fromNode(node),
    children: _childrenWithGap(context, node, Axis.vertical),
  );
  final withGestures = _withGestures(context, node, scrollView);
  return quickjsUiWrapScrollNotifications(
    context: context,
    node: node,
    child: withGestures,
  );
}

Widget _buildGridView(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final axis = QuickjsUiProps.axis(node.props['scrollDirection']);
  final gridView = GridView.count(
    scrollDirection: axis,
    crossAxisCount: QuickjsUiProps.intValue(node.props['crossAxisCount']) ?? 2,
    childAspectRatio:
        QuickjsUiProps.doubleValue(node.props['childAspectRatio']) ?? 1,
    crossAxisSpacing:
        context.spacing(
          node.props['crossAxisSpacing'],
          name: 'GridView crossAxisSpacing',
        ) ??
        0,
    mainAxisSpacing:
        context.spacing(
          node.props['mainAxisSpacing'],
          name: 'GridView mainAxisSpacing',
        ) ??
        0,
    padding: context.edgeInsets(node.props['padding']),
    shrinkWrap: QuickjsUiProps.boolValue(node.props['shrinkWrap']) ?? false,
    children: context.children(node),
  );
  final withGestures = _withGestures(context, node, gridView);
  return quickjsUiWrapScrollNotifications(
    context: context,
    node: node,
    child: withGestures,
  );
}

Widget _buildPageView(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onPageChanged = QuickjsUiProps.event(node.props['onPageChanged']);
  final pageView = PageView(
    scrollDirection: QuickjsUiProps.axis(node.props['scrollDirection']),
    pageSnapping: QuickjsUiProps.boolValue(node.props['pageSnapping']) ?? true,
    onPageChanged: onPageChanged == null
        ? null
        : (index) => context.dispatchEvent(
            onPageChanged,
            defaultCoalesceKey: _eventKey(node, 'onPageChanged'),
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'index': index},
          ),
    children: context.children(node),
  );
  final withGestures = _withGestures(context, node, pageView);
  return quickjsUiWrapScrollNotifications(
    context: context,
    node: node,
    child: withGestures,
  );
}

Widget _buildRefreshIndicator(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final onRefresh = QuickjsUiProps.event(node.props['onRefresh']);
  return RefreshIndicator(
    onRefresh: () async {
      if (onRefresh != null) {
        context.dispatchEvent(onRefresh);
      }
    },
    child: context.child(node) ?? ListView(children: const <Widget>[]),
  );
}

List<Widget> _childrenWithGap(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
  Axis axis,
) {
  final children = context.children(node);
  final gap = _gap(context, node);
  if (children.length < 2 || gap <= 0) {
    return children;
  }
  return <Widget>[
    for (var index = 0; index < children.length; index++) ...<Widget>[
      if (index > 0)
        axis == Axis.horizontal ? SizedBox(width: gap) : SizedBox(height: gap),
      children[index],
    ],
  ];
}

double _gap(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return context.spacing(node.props['gap'], name: 'gap') ?? 0;
}

Duration? _animationDuration(QuickjsUiNode node) {
  return QuickjsUiProps.duration(
    node.props['animationDurationMs'] ?? node.props['durationMs'],
    name: 'animation duration',
  );
}

Widget _buildTextField(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onChanged = QuickjsUiProps.event(node.props['onChanged']);
  final onSubmitted = QuickjsUiProps.event(node.props['onSubmitted']);
  final onFocus = QuickjsUiProps.event(node.props['onFocus']);
  final onBlur = QuickjsUiProps.event(node.props['onBlur']);
  final onEditingComplete = QuickjsUiProps.event(
    node.props['onEditingComplete'],
  );
  final onSelectionChanged = QuickjsUiProps.event(
    node.props['onSelectionChanged'],
  );
  final focusId = QuickjsUiProps.string(node.props['focusId']);
  return _QuickjsUiTextField(
    value:
        QuickjsUiProps.string(
          node.props['value'] ?? node.props['initialValue'],
          name: 'TextField value',
        ) ??
        '',
    focusId: focusId,
    enabled: QuickjsUiProps.boolValue(node.props['enabled']) ?? true,
    autofocus:
        QuickjsUiProps.boolValue(
          node.props['autofocus'] ?? node.props['focusOnMount'],
        ) ??
        false,
    requestFocus: QuickjsUiProps.boolValue(node.props['requestFocus']) ?? false,
    clearFocus: QuickjsUiProps.boolValue(node.props['clearFocus']) ?? false,
    obscureText: QuickjsUiProps.boolValue(node.props['obscureText']) ?? false,
    maxLines: QuickjsUiProps.intValue(node.props['maxLines']),
    keyboardType: QuickjsUiProps.textInputType(node.props['keyboardType']),
    textInputAction: QuickjsUiProps.textInputAction(
      node.props['textInputAction'],
    ),
    submitFocusAction: _submitFocusAction(
      node.props['submitFocusAction'],
      node.props['textInputAction'],
    ),
    decoration: InputDecoration(
      labelText: QuickjsUiProps.string(node.props['labelText']),
      hintText: QuickjsUiProps.string(node.props['hintText']),
    ),
    onChanged: onChanged == null
        ? null
        : (value) => context.dispatchEvent(
            onChanged,
            defaultCoalesceKey: _eventKey(node, 'onChanged'),
            kind: QuickjsUiEventKind.sample,
            payload: value,
          ),
    onSubmitted: onSubmitted == null
        ? null
        : (value) =>
              context.dispatch(<String, Object?>{...onSubmitted, ...value}),
    onEditingComplete: onEditingComplete == null
        ? null
        : (value) => context.dispatch(<String, Object?>{
            ...onEditingComplete,
            ...value,
          }),
    onFocus: onFocus == null
        ? null
        : (value) => context.dispatch(<String, Object?>{...onFocus, ...value}),
    onBlur: onBlur == null
        ? null
        : (value) => context.dispatch(<String, Object?>{...onBlur, ...value}),
    onSelectionChanged: onSelectionChanged == null
        ? null
        : (value) => context.dispatchEvent(
            onSelectionChanged,
            defaultCoalesceKey: _eventKey(node, 'onSelectionChanged'),
            kind: QuickjsUiEventKind.sample,
            payload: value,
          ),
  );
}

_QuickjsUiSubmitFocusAction _submitFocusAction(
  Object? value,
  Object? textInputAction,
) {
  return switch (value) {
    null => switch (textInputAction) {
      'next' => _QuickjsUiSubmitFocusAction.next,
      'previous' => _QuickjsUiSubmitFocusAction.previous,
      _ => _QuickjsUiSubmitFocusAction.none,
    },
    'none' => _QuickjsUiSubmitFocusAction.none,
    'next' => _QuickjsUiSubmitFocusAction.next,
    'previous' => _QuickjsUiSubmitFocusAction.previous,
    'unfocus' => _QuickjsUiSubmitFocusAction.unfocus,
    _ => throw const FormatException('Unknown quickjs_ui submitFocusAction'),
  };
}

Widget _buildStack(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Stack(
    alignment:
        QuickjsUiProps.alignment(node.props['alignment']) ??
        AlignmentDirectional.topStart,
    fit: QuickjsUiProps.stackFit(node.props['fit']),
    children: context.children(node),
  );
}

Widget _buildPositioned(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Positioned(
    left: QuickjsUiProps.doubleValue(node.props['left']),
    top: QuickjsUiProps.doubleValue(node.props['top']),
    right: QuickjsUiProps.doubleValue(node.props['right']),
    bottom: QuickjsUiProps.doubleValue(node.props['bottom']),
    width: QuickjsUiProps.doubleValue(node.props['width']),
    height: QuickjsUiProps.doubleValue(node.props['height']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildPadding(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final padding = context.edgeInsets(node.props['padding']) ?? EdgeInsets.zero;
  final animationDuration = _animationDuration(node);
  final child = context.child(node) ?? const SizedBox.shrink();
  return _withGestures(
    context,
    node,
    animationDuration == null
        ? Padding(padding: padding, child: child)
        : AnimatedPadding(
            padding: padding,
            duration: animationDuration,
            curve: QuickjsUiProps.curve(node.props['animationCurve']),
            child: child,
          ),
  );
}

Widget _buildMargin(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final margin =
      context.edgeInsets(
        node.props['margin'] ?? node.props['padding'] ?? node.props['value'],
      ) ??
      EdgeInsets.zero;
  return _withGestures(
    context,
    node,
    Padding(padding: margin, child: context.child(node) ?? const SizedBox()),
  );
}

Widget _buildAlign(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return _withGestures(
    context,
    node,
    Align(
      alignment:
          QuickjsUiProps.alignment(node.props['alignment']) ?? Alignment.center,
      widthFactor: QuickjsUiProps.doubleValue(node.props['widthFactor']),
      heightFactor: QuickjsUiProps.doubleValue(node.props['heightFactor']),
      child: context.child(node),
    ),
  );
}

Widget _buildCenter(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return _withGestures(
    context,
    node,
    Center(
      widthFactor: QuickjsUiProps.doubleValue(node.props['widthFactor']),
      heightFactor: QuickjsUiProps.doubleValue(node.props['heightFactor']),
      child: context.child(node),
    ),
  );
}

Widget _buildSizedBox(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return _withGestures(
    context,
    node,
    SizedBox(
      width: QuickjsUiProps.doubleValue(node.props['width']),
      height: QuickjsUiProps.doubleValue(node.props['height']),
      child: context.child(node),
    ),
  );
}

Widget _buildExpanded(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Expanded(
    flex: QuickjsUiProps.intValue(node.props['flex']) ?? 1,
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildFlexible(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Flexible(
    flex: QuickjsUiProps.intValue(node.props['flex']) ?? 1,
    fit: _flexFit(node.props['fit']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildSpacer(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Spacer(flex: QuickjsUiProps.intValue(node.props['flex']) ?? 1);
}

Widget _buildWrap(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return _withGestures(
    context,
    node,
    Wrap(
      direction: QuickjsUiProps.axis(node.props['direction']),
      alignment: _wrapAlignment(node.props['alignment']),
      runAlignment: _wrapAlignment(node.props['runAlignment']),
      crossAxisAlignment: _wrapCrossAlignment(node.props['crossAxisAlignment']),
      spacing:
          context.spacing(node.props['spacing'], name: 'Wrap spacing') ?? 0,
      runSpacing:
          context.spacing(node.props['runSpacing'], name: 'Wrap runSpacing') ??
          0,
      children: context.children(node),
    ),
  );
}

Widget _buildAspectRatio(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final ratio = QuickjsUiProps.doubleValue(node.props['aspectRatio']) ?? 1;
  return _withGestures(
    context,
    node,
    AspectRatio(
      aspectRatio: ratio,
      child: context.child(node) ?? const SizedBox.shrink(),
    ),
  );
}

Widget _buildConstrainedBox(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return _withGestures(
    context,
    node,
    ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: QuickjsUiProps.doubleValue(node.props['minWidth']) ?? 0,
        maxWidth:
            QuickjsUiProps.doubleValue(node.props['maxWidth']) ??
            double.infinity,
        minHeight: QuickjsUiProps.doubleValue(node.props['minHeight']) ?? 0,
        maxHeight:
            QuickjsUiProps.doubleValue(node.props['maxHeight']) ??
            double.infinity,
      ),
      child: context.child(node) ?? const SizedBox.shrink(),
    ),
  );
}

Widget _buildSafeArea(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return SafeArea(
    left: QuickjsUiProps.boolValue(node.props['left']) ?? true,
    top: QuickjsUiProps.boolValue(node.props['top']) ?? true,
    right: QuickjsUiProps.boolValue(node.props['right']) ?? true,
    bottom: QuickjsUiProps.boolValue(node.props['bottom']) ?? true,
    minimum: _edgeInsets(context.edgeInsets(node.props['minimum'])),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildForm(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Form(child: context.child(node) ?? const SizedBox.shrink());
}

Widget _buildCheckbox(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onChanged = QuickjsUiProps.event(node.props['onChanged']);
  return Checkbox(
    value: QuickjsUiProps.boolValue(node.props['value']) ?? false,
    tristate: QuickjsUiProps.boolValue(node.props['tristate']) ?? false,
    onChanged: onChanged == null
        ? null
        : (value) => context.dispatchEvent(
            onChanged,
            defaultCoalesceKey: _eventKey(node, 'onChanged'),
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'value': value},
          ),
  );
}

Widget _buildSwitch(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onChanged = QuickjsUiProps.event(node.props['onChanged']);
  return Switch(
    value: QuickjsUiProps.boolValue(node.props['value']) ?? false,
    onChanged: onChanged == null
        ? null
        : (value) => context.dispatchEvent(
            onChanged,
            defaultCoalesceKey: _eventKey(node, 'onChanged'),
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'value': value},
          ),
  );
}

Widget _buildSlider(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onChanged = QuickjsUiProps.event(node.props['onChanged']);
  final onChangeEnd = QuickjsUiProps.event(node.props['onChangeEnd']);
  final min = QuickjsUiProps.doubleValue(node.props['min']) ?? 0;
  final max = QuickjsUiProps.doubleValue(node.props['max']) ?? 1;
  final value = (QuickjsUiProps.doubleValue(node.props['value']) ?? min).clamp(
    min,
    max,
  );
  return Slider(
    min: min,
    max: max,
    value: value,
    divisions: QuickjsUiProps.intValue(node.props['divisions']),
    label: QuickjsUiProps.string(node.props['label']),
    onChanged: onChanged == null
        ? null
        : (next) => context.dispatchEvent(
            onChanged,
            defaultCoalesceKey: _eventKey(node, 'onChanged'),
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'value': next},
          ),
    onChangeEnd: onChangeEnd == null
        ? null
        : (next) => context.dispatchEvent(
            onChangeEnd,
            defaultCoalesceKey: _eventKey(node, 'onChangeEnd'),
            payload: <String, Object?>{'value': next},
          ),
  );
}

Widget _buildRadio(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onChanged = QuickjsUiProps.event(node.props['onChanged']);
  final value = node.props['value'];
  // Keep compatibility with the package's older Flutter lower bound.
  // ignore: deprecated_member_use
  return Radio<Object?>(
    value: value,
    // ignore: deprecated_member_use
    groupValue: node.props['groupValue'],
    // ignore: deprecated_member_use
    onChanged: onChanged == null
        ? null
        : (value) => context.dispatchEvent(
            onChanged,
            defaultCoalesceKey: _eventKey(node, 'onChanged'),
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'value': value},
          ),
  );
}

Widget _buildDropdownButton(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final onChanged = QuickjsUiProps.event(node.props['onChanged']);
  final items = _dropdownItems(node.props['items']);
  final value = node.props['value'];
  final hint = QuickjsUiProps.string(node.props['hint']);
  return DropdownButton<Object?>(
    value: items.any((item) => item.value == value) ? value : null,
    isExpanded: QuickjsUiProps.boolValue(node.props['isExpanded']) ?? false,
    hint: hint == null ? null : Text(hint),
    items: items,
    onChanged: onChanged == null
        ? null
        : (value) => context.dispatchEvent(
            onChanged,
            defaultCoalesceKey: _eventKey(node, 'onChanged'),
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'value': value},
          ),
  );
}

List<DropdownMenuItem<Object?>> _dropdownItems(Object? value) {
  if (value == null) {
    return const <DropdownMenuItem<Object?>>[];
  }
  if (value is! List) {
    throw const FormatException(
      'quickjs_ui DropdownButton items must be a list',
    );
  }
  return <DropdownMenuItem<Object?>>[
    for (final item in value) _dropdownItem(item),
  ];
}

DropdownMenuItem<Object?> _dropdownItem(Object? value) {
  if (value is Map) {
    final props = value.map(
      (key, value) => MapEntry<String, Object?>('$key', value),
    );
    final itemValue = props['value'];
    return DropdownMenuItem<Object?>(
      value: itemValue,
      child: Text(QuickjsUiProps.string(props['label']) ?? '$itemValue'),
    );
  }
  return DropdownMenuItem<Object?>(value: value, child: Text('$value'));
}

Widget _buildIcon(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Icon(
    _iconData(QuickjsUiProps.string(node.props['icon'] ?? node.props['name'])),
    size: QuickjsUiProps.doubleValue(node.props['size']),
    color: context.color(node.props['color']),
    semanticLabel: QuickjsUiProps.string(node.props['semanticLabel']),
  );
}

Widget _buildDivider(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Divider(
    height: QuickjsUiProps.doubleValue(node.props['height']),
    thickness: QuickjsUiProps.doubleValue(node.props['thickness']),
    indent: QuickjsUiProps.doubleValue(node.props['indent']),
    endIndent: QuickjsUiProps.doubleValue(node.props['endIndent']),
    color: context.color(node.props['color']),
  );
}

Widget _buildCard(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Card(
    color: context.color(node.props['color']),
    elevation: context.elevation(node.props['elevation']),
    margin: context.edgeInsets(node.props['margin']),
    clipBehavior: _clipBehavior(node.props['clipBehavior']),
    child: context.child(node),
  );
}

Widget _buildClipRRect(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return ClipRRect(
    borderRadius:
        context.borderRadius(node.props['borderRadius']) ?? BorderRadius.zero,
    clipBehavior: _clipBehavior(node.props['clipBehavior']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildBackdropFilter(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return BackdropFilter(
    filter: _imageFilter(node.props['filter'] ?? node.props['imageFilter']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildDecoratedBox(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return DecoratedBox(
    decoration:
        context.boxDecoration(node.props) ??
        BoxDecoration(color: context.color(node.props['color'])),
    position: node.props['position'] == 'foreground'
        ? DecorationPosition.foreground
        : DecorationPosition.background,
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildRichText(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return RichText(
    textAlign:
        QuickjsUiProps.textAlign(node.props['textAlign']) ?? TextAlign.start,
    text: TextSpan(
      style: context.textStyle(node.props['style']),
      children: _textSpans(context, node.props['spans'] ?? node.props['text']),
    ),
  );
}

Widget _buildScaffold(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final appBar = _nodeProp(node.props['appBar']);
  final bottomNavigationBar = _nodeProp(node.props['bottomNavigationBar']);
  final drawer = _nodeProp(node.props['drawer']);
  final floatingActionButton = _nodeProp(node.props['floatingActionButton']);
  final scaffold = Scaffold(
    appBar: appBar == null
        ? null
        : _asPreferredSizeWidget(context.build(appBar), 'Scaffold.appBar'),
    body: _nodeProp(node.props['body']) == null
        ? context.child(node)
        : context.build(_nodeProp(node.props['body'])!),
    drawer: drawer == null ? null : context.build(drawer),
    bottomNavigationBar: bottomNavigationBar == null
        ? null
        : context.build(bottomNavigationBar),
    floatingActionButton: floatingActionButton == null
        ? null
        : context.build(floatingActionButton),
    backgroundColor: context.color(node.props['backgroundColor']),
  );
  final tabLength = QuickjsUiProps.intValue(node.props['tabLength']);
  if (tabLength == null || tabLength <= 0) {
    return scaffold;
  }
  return DefaultTabController(
    length: tabLength,
    initialIndex: QuickjsUiProps.intValue(node.props['initialTabIndex']) ?? 0,
    child: scaffold,
  );
}

Widget _buildAppBar(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final title = _nodeProp(node.props['title']);
  final leading = _nodeProp(node.props['leading']);
  final bottom = _nodeProp(node.props['bottom']);
  return AppBar(
    title: title == null
        ? _optionalText(QuickjsUiProps.string(node.props['titleText']))
        : context.build(title),
    leading: leading == null ? null : context.build(leading),
    actions: _nodeListProp(context, node.props['actions']),
    backgroundColor: context.color(node.props['backgroundColor']),
    foregroundColor: context.color(node.props['foregroundColor']),
    centerTitle: QuickjsUiProps.boolValue(node.props['centerTitle']),
    elevation: context.elevation(node.props['elevation']),
    bottom: bottom == null
        ? null
        : _asPreferredSizeWidget(context.build(bottom), 'AppBar.bottom'),
  );
}

Widget _buildBottomNavigationBar(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final onTap = QuickjsUiProps.event(node.props['onTap']);
  return BottomNavigationBar(
    currentIndex: QuickjsUiProps.intValue(node.props['currentIndex']) ?? 0,
    type: node.props['typeMode'] == 'shifting'
        ? BottomNavigationBarType.shifting
        : BottomNavigationBarType.fixed,
    onTap: onTap == null
        ? null
        : (index) => context.dispatchEvent(
            onTap,
            defaultCoalesceKey: _eventKey(node, 'onTap'),
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'index': index},
          ),
    items: _bottomNavigationItems(context, node.props['items']),
  );
}

Widget _buildTabBar(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onTap = QuickjsUiProps.event(node.props['onTap']);
  return TabBar(
    isScrollable: QuickjsUiProps.boolValue(node.props['isScrollable']) ?? false,
    onTap: onTap == null
        ? null
        : (index) => context.dispatchEvent(
            onTap,
            defaultCoalesceKey: _eventKey(node, 'onTap'),
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'index': index},
          ),
    tabs: _tabs(context, node.props['tabs']),
  );
}

Widget _buildTabBarView(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return TabBarView(children: context.children(node));
}

Widget _buildDrawer(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Drawer(child: context.child(node));
}

Widget _buildCircularProgressIndicator(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return CircularProgressIndicator(
    value: QuickjsUiProps.doubleValue(node.props['value']),
    color: context.color(node.props['color']),
    backgroundColor: context.color(node.props['backgroundColor']),
    strokeWidth: QuickjsUiProps.doubleValue(node.props['strokeWidth']) ?? 4,
  );
}

Widget _buildLinearProgressIndicator(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return LinearProgressIndicator(
    value: QuickjsUiProps.doubleValue(node.props['value']),
    color: context.color(node.props['color']),
    backgroundColor: context.color(node.props['backgroundColor']),
    minHeight: QuickjsUiProps.doubleValue(node.props['minHeight']),
  );
}

Widget _buildSnackBar(QuickjsUiRenderContext context, QuickjsUiNode node) {
  if (QuickjsUiProps.boolValue(node.props['visible']) == false) {
    return const SizedBox.shrink();
  }
  final content =
      context.child(node) ??
      Text(
        QuickjsUiProps.string(node.props['content'] ?? node.props['text']) ??
            '',
      );
  return _QuickjsUiSnackBarHost(
    signature: jsonEncode(node.toMap()),
    content: content,
    backgroundColor: context.color(node.props['backgroundColor']),
    duration:
        QuickjsUiProps.duration(node.props['durationMs']) ??
        const Duration(seconds: 4),
  );
}

Widget _buildAlertDialog(QuickjsUiRenderContext context, QuickjsUiNode node) {
  if (QuickjsUiProps.boolValue(node.props['visible']) == false) {
    return const SizedBox.shrink();
  }
  final title = _nodeProp(node.props['title']);
  final content = _nodeProp(node.props['content']);
  return AlertDialog(
    title: title == null
        ? _optionalText(QuickjsUiProps.string(node.props['titleText']))
        : context.build(title),
    content: content == null
        ? _optionalText(QuickjsUiProps.string(node.props['contentText']))
        : context.build(content),
    actions: _nodeListProp(context, node.props['actions']),
    backgroundColor: context.color(node.props['backgroundColor']),
  );
}

Widget _buildBottomSheet(QuickjsUiRenderContext context, QuickjsUiNode node) {
  if (QuickjsUiProps.boolValue(node.props['visible']) == false) {
    return const SizedBox.shrink();
  }
  final onClosing = QuickjsUiProps.event(node.props['onClosing']);
  return _QuickjsUiBottomSheetHost(
    signature: jsonEncode(node.toMap()),
    backgroundColor: context.color(node.props['backgroundColor']),
    onClosing: () {
      if (onClosing != null) {
        context.dispatchEvent(onClosing);
      }
    },
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildAnimatedAlign(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return AnimatedAlign(
    alignment:
        QuickjsUiProps.alignment(node.props['alignment']) ?? Alignment.center,
    duration: _animationDuration(node) ?? const Duration(milliseconds: 200),
    curve: QuickjsUiProps.curve(node.props['animationCurve']),
    widthFactor: QuickjsUiProps.doubleValue(node.props['widthFactor']),
    heightFactor: QuickjsUiProps.doubleValue(node.props['heightFactor']),
    child: context.child(node),
  );
}

Widget _buildAnimatedSwitcher(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return AnimatedSwitcher(
    duration: _animationDuration(node) ?? const Duration(milliseconds: 200),
    reverseDuration: QuickjsUiProps.duration(
      node.props['reverseDurationMs'],
      name: 'reverse animation duration',
    ),
    switchInCurve: QuickjsUiProps.curve(node.props['switchInCurve']),
    switchOutCurve: QuickjsUiProps.curve(node.props['switchOutCurve']),
    child: context.child(node),
  );
}

QuickjsUiNode? _nodeProp(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map) {
    return QuickjsUiNode.fromMap(
      value.map((key, value) => MapEntry<String, Object?>('$key', value)),
    );
  }
  throw const FormatException('quickjs_ui node property must be an object');
}

List<Widget>? _nodeListProp(QuickjsUiRenderContext context, Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw const FormatException('quickjs_ui node list property must be a list');
  }
  return <Widget>[
    for (final item in value)
      if (_nodeProp(item) case final node?) context.build(node),
  ];
}

PreferredSizeWidget _asPreferredSizeWidget(Widget widget, String name) {
  if (widget is PreferredSizeWidget) {
    return widget;
  }
  throw FormatException('quickjs_ui $name must render a PreferredSizeWidget');
}

Widget? _optionalText(String? value) {
  if (value == null) {
    return null;
  }
  return Text(value);
}

IconData _iconData(String? name) {
  return switch (name) {
    'add' => Icons.add,
    'arrowBack' || 'back' => Icons.arrow_back,
    'check' => Icons.check,
    'close' => Icons.close,
    'delete' => Icons.delete,
    'edit' => Icons.edit,
    'favorite' => Icons.favorite,
    'home' => Icons.home,
    'info' => Icons.info,
    'menu' => Icons.menu,
    'moreVert' => Icons.more_vert,
    'pause' => Icons.pause,
    'playArrow' || 'play' => Icons.play_arrow,
    'refresh' => Icons.refresh,
    'search' => Icons.search,
    'settings' => Icons.settings,
    'share' => Icons.share,
    'star' => Icons.star,
    'warning' => Icons.warning,
    _ => Icons.help_outline,
  };
}

List<InlineSpan> _textSpans(QuickjsUiRenderContext context, Object? value) {
  if (value == null) {
    return const <InlineSpan>[];
  }
  if (value is String) {
    return <InlineSpan>[TextSpan(text: value)];
  }
  if (value is! List) {
    throw const FormatException('quickjs_ui RichText spans must be a list');
  }
  return <InlineSpan>[for (final item in value) _textSpan(context, item)];
}

InlineSpan _textSpan(QuickjsUiRenderContext context, Object? value) {
  if (value is String) {
    return TextSpan(text: value);
  }
  if (value is Map) {
    final props = value.map(
      (key, value) => MapEntry<String, Object?>('$key', value),
    );
    return TextSpan(
      text: QuickjsUiProps.string(props['text']) ?? '',
      style: context.textStyle(props['style']),
      children: _textSpans(context, props['children']),
    );
  }
  throw const FormatException('quickjs_ui TextSpan must be a string or object');
}

List<BottomNavigationBarItem> _bottomNavigationItems(
  QuickjsUiRenderContext context,
  Object? value,
) {
  if (value is! List || value.length < 2) {
    throw const FormatException(
      'quickjs_ui BottomNavigationBar.items must contain at least two items',
    );
  }
  return <BottomNavigationBarItem>[
    for (final item in value) _bottomNavigationItem(context, item),
  ];
}

BottomNavigationBarItem _bottomNavigationItem(
  QuickjsUiRenderContext context,
  Object? value,
) {
  if (value is! Map) {
    throw const FormatException(
      'quickjs_ui BottomNavigationBar item must be an object',
    );
  }
  final props = value.map(
    (key, value) => MapEntry<String, Object?>('$key', value),
  );
  final icon = _nodeProp(props['icon']);
  final activeIcon = _nodeProp(props['activeIcon']);
  return BottomNavigationBarItem(
    icon: icon == null
        ? Icon(_iconData(QuickjsUiProps.string(props['iconName'])))
        : context.build(icon),
    activeIcon: activeIcon == null ? null : context.build(activeIcon),
    label: QuickjsUiProps.string(props['label']) ?? '',
    tooltip: QuickjsUiProps.string(props['tooltip']),
  );
}

List<Widget> _tabs(QuickjsUiRenderContext context, Object? value) {
  if (value is! List || value.isEmpty) {
    throw const FormatException(
      'quickjs_ui TabBar.tabs must be a non-empty list',
    );
  }
  return <Widget>[for (final tab in value) _tab(context, tab)];
}

Widget _tab(QuickjsUiRenderContext context, Object? value) {
  if (value is String) {
    return Tab(text: value);
  }
  if (value is Map) {
    final props = value.map(
      (key, value) => MapEntry<String, Object?>('$key', value),
    );
    final child = _nodeProp(props['child']);
    final icon = _nodeProp(props['icon']);
    return Tab(
      text: QuickjsUiProps.string(props['text'] ?? props['label']),
      icon: icon == null ? null : context.build(icon),
      child: child == null ? null : context.build(child),
    );
  }
  throw const FormatException('quickjs_ui Tab must be a string or object');
}

FlexFit _flexFit(Object? value) {
  return switch (value) {
    null || 'tight' => FlexFit.tight,
    'loose' => FlexFit.loose,
    _ => throw const FormatException('Unknown quickjs_ui FlexFit'),
  };
}

WrapAlignment _wrapAlignment(Object? value) {
  return switch (value) {
    null || 'start' => WrapAlignment.start,
    'end' => WrapAlignment.end,
    'center' => WrapAlignment.center,
    'spaceBetween' => WrapAlignment.spaceBetween,
    'spaceAround' => WrapAlignment.spaceAround,
    'spaceEvenly' => WrapAlignment.spaceEvenly,
    _ => throw const FormatException('Unknown quickjs_ui WrapAlignment'),
  };
}

WrapCrossAlignment _wrapCrossAlignment(Object? value) {
  return switch (value) {
    null || 'start' => WrapCrossAlignment.start,
    'end' => WrapCrossAlignment.end,
    'center' => WrapCrossAlignment.center,
    _ => throw const FormatException('Unknown quickjs_ui WrapCrossAlignment'),
  };
}

Clip _clipBehavior(Object? value) {
  return switch (value) {
    null || 'antiAlias' => Clip.antiAlias,
    'none' => Clip.none,
    'hardEdge' => Clip.hardEdge,
    'antiAliasWithSaveLayer' => Clip.antiAliasWithSaveLayer,
    _ => throw const FormatException('Unknown quickjs_ui Clip'),
  };
}

ui.ImageFilter _imageFilter(Object? value) {
  if (value == null) {
    return ui.ImageFilter.blur();
  }
  if (value is String) {
    if (value == 'blur') {
      return ui.ImageFilter.blur();
    }
    throw FormatException('Unsupported quickjs_ui ImageFilter "$value"');
  }
  if (value is! Map) {
    throw const FormatException('quickjs_ui ImageFilter must be an object');
  }
  final props = value.map(
    (key, value) => MapEntry<String, Object?>('$key', value),
  );
  final type = props['type'] ?? props['kind'];
  switch (type) {
    case null:
    case 'blur':
      final sigma = QuickjsUiProps.doubleValue(props['sigma']);
      return ui.ImageFilter.blur(
        sigmaX: QuickjsUiProps.doubleValue(props['sigmaX']) ?? sigma ?? 0,
        sigmaY: QuickjsUiProps.doubleValue(props['sigmaY']) ?? sigma ?? 0,
      );
  }
  throw FormatException('Unsupported quickjs_ui ImageFilter "$type"');
}

EdgeInsets _edgeInsets(EdgeInsetsGeometry? value) {
  return switch (value) {
    null => EdgeInsets.zero,
    EdgeInsets edgeInsets => edgeInsets,
    _ => EdgeInsets.zero,
  };
}

Widget _withGestures(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
  Widget child,
) {
  final onTap = QuickjsUiProps.event(node.props['onTap']);
  final onLongPress = QuickjsUiProps.event(node.props['onLongPress']);
  final onDoubleTap = QuickjsUiProps.event(node.props['onDoubleTap']);
  final onDragStart = QuickjsUiProps.event(node.props['onDragStart']);
  final onDragUpdate = QuickjsUiProps.event(node.props['onDragUpdate']);
  final onDragEnd = QuickjsUiProps.event(node.props['onDragEnd']);
  final onSwipe = QuickjsUiProps.event(node.props['onSwipe']);
  final hasPan =
      onDragStart != null ||
      onDragUpdate != null ||
      onDragEnd != null ||
      onSwipe != null;
  if (onTap == null && onLongPress == null && onDoubleTap == null && !hasPan) {
    return child;
  }
  Offset dragTotal = Offset.zero;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap == null
        ? null
        : () => context.dispatchEvent(
            onTap,
            defaultCoalesceKey: _eventKey(node, 'onTap'),
          ),
    onLongPress: onLongPress == null
        ? null
        : () => context.dispatchEvent(
            onLongPress,
            defaultCoalesceKey: _eventKey(node, 'onLongPress'),
          ),
    onDoubleTap: onDoubleTap == null
        ? null
        : () => context.dispatchEvent(
            onDoubleTap,
            defaultCoalesceKey: _eventKey(node, 'onDoubleTap'),
          ),
    onPanStart: !hasPan
        ? null
        : (details) {
            dragTotal = Offset.zero;
            if (onDragStart != null) {
              context.dispatchEvent(
                onDragStart,
                defaultCoalesceKey: _eventKey(node, 'onDragStart'),
                payload: <String, Object?>{
                  'x': details.localPosition.dx,
                  'y': details.localPosition.dy,
                  'globalX': details.globalPosition.dx,
                  'globalY': details.globalPosition.dy,
                },
              );
            }
          },
    onPanUpdate: !hasPan
        ? null
        : (details) {
            dragTotal += details.delta;
            if (onDragUpdate != null) {
              context.dispatchEvent(
                onDragUpdate,
                defaultCoalesceKey: _eventKey(node, 'onDragUpdate'),
                kind: QuickjsUiEventKind.sample,
                payload: <String, Object?>{
                  'deltaX': details.delta.dx,
                  'deltaY': details.delta.dy,
                  'totalDeltaX': dragTotal.dx,
                  'totalDeltaY': dragTotal.dy,
                  'x': details.localPosition.dx,
                  'y': details.localPosition.dy,
                  'globalX': details.globalPosition.dx,
                  'globalY': details.globalPosition.dy,
                },
              );
            }
          },
    onPanEnd: onDragEnd == null && onSwipe == null
        ? null
        : (details) {
            if (onDragEnd != null) {
              context.dispatchEvent(
                onDragEnd,
                defaultCoalesceKey: _eventKey(node, 'onDragEnd'),
                payload: <String, Object?>{
                  'velocityX': details.velocity.pixelsPerSecond.dx,
                  'velocityY': details.velocity.pixelsPerSecond.dy,
                  'totalDeltaX': dragTotal.dx,
                  'totalDeltaY': dragTotal.dy,
                },
              );
            }
            if (onSwipe != null) {
              final direction = _swipeDirection(
                dragTotal,
                details.velocity.pixelsPerSecond,
              );
              if (direction != null) {
                context.dispatchEvent(
                  onSwipe,
                  defaultCoalesceKey: _eventKey(node, 'onSwipe'),
                  payload: <String, Object?>{
                    'direction': direction,
                    'velocityX': details.velocity.pixelsPerSecond.dx,
                    'velocityY': details.velocity.pixelsPerSecond.dy,
                    'totalDeltaX': dragTotal.dx,
                    'totalDeltaY': dragTotal.dy,
                  },
                );
              }
            }
          },
    child: child,
  );
}

String? _swipeDirection(Offset delta, Offset velocity) {
  const minDistance = 40.0;
  const minVelocity = 300.0;
  final primaryDelta = delta.dx.abs() >= delta.dy.abs() ? delta.dx : delta.dy;
  final primaryVelocity = delta.dx.abs() >= delta.dy.abs()
      ? velocity.dx
      : velocity.dy;
  if (primaryDelta.abs() < minDistance && primaryVelocity.abs() < minVelocity) {
    return null;
  }
  if (delta.dx.abs() >= delta.dy.abs()) {
    return primaryDelta >= 0 ? 'right' : 'left';
  }
  return primaryDelta >= 0 ? 'down' : 'up';
}

String _eventKey(QuickjsUiNode node, String prop) {
  final key = node.props['key'];
  if (key is String && key.isNotEmpty) {
    return '${node.type}:$key:$prop';
  }
  return '${node.type}:${identityHashCode(node)}:$prop';
}

final class _QuickjsUiSnackBarHost extends StatefulWidget {
  const _QuickjsUiSnackBarHost({
    required this.signature,
    required this.content,
    required this.duration,
    this.backgroundColor,
  });

  final String signature;
  final Widget content;
  final Color? backgroundColor;
  final Duration duration;

  @override
  State<_QuickjsUiSnackBarHost> createState() => _QuickjsUiSnackBarHostState();
}

final class _QuickjsUiSnackBarHostState extends State<_QuickjsUiSnackBarHost> {
  String? _shownSignature;

  @override
  void initState() {
    super.initState();
    _scheduleShow();
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiSnackBarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signature != widget.signature) {
      _scheduleShow();
    }
  }

  void _scheduleShow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shownSignature == widget.signature) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        return;
      }
      _shownSignature = widget.signature;
      messenger.showSnackBar(
        SnackBar(
          content: widget.content,
          backgroundColor: widget.backgroundColor,
          duration: widget.duration,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

final class _QuickjsUiBottomSheetHost extends StatefulWidget {
  const _QuickjsUiBottomSheetHost({
    required this.signature,
    required this.child,
    required this.onClosing,
    this.backgroundColor,
  });

  final String signature;
  final Widget child;
  final Color? backgroundColor;
  final VoidCallback onClosing;

  @override
  State<_QuickjsUiBottomSheetHost> createState() =>
      _QuickjsUiBottomSheetHostState();
}

final class _QuickjsUiBottomSheetHostState
    extends State<_QuickjsUiBottomSheetHost> {
  String? _shownSignature;

  @override
  void initState() {
    super.initState();
    _scheduleShow();
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiBottomSheetHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signature != widget.signature) {
      _scheduleShow();
    }
  }

  void _scheduleShow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shownSignature == widget.signature) {
        return;
      }
      if (Navigator.maybeOf(context) == null) {
        return;
      }
      _shownSignature = widget.signature;
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: widget.backgroundColor,
        builder: (_) => widget.child,
      ).whenComplete(widget.onClosing);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

final class _QuickjsUiTextField extends StatefulWidget {
  const _QuickjsUiTextField({
    required this.value,
    required this.focusId,
    required this.enabled,
    required this.autofocus,
    required this.requestFocus,
    required this.clearFocus,
    required this.obscureText,
    required this.decoration,
    required this.submitFocusAction,
    this.maxLines,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onFocus,
    this.onBlur,
    this.onSelectionChanged,
  });

  final String value;
  final String? focusId;
  final bool enabled;
  final bool autofocus;
  final bool requestFocus;
  final bool clearFocus;
  final bool obscureText;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final _QuickjsUiSubmitFocusAction submitFocusAction;
  final InputDecoration decoration;
  final ValueChanged<Map<String, Object?>>? onChanged;
  final ValueChanged<Map<String, Object?>>? onSubmitted;
  final ValueChanged<Map<String, Object?>>? onEditingComplete;
  final ValueChanged<Map<String, Object?>>? onFocus;
  final ValueChanged<Map<String, Object?>>? onBlur;
  final ValueChanged<Map<String, Object?>>? onSelectionChanged;

  @override
  State<_QuickjsUiTextField> createState() => _QuickjsUiTextFieldState();
}

final class _QuickjsUiTextFieldState extends State<_QuickjsUiTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  TextSelection? _lastSelection;
  TextRange? _lastComposing;
  bool _syncingController = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _lastSelection = _controller.selection;
    _lastComposing = _controller.value.composing;
    _controller.addListener(_handleControllerChange);
    _focusNode = FocusNode()..addListener(_handleFocusChange);
    if (widget.requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestFocus());
    }
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _syncingController = true;
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
      _syncingController = false;
      _lastSelection = _controller.selection;
      _lastComposing = _controller.value.composing;
    }
    if (!oldWidget.requestFocus && widget.requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestFocus());
    }
    if (!oldWidget.clearFocus && widget.clearFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _clearFocus());
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.removeListener(_handleControllerChange);
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      widget.onFocus?.call(_snapshot());
    } else {
      widget.onBlur?.call(_snapshot());
    }
  }

  void _handleControllerChange() {
    if (_syncingController) {
      return;
    }
    final selection = _controller.selection;
    final composing = _controller.value.composing;
    if (selection == _lastSelection && composing == _lastComposing) {
      return;
    }
    _lastSelection = selection;
    _lastComposing = composing;
    widget.onSelectionChanged?.call(_snapshot());
  }

  void _requestFocus() {
    if (!mounted || !widget.enabled || _focusNode.hasFocus) {
      return;
    }
    _focusNode.requestFocus();
  }

  void _clearFocus() {
    if (!mounted || !_focusNode.hasFocus) {
      return;
    }
    _focusNode.unfocus();
  }

  void _handleEditingComplete() {
    widget.onEditingComplete?.call(_snapshot());
    final scope = FocusScope.of(context);
    switch (widget.submitFocusAction) {
      case _QuickjsUiSubmitFocusAction.none:
        break;
      case _QuickjsUiSubmitFocusAction.next:
        scope.nextFocus();
      case _QuickjsUiSubmitFocusAction.previous:
        scope.previousFocus();
      case _QuickjsUiSubmitFocusAction.unfocus:
        _focusNode.unfocus();
    }
  }

  Map<String, Object?> _snapshot() {
    final value = _controller.value;
    return <String, Object?>{
      'value': value.text,
      if (widget.focusId != null) 'focusId': widget.focusId,
      'selectionStart': value.selection.start,
      'selectionEnd': value.selection.end,
      'selectionBaseOffset': value.selection.baseOffset,
      'selectionExtentOffset': value.selection.extentOffset,
      'composingStart': value.composing.start,
      'composingEnd': value.composing.end,
    };
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: widget.obscureText,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      decoration: widget.decoration,
      onChanged: widget.onChanged == null
          ? null
          : (_) => widget.onChanged?.call(_snapshot()),
      onSubmitted: widget.onSubmitted == null
          ? null
          : (_) => widget.onSubmitted?.call(_snapshot()),
      onEditingComplete: _handleEditingComplete,
    );
  }
}

enum _QuickjsUiSubmitFocusAction { none, next, previous, unfocus }
