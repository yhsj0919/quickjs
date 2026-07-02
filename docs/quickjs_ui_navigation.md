# quickjs_ui navigation

`QuickjsUiNavigator` supports native Flutter <-> JSUI navigation and JSUI
internal routing. JS pages send structured navigation intents through
`quickjsUiNavigation`.

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
`allowedRoutes` / `allowedPaths` are static allowlists. `onRequest` is called
for each JSUI route request that passes the static rules, so the host can log,
show UI, ask the user, or reject in real time.

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

## Transition Intent

Navigation intents may include a serializable `transition` object. Flutter maps
it to a native route transition when the navigation crosses a Flutter route
boundary.

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
