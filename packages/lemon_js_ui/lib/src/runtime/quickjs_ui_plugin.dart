import 'package:lemon_js/lemon_js.dart';

import '../renderer/quickjs_ui_component_registry.dart';

/// 将 Flutter 组件注册逻辑写入 [JsUiComponentRegistry] 的回调类型。
typedef JsUiRegistryConfigurator =
    void Function(JsUiComponentRegistry registry);

/// 安装到 [JsUiView] 的原生 UI 扩展插件。
///
/// 第三方 UI 控件通常需要两部分能力：
/// 1. [features]：让 JS 能 `import` 对应模块（例如 `quickjs_ui/video_player`）。
/// 2. `configure`：让 Flutter 渲染层认识 schema 中的 `type`（例如 `VideoPlayer`）。
///
/// 通过 [JsUiPlugin] 把这两部分绑在一起，避免只配置 registry 或只配置 features
/// 导致页面一半能力缺失。
final class JsUiPlugin {
  /// 创建一个 UI 插件描述对象。
  ///
  /// - [name]：插件稳定名称，用于调试与冲突识别。
  /// - [features]：该插件需要的 JS runtime features 列表。
  /// - [configure]：向渲染注册表注册原生组件构建器的回调。
  const JsUiPlugin({
    required this.name,
    this.features = const <JsFeatures>[],
    JsUiRegistryConfigurator? configure,
  }) : _configurator = configure;

  /// 插件稳定名称。
  final String name;

  /// 该 UI 插件依赖的 JS runtime features。
  ///
  /// 会在 [JsUiView] 创建 runtime 时与业务 [JsUiView.features] 合并加载。
  final List<JsFeatures> features;

  /// 向 [JsUiComponentRegistry] 注册原生组件构建器。
  ///
  /// 例如将 schema 节点 `type: 'VideoPlayer'` 映射到 Flutter `VideoPlayer` widget。
  final JsUiRegistryConfigurator? _configurator;

  /// 将本插件的组件注册写入 [registry]。
  void configure(JsUiComponentRegistry registry) {
    _configurator?.call(registry);
  }
}
