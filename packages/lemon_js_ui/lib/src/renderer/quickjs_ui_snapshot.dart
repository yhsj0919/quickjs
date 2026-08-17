import 'dart:ui' as ui;

/// Page-scoped registry for captured Flutter subtree images.
///
/// JavaScript receives opaque ids while pixels remain owned by Flutter.
final class JsUiSnapshotRegistry {
  /// Creates a js ui snapshot registry.
  JsUiSnapshotRegistry({
    this.maxSnapshots = 32,
    this.maxSnapshotPixels = 16 * 1024 * 1024,
  }) : assert(maxSnapshots > 0),
       assert(maxSnapshotPixels > 0);

  /// The max snapshots value.
  final int maxSnapshots;

  /// The max snapshot pixels value.
  final int maxSnapshotPixels;
  final Map<String, JsUiSnapshot> _snapshots = <String, JsUiSnapshot>{};
  final Map<String, Object?> _captureTokens = <String, Object?>{};
  final Map<String, _JsUiCaptureClaim> _captureClaims =
      <String, _JsUiCaptureClaim>{};
  int _nextSnapshotId = 0;

  /// Returns the current length.
  int get length => _snapshots.length;

  /// Returns the current pixel count.
  int get pixelCount => _snapshots.values.fold<int>(
    0,
    (total, snapshot) => total + snapshot.image.width * snapshot.image.height,
  );

  /// The resolve value.
  JsUiSnapshot? resolve(String id) => _snapshots[id];

  /// Claims one capture for a boundary/token pair for the lifetime of this
  /// page registry. Rebuilding or remounting the widget cannot claim it again.
  bool claimCapture({
    required String boundaryId,
    required Object? token,
    required Object owner,
  }) {
    if (_captureTokens.containsKey(boundaryId) &&
        _snapshotTokenEquals(_captureTokens[boundaryId], token)) {
      return false;
    }
    final active = _captureClaims[boundaryId];
    if (active != null && _snapshotTokenEquals(active.token, token)) {
      return false;
    }
    _captureClaims[boundaryId] = _JsUiCaptureClaim(token, owner);
    return true;
  }

  /// Performs the complete capture operation.
  void completeCapture({
    required String boundaryId,
    required Object? token,
    required Object owner,
  }) {
    final active = _captureClaims[boundaryId];
    if (active == null || !identical(active.owner, owner)) return;
    _captureClaims.remove(boundaryId);
    _captureTokens[boundaryId] = token;
  }

  /// Performs the cancel capture operation.
  void cancelCapture({required String boundaryId, required Object owner}) {
    final active = _captureClaims[boundaryId];
    if (active != null && identical(active.owner, owner)) {
      _captureClaims.remove(boundaryId);
    }
  }

  /// Performs the register operation.
  JsUiSnapshot register({
    required String boundaryId,
    required ui.Image image,
    required double pixelRatio,
  }) {
    if (image.width * image.height > maxSnapshotPixels) {
      image.dispose();
      throw StateError('quickjs_ui snapshot exceeds $maxSnapshotPixels pixels');
    }
    final id = 'snapshot:$boundaryId:${++_nextSnapshotId}';
    while (_snapshots.length >= maxSnapshots) {
      _dispose(_snapshots.remove(_snapshots.keys.first));
    }
    final snapshot = JsUiSnapshot(id: id, image: image, pixelRatio: pixelRatio);
    _snapshots[id] = snapshot;
    return snapshot;
  }

  /// Performs the release operation.
  bool release(String id) {
    final snapshot = _snapshots.remove(id);
    _dispose(snapshot);
    return snapshot != null;
  }

  /// Performs the dispose operation.
  void dispose() {
    for (final snapshot in _snapshots.values) {
      snapshot.image.dispose();
    }
    _snapshots.clear();
    _captureTokens.clear();
    _captureClaims.clear();
  }

  void _dispose(JsUiSnapshot? snapshot) => snapshot?.image.dispose();
}

final class _JsUiCaptureClaim {
  const _JsUiCaptureClaim(this.token, this.owner);

  final Object? token;
  final Object owner;
}

bool _snapshotTokenEquals(Object? left, Object? right) {
  if (identical(left, right) || left == right) return true;
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (!_snapshotTokenEquals(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_snapshotTokenEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return false;
}

/// Public JSUI js ui snapshot API.
final class JsUiSnapshot {
  /// Creates a js ui snapshot.
  const JsUiSnapshot({
    required this.id,
    required this.image,
    required this.pixelRatio,
  });

  /// The id value.
  final String id;

  /// The image value.
  final ui.Image image;

  /// The pixel ratio value.
  final double pixelRatio;

  /// Returns the current width.
  double get width => image.width / pixelRatio;

  /// Returns the current height.
  double get height => image.height / pixelRatio;

  /// Performs the to payload operation.
  Map<String, Object?> toPayload() => <String, Object?>{
    'snapshotId': id,
    'width': width,
    'height': height,
    'pixelWidth': image.width,
    'pixelHeight': image.height,
    'pixelRatio': pixelRatio,
  };
}
