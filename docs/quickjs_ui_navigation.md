# quickjs_ui navigation

`QuickjsUiNavigator` supports native Flutter <-> JSUI navigation and JSUI
internal routing. JS pages send structured navigation intents through
`quickjsUiNavigation`.

## Route model

`quickjsUiNavigation` is an independent JSUI router API. It is injected per
JSUI route entry and is not an alias for `quickjsUiHost.navigationIntent`.

The router follows Flutter `Navigator.push` semantics:

- `push()` mutates the route stack immediately and resolves when that route is
  later popped with a result.
- `replace()` consumes the current route immediately and resolves to `true` for
  the replacing page. If the current route was opened by `push()`, that pending
  push result completes with `null`; it does not wait for the replacement page
  to pop.
- `pop(result)` completes the pending `push()` result for the previous page.
- `onRouteEnter`, `onRouteLeave`, and `onRouteResult` are lifecycle
  notifications. They are not the primary data return path.

Internal navigation uses a two-phase protocol. The host first validates and
locks the requested operation, then `quickjsUiNavigation` invokes
`onRouteLeave` and `onHide` inside the current JS dispatch before committing
the route mutation. This avoids a second call into the same QuickJS context
while preserving `await push()` result semantics. The entering page therefore
cannot receive `onRouteEnter` before the covered page has finished its departure
hooks.

Page visibility lifecycle follows the same two-phase ordering for internal
router transitions. A newly rendered page receives `onMount` and then `onShow`.
When a page is covered or removed by JSUI navigation it receives `onRouteLeave`
and then `onHide`; when a previous page becomes visible again it receives
`onRouteResult`, `onShow`, and then `onRouteEnter`.

Each `quickjsUiNavigation` object is bound to the page that received it. A page
can only navigate while it is the current JSUI route entry, and only one
navigation operation from that entry may be pending. Repeated calls from the
same callback after a push/replace, or calls from a page that is no longer
current, reject instead of growing the stack.

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

Rollback note: the previous experimental behavior treated `await
quickjsUiNavigation.push()` as "navigation accepted" and expected pages to read
the returned route result from `onRouteResult`. That behavior is intentionally
rolled back. `onRouteResult` remains as an observer-style lifecycle hook only.
The old `quickjsUiHost.navigationIntent` capability is also not part of JSUI
internal routing; use it only for app-defined host capabilities.

## Host controlled JSUI routing

JSUI pages may open another JSUI page with a relative path:

```js
await quickjsUiNavigation.push({
  route: 'quickjs-ui.navigation.child',
  path: './navigation_child_page.mjs',
  params: { itemId: 42 }
});
```

The host can restrict these JSUI-internal jumps with `jsRoutePolicy`.
`allowedRoutes` / `allowedPaths` are static allowlists. Paths are matched only
after resolution and normalization; relative request text is never trusted as
an allowlist identity. `onRequest` is called for each JSUI route request that
passes the static rules, so the host can log, show UI, ask the user, or reject
in real time.

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

The callback may show a Flutter dialog and remember a decision for later
requests:

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

When rejected, `quickjsUiNavigation.push()` / `replace()` rejects its Promise.
The JS page can catch the error and render an application-level message.

Prepared operations expire after 10 seconds by default. This bounds the source
route lock when an asynchronous `onRouteLeave` or `onHide` hook never settles.
Expiry removes the prepared token and unlocks the source route; a late commit
rejects instead of applying stale navigation. Hosts can change the limit on the
registry:

```dart
final registry = QuickjsUiRouteRegistry(
  options: const QuickjsUiNavigationOptions(
    preparedNavigationTimeout: Duration(seconds: 15),
    lifecycleTimeout: Duration(seconds: 3),
    maxJsRouteDepth: 32,
  ),
);
```

`lifecycleTimeout` bounds `onRouteLeave` and `onHide` as one departure phase.
After timeout the approved navigation continues; the hook Promise is no longer
allowed to hold the route lock indefinitely, and a state patch returned later
by that hook is discarded. The same deadline applies to Flutter/system back;
its departing page session is released as the pop proceeds. `maxJsRouteDepth`
bounds retained JSUI entries and their controllers. It applies only to
JSUI-internal `push`; `replace`, `pop`, and native Flutter routes do not consume
additional depth.

## Transition Intent

Navigation intents may include a serializable `transition` object. Flutter maps
it to a native route transition when the navigation crosses a Flutter route
boundary.

For JSUI-internal routes, the same transition object animates the top route
entry without recreating earlier entries. Previous pushed pages keep their
controller, state, and last rendered schema while they are hidden. On pop, the
removed page remains as a temporary overlay until its reverse transition
finishes, then its controller is disposed.

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

Supported transition types are `material`, `none`, `fade`, `slide`, and
`scale`.
