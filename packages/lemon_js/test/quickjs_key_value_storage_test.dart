import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test(
    'shared preferences store isolates namespaces and round-trips JSON',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final store = SharedPreferencesQuickjsKeyValueStore();

      await store.set('session', <String, Object?>{
        'token': 'one',
        'expires': 10,
        'scopes': <String>['read'],
      }, namespace: 'site.one');
      await store.set('session', null, namespace: 'site.two');

      expect(
        await store.get('session', namespace: 'site.one'),
        <String, Object?>{
          'token': 'one',
          'expires': 10,
          'scopes': <String>['read'],
        },
      );
      expect(await store.containsKey('session', namespace: 'site.two'), isTrue);
      expect(await store.get('session', namespace: 'site.two'), isNull);
      expect(await store.keys(namespace: 'site.one'), <String>['session']);

      await store.clear(namespace: 'site.one');
      expect(
        await store.containsKey('session', namespace: 'site.one'),
        isFalse,
      );
      expect(await store.containsKey('session', namespace: 'site.two'), isTrue);
    },
  );

  test('storage mount binds namespace without exposing it to JavaScript', () {
    final mount = QuickjsKeyValueStorageMount(
      store: InMemoryQuickjsKeyValueStore(),
      namespace: 'site.one',
    );

    expect(mount.modules.single.specifier, 'lemon_js/storage');
    expect(mount.modules.single.source, contains('containsKey(key)'));
    expect(mount.modules.single.source, contains('keys()'));
    expect(mount.modules.single.source, isNot(contains('site.one')));
  });
}
