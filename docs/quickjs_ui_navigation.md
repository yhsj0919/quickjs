# quickjs_ui 导航

`QuickjsUiNavigator` 支持 Flutter 原生页面与 JSUI 之间的导航，以及 JSUI 内部路由。
JS 页面通过 `quickjsUiNavigation` 发送结构化导航意图。

## 路由模型

`quickjsUiNavigation` 是独立的 JSUI Router API，按 JSUI 路由入口注入，并非
`quickjsUiHost.navigationIntent` 的别名。

Router 遵循 Flutter `Navigator.push` 语义：

- `push()` 立即修改路由栈，并在该路由之后携带结果弹出时完成。
- `replace()` 立即消费当前路由，并向替换页面返回 `true`。若当前路由由 `push()` 打开，
  待处理结果以 `null` 完成，不等待替换页面弹出。
- `pop(result)` 完成前一页面待处理的 `push()` 结果。
- `onRouteEnter`、`onRouteLeave` 和 `onRouteResult` 是生命周期通知，不是主要数据返回通道。

内部导航使用两阶段协议：宿主先校验并锁定操作；`quickjsUiNavigation` 再在当前 JS
dispatch 内调用 `onRouteLeave` 和 `onHide`，随后提交路由变化。这样既避免二次进入同一
QuickJS Context，又保留 `await push()` 的结果语义。被覆盖页面完成离开钩子前，新页面
不会收到 `onRouteEnter`。

页面可见性生命周期遵循相同顺序：新页面依次收到 `onMount`、`onShow`；页面被覆盖或
移除时依次收到 `onRouteLeave`、`onHide`；旧页面重新可见时依次收到
`onRouteResult`、`onShow`、`onRouteEnter`。

每个 `quickjsUiNavigation` 对象绑定到接收它的页面。页面只有在当前 JSUI 路由入口时
才能导航，且同一入口最多存在一个待处理导航。push/replace 后在同一回调内重复调用，
或非当前页面发起调用，都会被拒绝而不是继续增长路由栈。

```js
async openChild(state, _payload, props) {
  const result = await quickjsUiNavigation.push({
    route: 'quickjs-ui.navigation.child',
    path: './navigation_child_page.mjs',
    params: { itemId: props.itemId }
  });
  return { ...state, result };
}
```

回滚说明：旧实验行为把 `await quickjsUiNavigation.push()` 视为“导航已接受”，并要求页面
从 `onRouteResult` 读取结果；该行为已回滚。`onRouteResult` 只保留为观察式生命周期钩子。
旧的 `quickjsUiHost.navigationIntent` 也不属于 JSUI 内部路由，仅用于应用自定义宿主能力。

## 宿主控制的 JSUI 路由

JSUI 页面可以通过相对路径打开另一个 JSUI 页面：

```js
await quickjsUiNavigation.push({
  route: 'quickjs-ui.navigation.child',
  path: './navigation_child_page.mjs',
  params: { itemId: 42 }
});
```

宿主可以使用 `jsRoutePolicy` 限制 JSUI 内部跳转。`allowedRoutes` / `allowedPaths`
是静态白名单。路径仅在解析和规范化后匹配，绝不把相对请求文本直接作为白名单身份。
每个通过静态规则的 JSUI 路由请求都会调用 `onRequest`，宿主可实时记录、显示 UI、
询问用户或拒绝请求。

```dart
final registry = QuickjsUiRouteRegistry(
  jsRoutePolicy: QuickjsUiJsRoutePolicy(
    allowedPaths: const <String>{
      'assets/quickjs_ui/navigation_child_page.mjs',
    },
    onRequest: (request) async {
      debugPrint(
        'JSUI route ${request.action}: '
        '${request.resolvedPath} from ${request.from}',
      );
      return true; // return false to reject
    },
  ),
);
```

回调可以显示 Flutter 对话框，并为后续请求记住决定：

```dart
final trustedPaths = <String>{};

final registry = QuickjsUiRouteRegistry(
  jsRoutePolicy: QuickjsUiJsRoutePolicy(
    allowedPaths: const <String>{
      'assets/quickjs_ui/navigation_child_page.mjs',
    },
    onRequest: (request) async {
      if (trustedPaths.contains(request.resolvedPath)) {
        return true;
      }
      final decision = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Allow JSUI navigation?'),
          content: Text('${request.from} -> ${request.resolvedPath}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'deny'),
              child: const Text('Deny'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'once'),
              child: const Text('Allow once'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'always'),
              child: const Text('Always allow this page'),
            ),
          ],
        ),
      );
      if (decision == 'always') {
        trustedPaths.add(request.resolvedPath);
      }
      return decision == 'once' || decision == 'always';
    },
  ),
);
```

请求被拒绝时，`quickjsUiNavigation.push()` / `replace()` 的 Promise 会 reject；
JS 页面可以捕获错误并显示应用级提示。

预备操作默认在 10 秒后过期，避免异步 `onRouteLeave` 或 `onHide` 永不完成时持续锁定
源路由。过期会删除预备 token 并解锁源路由；迟到的 commit 会被拒绝，而不是应用过时
导航。宿主可以在注册表中修改限制：

```dart
final registry = QuickjsUiRouteRegistry(
  options: const QuickjsUiNavigationOptions(
    preparedNavigationTimeout: Duration(seconds: 15),
    lifecycleTimeout: Duration(seconds: 3),
    maxJsRouteDepth: 32,
  ),
);
```

`lifecycleTimeout` 把 `onRouteLeave` 和 `onHide` 作为一个离开阶段限制。超时后，已批准
的导航继续执行；钩子 Promise 不再无限占用路由锁，迟到的状态 patch 会被丢弃。相同
期限也适用于 Flutter/系统返回，页面 Session 会随 pop 释放。`maxJsRouteDepth` 限制
保留的 JSUI 入口及其 Controller 数量，仅作用于 JSUI 内部 `push`；`replace`、`pop`
和 Flutter 原生路由不增加该深度。

## 过渡意图

导航意图可以包含可序列化的 `transition` 对象。跨越 Flutter 路由边界时，Flutter 会将其
映射为原生路由过渡。

对于 JSUI 内部路由，同一 transition 对象只为栈顶入口执行动画，不重建更早入口。之前
push 的页面在隐藏期间保留 Controller、state 和最后一次渲染的 Schema。pop 时，被移除
页面作为临时浮层保留到反向过渡结束，随后释放其 Controller。

```js
await quickjsUiNavigation.push({
  route: 'settings',
  transition: {
    type: 'slide',
    from: 'right',
    durationMs: 220,
    curve: 'easeOutCubic'
  }
});
```

支持的过渡类型包括 `material`、`none`、`fade`、`slide` 和 `scale`。
