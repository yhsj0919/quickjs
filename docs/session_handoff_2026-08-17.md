# Lemon JS API 审查交接（2026-08-17）

## 1. 当前目标

继续完成四个 package 的公开 API 审查与破坏性迁移收尾。主清单位于
`docs/api_review_plan.md`，迁移对照表位于 `docs/breaking_api_migration.md`。

四个 package 的公开 API 注释覆盖均已完成，`public_member_api_docs` 已清零。
`lemon_js_ui` 整包 Analyze 0 问题，配置现有 Debug `quickjs.dll` 后全量 244 项
测试通过。API 审查和非 Web 仓库验证均已收尾，剩余环境边界只有暂缓的 Chrome
Web consistency 验证。

## 2. 已完成的主要工作

### API 与平台命名

- 清理 JSUI 无用别名：`defineComponent`、`action`、`event`。
- 补全 `Component()` TypeScript 声明。
- 五个平台插件壳统一为 `LemonJsPlugin` / `lemon_js_plugin`。
- Android namespace 改为 `xyz.yhsj.lemon_js`。
- Windows 插件 target 编译通过。
- 清理 Core、UI、Extensions 中可修改的 `Quickjs/quickjs` 旧命名；引擎事实、C ABI、
  Web bridge 与 `quickjs_ui` 协议身份按计划保留。

### 修复与测试

- 修复 Axios 资源路径。
- 修复两个示例页面的 Timer 泄漏。
- 修复 Permission 错误展示。
- 修复 Core 测试以适配新的 `eval` / `run` 结构化返回语义、`JsUndefined.value`、
  队列取消时序和异步回调声明。
- 改进 `tool/verify.ps1`：
  - 避免 `ProcessStartInfo` 输出死锁；
  - 通过 Dart VM 启动 Flutter tools；
  - 纳入 Extensions analyze/test；
  - 修正 consistency 测试路径；
  - Web 测试使用 `--platform chrome`；
  - 增加 `-SkipFormat`；
  - 完整模式初始化 native DLL 并将 DLL 目录加入 `PATH`。

### 文档与迁移

- 已创建 `docs/breaking_api_migration.md`，完整破坏性迁移表已在审查清单中标记完成。
- `docs/api_review_plan.md` 已记录各包 Analyze/Test 状态和剩余环境限制。
- Core `engine.dart` 原先 59 条公开注释缺口已清零。
- Core `exception.dart`、Extensions Manifest/Manager/Flow/Package/Update/View/Registry/
  Session/Storage、UI 高频基础类型均已补充公开注释。

## 3. 当前公开注释 lint 状态

四个 package 的 `analysis_options.yaml` 已启用：

```yaml
linter:
  rules:
    public_member_api_docs: true
```

### lemon_js（Core）

- 整包 `dart analyze`：**0 问题**。
- 主入口和 `lemon_js_context.dart` 的真实公开 API 注释已清零。
- 已补注释的重点文件：
  - `lib/src/runtime/engine.dart`
  - `lib/src/diagnostics/exception.dart`
  - `lib/src/diagnostics/source_map.dart`
  - `lib/src/runtime/plugin.dart`
  - `lib/src/runtime/plugin_tools.dart`
  - `lib/src/runtime/context.dart`
  - `lib/src/runtime/value.dart`
  - `lib/src/module/fetch_features.dart`
  - `lib/src/module/key_value_storage.dart`
  - `lib/src/module/web_crypto_features.dart`
  - `lib/src/module/websocket_features_io.dart`
  - `lib/src/module/websocket_features_stub.dart`
- native、bridge、backend、runtime-base 等不属于稳定公开入口的文件使用
  `// ignore_for_file: public_member_api_docs` 明确内部边界；未关闭其他 analyzer 检查。

### lemon_js_extensions

