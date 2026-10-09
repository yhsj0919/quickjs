# Dart 原生 JavaScript Runtime 方案讨论

记录日期：2026-10-08。状态：方案讨论，尚未实现。

本文记录当前方向和建议。示例 API 仅用于说明使用体验，名称、包结构和执行参数尚未确定。现有 QuickJS 后端继续保留，不因本方案改动。

## 定位

希望实现一个纯 Dart 的通用 JavaScript 引擎，兼容大部分主流标准 JavaScript。核心库不依赖 Flutter，也不认识 Widget、页面和 UI 生命周期。JSUI 是独立接入层，不能反过来决定语言核心的行为。

主要目标是接入简单、使用直接、代码易读且容易维护。希望减少现有 QuickJS 与 Dart 之间的 FFI、序列化、对象 handle 和异步桥接负担。不追求超高性能，但必须维持实际使用所需的功能和响应速度。

UI 接入以典型场景达到 120 Hz 为验证目标，而非引擎对所有脚本、设备和页面的保证。120 Hz 每帧约 8.33 ms，JS 只能使用其中一部分时间，Flutter 仍需要构建、布局和绘制。

## 模块边界

| 模块 | 职责 | 扩展边界 |
| --- | --- | --- |
| 语言前端 | 词法、语法、AST、字节码编译 | 引擎内部维护，统一字节码契约 |
| 执行核心 | 值、对象模型、作用域、执行帧、调用、异常、执行预算 | 不依赖 UI、IO 或具体宿主包 |
| 标准库 | Object、Array、String、Math、JSON、Date、RegExp 等 | 通过标准对象和函数接入，遵循 JS 语义 |
| 异步支持 | Promise、jobs 队列、async/await 的挂起与恢复 | 与执行帧和语言前端有明确契约 |
| 模块加载 | 模块解析、链接、实例化、模块状态 | 宿主提供源码和名称解析，不内置网络或文件策略 |
| Dart 互操作 | HostFunction、HostObject、HostClass、Future 适配 | 显式绑定，支持生成绑定代码 |
| 环境扩展 | 文件、网络、Timer、Web／Node 风格能力 | 独立模块，由宿主显式安装 |
| Flutter／JSUI | Widget、controller、页面资源和渲染协议 | 独立接入，不进入语言核心 |

这些首先是代码边界，初期可以在一个 package 中按目录组织。边界稳定后，再按实际独立使用需求拆包，不先创建十几个互相转发的 package。

新增 HTTP、数据库或 Dart 包绑定，应只改对应扩展。新增语言能力则可能需要同时修改前端、编译器和执行器，例如 async/await；目标是修改范围明确，不能承诺语言演进完全没有耦合。

不优先建设通用 SyntaxFeature、CompilerFeature 或 Opcode 插件体系。标准语言实现直接维护，宿主模块和环境能力提供扩展接口。缺少依赖时明确报错，不自动扫描、偷偷安装或修改全局环境。

## JavaScript 兼容

后续需要选定 ECMAScript 版本基线，并维护支持清单、已知差异和测试结果。“大部分标准 JS”不能只按语法数量衡量。

从第一阶段就确定原型链、属性描述符、属性键、this、闭包和异常的底层模型。功能可以逐步开放，但不能先把对象当作普通 Dart Map，后面再补对象语义。

Promise、模块和 async/await 可以分文件或模块维护，但执行核心必须预留 jobs 检查点、模块状态和执行帧挂起机制。不能把这些全部当作无须改变执行模型的外挂函数。

建议使用 test262 中对应已实现能力的测试，并用 QuickJS 做结果差分。未支持的功能应明确报告，不静默执行成另一种行为。真实 JS 包另做集成测试。

## 复用 Dart 基础能力

Dart 提供实现材料，ECMAScript 规范决定外部行为。能复用的能力优先复用，但不能直接把 Dart API 当作同名 JS API。

- RegExp：复用 Dart 匹配能力，补齐 JS 对象的状态、lastIndex、方法和目标规范版本要求。
- Date：复用时间计算能力，补齐 Invalid Date、转换、时间范围和方法语义。
- TypedArray／ArrayBuffer：复用 dart:typed_data，补齐视图、索引、类型转换和缓冲区状态。
- JSON：复用适合的编码工具，但保留 undefined、toJSON、键顺序、循环引用等 JS 规则。
- Math／文本编码：复用 Dart 底层能力，并测试数值和编码边界。
- Promise：可以接收 Dart Future，JS Promise 状态、thenable 吸收和 jobs 顺序由引擎管理。
- 文件、网络和 Timer：由环境模块包装 Dart API，按宿主权限开放。

数值转换、对象相等性、属性枚举等语言语义由引擎负责。Dart GC 可以管理引用内存，但不会自动完成 controller、文件或订阅的显式释放。

## Dart 与 JS 接入体验

对外尽量保留少量直接入口：安装能力、注册宿主模块、注册 JS 包和配置模块解析器。

