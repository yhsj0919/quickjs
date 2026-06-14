# Dart class binding lifecycle

本文档说明 `Quickjs.bindClass<T>()` 第一版窄切片的生命周期语义。当前实现只覆盖显式 descriptor 绑定，不支持 Dart 反射、继承、静态成员或 JS GC 驱动的 Dart 对象回收。

## API shape

```dart
final handle = await engine.bindClass<User>(
  'User',
  QuickjsClass<User>(
    constructor: (args) => User(args.single as String),
    accessors: {
      'name': QuickjsInstanceAccessor<User>(
        get: (user) => user.name,
        set: (user, value) {
          user.name = value as String;
        },
      ),
    },
    methods: {
      'greet': (user, args) => 'Hello ${args.single}, I am ${user.name}',
    },
  ),
);
```

JavaScript 侧保持自然构造写法：

```js
const user = new User('Tom');
const name = await user.name;
user.name = 'Jerry';
const greeting = await user.greet('Alice');
```

## Construction

`new User(...)` 会同步返回一个 JS instance proxy。Dart constructor 不会同步阻塞 JS constructor，而是通过现有 Promise callback bridge 在 Dart 侧创建实例。

每个 JS instance proxy 内部保存：

- runtime/class 作用域内唯一的 instance id。
- 一个 constructor `ready` Promise。
- 一个 disposed 标记。

instance getter 和 method 会先等待 `ready` Promise，然后用 instance id 到 Dart runtime-owned instance table 中查找真实 Dart 对象。

## Getter, Setter, Method Semantics

getter 在 JS 侧表现为 Promise：

```js
const value = await user.name;
```

method 也通过 Promise callback bridge 返回 Promise：

```js
const result = await user.greet('Alice');
```

setter 使用 JS accessor assignment 语法：

```js
user.name = 'Jerry';
```

JavaScript assignment 表达式本身不能返回 setter 内部的 Promise，因此 async setter 错误不能通过 `await user.name = ...` 这类写法捕获。需要可 await 的写入语义时，应优先暴露显式 method，例如 `await user.setName('Jerry')`。

## Ownership

Dart 实例由所属 `Quickjs` runtime 管理。当前实现的所有权边界是：

- JS instance proxy 只保存 instance id，不保存 Dart 对象引用。
- Dart 侧按 runtime/class 维护 instance table。
- instance id 只在创建它的 `Quickjs` runtime 内有效。
- 不允许跨 runtime 混用 constructor、instance proxy 或 Dart handle。

## Disposal

`QuickjsClassHandle.dispose()` 会：

- 删除 JS 全局 constructor。
- 删除隐藏 callback globals。
- 从 runtime callback registry 注销相关 callback。
- 清理 Dart 侧 class instance table。
- 将已创建且仍被 JS 持有的 instance proxy 标记为 disposed。

dispose 后：

```js
typeof User // "undefined"
await leakedUser.name // throws "QuickJS class instance is disposed"
await leakedUser.greet() // throws "QuickJS class instance is disposed"
```

重复调用 `QuickjsClassHandle.dispose()` 是 no-op。所属 runtime 已 dispose 后再 dispose class handle 也是 no-op。

`Quickjs.dispose()` 会释放整个 runtime，并清空 class instance table。`Quickjs.stop()` 在需要重建底层 runtime 时也会清空 class instance table；之前绑定到旧 runtime 的 constructor / instance proxy 不再可用。

## JS GC and Dart GC

当前版本不承诺 JS GC 会触发 Dart instance 回收。JS 侧对象被回收时，Dart instance table 不会依赖 finalizer 立即清理。

稳定语义是：

- 通过 `QuickjsClassHandle.dispose()` 显式释放某个 class binding 的所有实例。
- 通过 `Quickjs.dispose()` 释放整个 runtime 的所有实例。
- future finalizer 只能作为兜底清理，不能替代显式 dispose。

这个约束避免把 Dart 对象生命周期绑定到 native QuickJS / web WASM 两端不同的 GC 暴露能力上。

## Current Limits

- 不支持自动 Dart 反射。
- 不支持继承、静态成员、symbol member 或 private field。
- 不支持 JS GC 驱动 Dart instance table 精确删除。
- setter assignment 的 async 错误不可 await。
- constructor 失败会在第一次 await getter/method 时表现为 Promise rejection。