- 整包 `dart analyze`：**0 问题**。
- `public_member_api_docs` 已全部清零。
- 最后一批完成的是：
  - `extension_default_store_io.dart`
  - `extension_default_store_preferences.dart`
  - `extension_file_store_io.dart`
  - `extension_file_store_stub.dart`
  - `extension_package_file_io.dart`
  - `extension_package_file_stub.dart`
  - `extension_session.dart`
  - `extension_storage.dart`

### lemon_js_ui_video_player

- 整包 Analyze：**0 问题**。
- 公开注释 lint：**0 缺口**。

### lemon_js_ui

- 整包 `dart analyze`：**0 问题**。
- `public_member_api_docs`：**0 缺口**（从 921 条清零）。
- 主入口及独立 Session 入口的真实公开 API 已补充契约文档。
- 未从 package 入口导出的 renderer、helper 与平台实现文件使用文件级
  `public_member_api_docs` 豁免明确内部边界，未关闭其他 analyzer 检查。
- 已完成并定向 Analyze 0 问题的基础类型包括：
  - `quickjs_ui_node.dart`
  - `quickjs_ui_runtime.dart`
  - `quickjs_ui_view.dart`
  - `quickjs_ui_props.dart`
  - `quickjs_ui_controller.dart`
  - `quickjs_ui_render_context.dart`
  - `quickjs_ui_dev_options.dart`
  - `quickjs_ui_diff_stats.dart`
  - `quickjs_ui_lifecycle_event.dart`
  - `quickjs_ui_load_metrics.dart`
  - `quickjs_ui_network_journal.dart`

最后一组 UI 诊断文件共清理 21 条，定向 Analyze 为 0。

## 4. 收尾状态

- 四包 API 审查、命名迁移、公开注释和迁移文档均已完成。
- iOS/macOS 示例 RunnerTests 已同步使用 `lemon_js` 模块和 `LemonJsPlugin` 平台类。
- 路线图中的旧 `QuickjsPluginClient` 名称已同步为 `JsPluginClient`。
- 公开类型前缀已再次集中复核：Core KV 实现统一为 `Js*`，Extensions 的 Store、
  Manager 和 Installation 模型统一为 `JsExtension*`；迁移表已补充对应改名。
- 五个工程 Analyze 均为 0 问题。
- 所有非 Web 测试已在本次收尾重新执行并通过。
- `git diff --check` 无空白错误；LF/CRLF 输出是 Git 的行尾转换提示。

提交前需确保将删除与对应新增文件一起暂存，以便 Git 正确识别本轮大规模重命名。

## 5. 已知验证结果与未闭环项

最近已确认：

- Core：包含 WebSocket 在内的 241 项原生测试通过；整包 Analyze 0。
- UI：244 项测试通过。
- Extensions：36 项测试通过；整包 Analyze 0。
- Video Player：3 项通过，其中包含约 25 秒 progress storm 测试；整包 Analyze 0。
- Example：58 项通过；运行时需要将包含 `fvp.dll` 的 runner Debug 目录加入 `PATH`。
- Windows 平台插件 target 编译通过。
- Core WebSocket 超时已修复：host script 内部错误调用不存在的 `dispatch()`，现统一
  使用标准 `dispatchEvent()`；定向测试与 Core 241 项原生测试均通过。
- Web consistency 使用正确的 `--platform chrome` 后，当前环境连续三次无法启动 Chrome。
- `git diff --check` 最近只有仓库既存的 LF/CRLF 提示，没有空白错误。

不要把 Chrome 环境问题当作已完成；也不要为解决性能问题绕过
`docs/performance_troubleshooting.md` 规定的测量流程。

## 6. 工作区与安全注意事项

- 工作树包含大量本轮及用户已有改动，不要 reset、checkout 或覆盖无关文件。
- 源码修改统一使用 `apply_patch`。
- 新增示例必须追加到用户可见示例列表末尾，不能插入现有条目前面。
- 修改 Core 前需要先向用户说明原因、范围和可能影响。
- `dart format` 偶尔会输出“拒绝访问 / Could not overwrite”后仍显示 formatted；必须以随后
  `dart analyze` 和实际 diff 为准，不要只相信 format 的状态文本。