```dart
// API 设想，尚未实现。
final runtime = JsRuntime();
runtime.install(JsStandardLibrary());
runtime.install(DartInterop());

runtime.registerModule(
  'app',
  exports: {
    'log': (String message) => print(message),
    'getUser': () async => userService.getUser(),
    'settings': settingsBinding,
  },
);
```

```js
import { log, getUser, settings } from 'app';

const user = await getUser();
log(user.name);
settings.theme = 'dark';
```

普通 Dart 函数尽量直接注册，Future 自动适配 Promise。任意函数签名的适配能力需要验证；不能默认认为 Flutter AOT 可以通过运行时反射调用所有 Dart API。

对象采用显式描述符或构建时生成绑定，声明开放的属性、方法、构造函数和参数规则。保留手动绑定处理特殊 API。使用者不应手动管理 callback 编号、序列化格式和跨语言 handle。

区分普通参数值与 HostObject：普通参数按约定转换，HostObject 引用真实 Dart 对象。明确对象身份、写入是否影响宿主、谁拥有资源、何时释放，以及释放后调用如何报错。

JS 包通过统一模块解析器加载模块图，不让调用者逐个拼接源码。本地文件、assets、ZIP 或网络来源属于加载工具和宿主策略。npm 包的依赖安装、package.json 入口解析、CommonJS 处理和打包不属于 VM 指令循环；Node API、原生扩展或 DOM 依赖需要相应环境，不能承诺任意 npm 包开箱即用。

## 执行与长任务

同一 isolate 内才能直接共享 Dart 对象并进行同步调用。放入后台 isolate 后，仍需要消息通信，不能直接操作 UI isolate 的 Flutter 对象。

Future 不会自动把同步计算移到后台。建议区分同步调用与可挂起调用：

```dart
// API 设想，尚未实现。
JsValue callSync(...);          // 必须立即返回，超预算明确失败。
Future<JsValue> callAsync(...); // 支持等待、执行分片和取消。
```

长任务可以按指令或时间预算保存执行位置、寄存器、调用帧和异常状态，让出事件循环后恢复。调度机制由宿主选择，核心不依赖 Flutter 帧回调。

引擎内部的时间片让出不能改变 JS 任务顺序：同一 runtime 的其他调用通常排队，不能在普通同步函数执行到一半时随意插入。Promise jobs 在规定的检查点执行；真正执行到 await 时，按异步语义挂起和恢复。反复安排 microtask 不能代替适当的事件循环让出。

同步 itemBuilder 等 Flutter 回调不能返回 Future，应保持短小并受预算约束。排序、JSON、正则等长内置操作也要考虑执行预算。阻塞的 Dart 宿主函数不能靠 VM 指令分片自动中断，应使用异步 API 或独立计算任务。

宿主回调重入、取消、try/finally、异步异常和 runtime 销毁必须从早期测试，不在功能完成后再补生命周期。

## moejs 参考范围

参考 [moejs](https://github.com/Calcium-Ion/moejs) 的寄存器字节码、不可变编译产物复用和低成本宿主调用设计。它在 await 时保存和恢复执行帧，值得参考；中断检查不等于通用时间片挂起恢复。[async 实现](https://github.com/Calcium-Ion/moejs/blob/main/engine/async.go)、[中断实现](https://github.com/Calcium-Ion/moejs/blob/main/engine/interrupt.go)

moejs 的插件基准包含宿主转换成本，QuickJS 对照通过 cgo 和 JSON 交换，不能直接推导 Dart 实现比当前 QuickJS 更快。[性能说明](https://github.com/Calcium-Ion/moejs/blob/main/docs/performance.md)

它的 Go map 懒转换与实时 HostObject 不同，服务器请求 runtime 池也不能直接作为有状态 UI 的生命周期。冻结并共享标准库可能影响会修改内置原型的 JS 包，需要在兼容性与内存之间明确选择。[使用指南](https://github.com/Calcium-Ion/moejs/blob/main/docs/guide.md)

初期不照搬 unsafe pointer、16 字节值布局或 NaN-boxing。优先普通 Dart 类型和易读执行逻辑，测出分配或访问瓶颈后再优化。

## 原型验证与未决事项

先独立验证，不立即替换现有 QuickJS：

1. 完成基本表达式、对象、数组、函数、闭包和宿主调用，验证基础语义与错误报告。
2. 验证真实 JS 模块、Dart 函数绑定、HostObject 属性方法，以及 Future／Promise。
3. 接入计数器、同步列表 builder、TextEditingController 共享与释放等代表性 JSUI 场景。
4. 验证长任务分片、取消、重入和销毁；在目标手机 profile/release 中比较耗时、内存和帧率。

Flutter 负责动画和滚动等连续更新，JS 处理事件和必要的状态变化，不要求每帧重新生成整页。逐帧 JS 场景单独测量。性能优化遵循仓库的测量流程，不因方案设想提前重写现有系统。

尚需决定：语言版本基线、标准库默认安装范围、可变内置对象策略、同步执行预算、时间片调度方式、绑定生成器的最小声明、模块兼容范围，以及哪些现有 JSUI 协议可直接复用。
