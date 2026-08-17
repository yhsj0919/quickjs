/// JavaScript 的 `undefined` 值。
final class JsUndefined {
  const JsUndefined._();

  /// 跨 Dart/JavaScript 边界表示 `undefined` 的唯一实例。
  static const JsUndefined value = JsUndefined._();

  @override
  String toString() => 'undefined';
}
