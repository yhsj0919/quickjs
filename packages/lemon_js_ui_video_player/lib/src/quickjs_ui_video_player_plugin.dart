import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:video_player/video_player.dart' as native;

/// JavaScript 导入视频组件时使用的稳定 ES module 名称。
const String jsUiVideoPlayerModuleSpecifier = 'quickjs_ui/video_player';

/// `VideoPlayer` 组件对应的内置 ES module 源码。
///
/// JavaScript 通过 `import { VideoPlayer } from 'quickjs_ui/video_player'` 使用。
const String jsUiVideoPlayerModuleSource = '''
export function VideoPlayer(props = {}) {
  const key = props.key ?? props.playerKey ?? 'video-player';
  const progress = props.onProgress == null
    ? undefined
    : {
        ...props.onProgress,
        throttleMs: props.progressThrottleMs ?? 250,
        coalesceKey: props.progressCoalesceKey ?? `\${key}:progress`
      };
  return {
    type: 'VideoPlayer',
    key,
    source: props.source,
    playing: props.playing === true,
    loop: props.loop === true,
    fit: props.fit,
    backgroundColor: props.backgroundColor,
    showLoading: props.showLoading ?? props.showProgress ?? true,
    playbackSpeed: props.playbackSpeed ?? 1,
    restartToken: props.restartToken ?? 0,
    seekToken: props.seekToken ?? 0,
    seekPositionMs: props.seekPositionMs ?? 0,
    onReady: props.onReady,
    onProgress: progress,
    onEnded: props.onEnded,
    onError: props.onError
  };
}
''';

/// lemon_js_ui 视频播放器的官方插件入口。
///
/// [plugin] 同时包含 JavaScript 模块 features 和 Flutter `VideoPlayer`
/// 组件注册。传给 [JsUiView.uiPlugins] 即可，无需单独配置 features 或 registry。
final class JsUiVideoPlayerPlugin {
  const JsUiVideoPlayerPlugin._();

  static bool _desktopBackendRegistered = false;

  /// 注册 `quickjs_ui/video_player` 模块的内部 features。
  static const JsFeatures _features = JsFeatures(
    name: 'quickjs_ui:plugin:video_player',
    modules: <JsModule>[
      JsModule(
        name: jsUiVideoPlayerModuleSpecifier,
        source: jsUiVideoPlayerModuleSource,
      ),
    ],
  );

  /// 可直接传给 [JsUiView.uiPlugins] 的 UI 插件实例。
  static final JsUiPlugin plugin = JsUiPlugin(
    name: 'quickjs_ui:plugin:video_player',
    features: const <JsFeatures>[_features],
    configure: _configure,
  );

  static void _configure(JsUiComponentRegistry registry) {
    _ensureDesktopBackendRegistered();
    registry.register('VideoPlayer', _build);
  }

  /// Registers the desktop implementation used by `video_player`.
  ///
  /// Applications normally do not need to call this method. The plugin
  /// registers the backend automatically when its component registry is
  /// configured. Call it before creating a UI session only when custom FVP
  /// options are required.
  static void registerDesktopBackend({Map<String, Object>? options}) {
    if (_desktopBackendRegistered ||
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return;
    }
    fvp.registerWith(
      options:
          options ??
          const <String, Object>{
            'platforms': <String>['windows', 'macos', 'linux'],
            'video.decoders': <String>['BRAW:gpu', 'auto'],
          },
    );
    _desktopBackendRegistered = true;
  }

  static void _ensureDesktopBackendRegistered() {
    registerDesktopBackend();
  }

  static Widget _build(JsUiRenderContext context, JsUiNode node) {
    return _JsUiVideoPlayerHost(context: context, node: node);
  }
}

class _JsUiVideoPlayerHost extends StatefulWidget {
  const _JsUiVideoPlayerHost({required this.context, required this.node});

  final JsUiRenderContext context;
  final JsUiNode node;

  @override
  State<_JsUiVideoPlayerHost> createState() => _JsUiVideoPlayerHostState();
}

class _JsUiVideoPlayerHostState extends State<_JsUiVideoPlayerHost> {
  static const int _progressDispatchIntervalMs = 50;
  static const Duration _stalePauseRecoveryThreshold = Duration(seconds: 30);

  native.VideoPlayerController? _controller;
  bool _initialized = false;
  bool _endedDispatched = false;
  String? _activeSource;
  JsUiResourceKind? _activeResourceKind;
  int _restartToken = 0;
  int _seekToken = 0;
  int _lastProgressDispatchMs = -1;
  int _lastProgressDurationMs = -1;
  int _playbackSyncVersion = 0;
  int _seekRequestVersion = 0;
  bool _applyingPlaying = false;
  bool _pendingPlayingSync = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  @override
  void didUpdateWidget(covariant _JsUiVideoPlayerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final resource = _tryResourceFromNode(widget.node);
    if (resource == null) {
      return;
    }
    final source = resource.uri;
    if (source != _activeSource) {
      _disposeController();
      _initializeController();
      return;
    }

    _syncRestart();
    _syncSeek();
    _syncLoop();
    _syncPlaybackSpeed();
    _syncPlaying();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  Future<void> _initializeController() async {
    final resource = _tryResourceFromNode(widget.node);
    if (resource == null) {
      return;
    }
    final source = resource.uri;

    _activeSource = source;
    _activeResourceKind = resource.kind;
    _playbackSyncVersion += 1;
    _seekRequestVersion += 1;
    _endedDispatched = false;
    _lastProgressDispatchMs = -1;
    _lastProgressDurationMs = -1;
    _pausedAt = null;

    final controller = _controllerForResource(resource);
    _controller = controller;
    try {
      await controller.initialize();
    } catch (error) {
      if (mounted && identical(_controller, controller)) {
        _applyingPlaying = false;
        _dispatchError('$error');
      }
      return;
    }
    if (!mounted || !identical(_controller, controller)) {
      await controller.dispose();
      return;
    }

    await controller.setLooping(_loopFromNode(widget.node));
    await _applyPlaybackSpeed(controller, _playbackSpeedFromNode(widget.node));
    controller.addListener(_handleControllerUpdate);
    setState(() {
      _initialized = true;
    });

    _syncPlaying(force: true);
    final onReady = JsUiProps.event(widget.node.props['onReady']);
    if (onReady != null) {
      widget.context.dispatch(
        onReady,
        payload: <String, Object?>{
          'durationMs': controller.value.duration.inMilliseconds,
        },
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_controller, controller)) {
        _syncPlaying(force: true);
      }
    });
  }

  void _syncRestart() {
    final restartToken = widget.node.props['restartToken'];
    if (restartToken is! num || restartToken.toInt() == _restartToken) {
      return;
    }
    _restartToken = restartToken.toInt();
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    _endedDispatched = false;
    _lastProgressDispatchMs = 0;
    final version = ++_seekRequestVersion;
    unawaited(_seekTo(controller, Duration.zero, version));
  }

  void _syncSeek() {
    final seekToken = widget.node.props['seekToken'];
    if (seekToken is! num || seekToken.toInt() == _seekToken) {
      return;
    }
    _seekToken = seekToken.toInt();
    final seekPositionMs = widget.node.props['seekPositionMs'];
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        seekPositionMs is! num) {
      return;
    }
    final positionMs = seekPositionMs.toInt().clamp(0, 1 << 31);
    final version = ++_seekRequestVersion;
    unawaited(_seekTo(controller, Duration(milliseconds: positionMs), version));
  }

  void _syncLoop() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    unawaited(controller.setLooping(_loopFromNode(widget.node)));
  }

  void _syncPlaybackSpeed() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final speed = _playbackSpeedFromNode(widget.node);
    if ((controller.value.playbackSpeed - speed).abs() < 0.001) {
      return;
    }
    unawaited(_applyPlaybackSpeed(controller, speed));
  }

  Future<void> _applyPlaybackSpeed(
    native.VideoPlayerController controller,
    double speed,
  ) async {
    try {
      await controller.setPlaybackSpeed(speed);
    } catch (error) {
      if (mounted && identical(_controller, controller)) {
        _dispatchError('$error');
      }
    }
  }

  void _syncPlaying({bool force = false}) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final playing = widget.node.props['playing'] == true;
    if (_applyingPlaying) {
      _pendingPlayingSync = true;
      return;
    }
    if (!force && controller.value.isPlaying == playing) {
      return;
    }
    final version = ++_playbackSyncVersion;
    _applyingPlaying = true;
    unawaited(_applyPlaying(controller, playing, version));
  }

  Future<void> _applyPlaying(
    native.VideoPlayerController controller,
    bool playing,
    int syncVersion,
  ) async {
    if (playing && _shouldRecoverControllerBeforePlay(controller)) {
      await _recoverControllerForPlayback(controller, syncVersion);
      return;
    }
    try {
      if (playing) {
        await controller.play();
      } else {
        await controller.pause();
      }
    } catch (error) {
      if (mounted && identical(_controller, controller)) {
        _applyingPlaying = false;
        _dispatchError('$error');
      }
      return;
    }
    if (!mounted || !identical(_controller, controller)) {
      if (mounted) {
        _applyingPlaying = false;
      }
      return;
    }
    _applyingPlaying = false;
    _pausedAt = playing ? null : DateTime.now();
    _completePlayingSync(syncVersion);
  }

  bool _shouldRecoverControllerBeforePlay(
    native.VideoPlayerController controller,
  ) {
    final pausedAt = _pausedAt;
    if (pausedAt == null || controller.value.isPlaying) {
      return false;
    }
    return DateTime.now().difference(pausedAt) >= _stalePauseRecoveryThreshold;
  }

  Future<void> _recoverControllerForPlayback(
    native.VideoPlayerController oldController,
    int syncVersion,
  ) async {
    final source = _activeSource;
    final kind = _activeResourceKind;
    if (source == null || source.isEmpty) {
      _applyingPlaying = false;
      return;
    }

    final position = oldController.value.position;
    final loop = _loopFromNode(widget.node);
    oldController.removeListener(_handleControllerUpdate);
    _controller = null;
    _seekRequestVersion += 1;
    _endedDispatched = false;
    if (mounted) {
      setState(() {
        _initialized = false;
      });
    }
    await oldController.dispose();

    final controller = _controllerForSource(source, kind);
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || !identical(_controller, controller)) {
        await controller.dispose();
        if (mounted) {
          _applyingPlaying = false;
        }
        return;
      }
      await controller.setLooping(loop);
      await _applyPlaybackSpeed(
        controller,
        _playbackSpeedFromNode(widget.node),
      );
      if (position > Duration.zero) {
        await controller.seekTo(position);
      }
      controller.addListener(_handleControllerUpdate);
      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
      if (syncVersion == _playbackSyncVersion) {
        await controller.play();
      }
    } catch (error) {
      if (mounted && identical(_controller, controller)) {
        _applyingPlaying = false;
        _dispatchError('$error');
      }
      return;
    }
    if (!mounted || !identical(_controller, controller)) {
      if (mounted) {
        _applyingPlaying = false;
      }
      return;
    }
    _applyingPlaying = false;
    _pausedAt = null;
    _lastProgressDispatchMs = position.inMilliseconds;
    _lastProgressDurationMs = controller.value.duration.inMilliseconds;
    _completePlayingSync(syncVersion);
  }

  void _completePlayingSync(int syncVersion) {
    if (syncVersion != _playbackSyncVersion || _pendingPlayingSync) {
      _pendingPlayingSync = false;
      _syncPlaying(force: true);
      return;
    }
  }

  Future<void> _seekTo(
    native.VideoPlayerController controller,
    Duration position,
    int requestVersion,
  ) async {
    await controller.seekTo(position);
    if (!mounted ||
        !identical(_controller, controller) ||
        requestVersion != _seekRequestVersion) {
      return;
    }
    _lastProgressDispatchMs = position.inMilliseconds;
    _lastProgressDurationMs = controller.value.duration.inMilliseconds;
    _endedDispatched = false;
    _dispatchProgress(positionMs: position.inMilliseconds, force: true);
  }

  void _handleControllerUpdate() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final value = controller.value;
    final positionMs = value.position.inMilliseconds;
    final durationMs = value.duration.inMilliseconds;
    final schemaPlaying = widget.node.props['playing'] == true;
    final intervalReached =
        _lastProgressDispatchMs < 0 ||
        (positionMs - _lastProgressDispatchMs).abs() >=
            _progressDispatchIntervalMs;
    final durationChanged = durationMs != _lastProgressDurationMs;
    if (schemaPlaying
        ? intervalReached
        : _lastProgressDispatchMs < 0 || durationChanged) {
      _dispatchProgress(positionMs: positionMs);
    }

    if (durationMs > 0 &&
        value.position >= value.duration &&
        !_endedDispatched &&
        !_loopFromNode(widget.node)) {
      _endedDispatched = true;
      final onEnded = JsUiProps.event(widget.node.props['onEnded']);
      if (onEnded != null) {
        widget.context.dispatch(onEnded);
      }
    }
  }

  void _dispatchProgress({required int positionMs, bool force = false}) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final onProgress = JsUiProps.event(widget.node.props['onProgress']);
    if (onProgress == null) {
      return;
    }
    final durationMs = controller.value.duration.inMilliseconds;
    if (!force &&
        positionMs == _lastProgressDispatchMs &&
        durationMs == _lastProgressDurationMs) {
      return;
    }
    _lastProgressDispatchMs = positionMs;
    _lastProgressDurationMs = durationMs;
    widget.context.dispatch(
      onProgress,
      defaultCoalesceKey:
          'VideoPlayer:${widget.node.props['key'] ?? 'video-player'}:onProgress',
      kind: JsUiEventKind.sample,
      payload: <String, Object?>{
        'positionMs': positionMs,
        'durationMs': durationMs,
        'isPlaying': controller.value.isPlaying,
      },
    );
  }

  void _dispatchError(String message) {
    final onError = JsUiProps.event(widget.node.props['onError']);
    if (onError == null) {
      return;
    }
    widget.context.dispatch(
      onError,
      payload: <String, Object?>{'message': message},
    );
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    _initialized = false;
    _activeSource = null;
    _activeResourceKind = null;
    _applyingPlaying = false;
    _pendingPlayingSync = false;
    _pausedAt = null;
    _playbackSyncVersion += 1;
    _seekRequestVersion += 1;
    if (controller != null) {
      controller.removeListener(_handleControllerUpdate);
      unawaited(controller.dispose());
    }
  }

  JsUiResourceReference? _tryResourceFromNode(JsUiNode node) {
    try {
      return _resourceFromNode(node);
    } catch (error) {
      _dispatchError('$error');
      return null;
    }
  }

  JsUiResourceReference _resourceFromNode(JsUiNode node) {
    final rawSource = node.props['source'];
    if (rawSource == null) {
      throw const FormatException('quickjs_ui VideoPlayer.source is required');
    }
    final resource = JsUiResourceReference.parse(
      rawSource,
      name: 'VideoPlayer.source',
    );
    return switch (resource.kind) {
      JsUiResourceKind.network || JsUiResourceKind.file => resource,
      _ => throw FormatException(
        'quickjs_ui VideoPlayer source must be a network or file resource: '
        '${resource.kind.name}',
      ),
    };
  }

  native.VideoPlayerController _controllerForResource(
    JsUiResourceReference resource,
  ) {
    return _controllerForSource(resource.uri, resource.kind);
  }

  native.VideoPlayerController _controllerForSource(
    String source,
    JsUiResourceKind? kind,
  ) {
    if (kind == JsUiResourceKind.file) {
      final uri = Uri.tryParse(source);
      final path = uri != null && uri.scheme == 'file'
          ? uri.toFilePath()
          : source;
      return native.VideoPlayerController.file(File(path));
    }
    return native.VideoPlayerController.networkUrl(Uri.parse(source));
  }

  bool _loopFromNode(JsUiNode node) {
    return node.props['loop'] == true;
  }

  double _playbackSpeedFromNode(JsUiNode node) {
    final value = node.props['playbackSpeed'];
    if (value == null) {
      return 1;
    }
    if (value is! num || !value.isFinite || value <= 0) {
      throw const FormatException(
        'quickjs_ui VideoPlayer.playbackSpeed must be a positive number',
      );
    }
    return value.toDouble();
  }

  BoxFit _fitFromNode(JsUiNode node) {
    return JsUiProps.boxFit(node.props['fit']) ?? BoxFit.contain;
  }

  Color _backgroundColorFromNode(JsUiNode node) {
    return JsUiProps.color(
          node.props['backgroundColor'] ?? node.props['color'],
        ) ??
        const Color(0xFF111827);
  }

  bool _showLoadingFromNode(JsUiNode node) {
    final value = node.props['showLoading'] ?? node.props['showProgress'];
    if (value == null) {
      return true;
    }
    if (value is bool) {
      return value;
    }
    throw const FormatException(
      'quickjs_ui VideoPlayer.showLoading must be a bool',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final backgroundColor = _backgroundColorFromNode(widget.node);
    if (!_initialized ||
        controller == null ||
        !controller.value.isInitialized) {
      return _JsUiVideoPlayerSurface(
        backgroundColor: backgroundColor,
        child: _showLoadingFromNode(widget.node)
            ? const Center(child: CircularProgressIndicator())
            : const SizedBox.shrink(),
      );
    }
    return _JsUiVideoPlayerSurface(
      backgroundColor: backgroundColor,
      fit: _fitFromNode(widget.node),
      videoSize: controller.value.size,
      child: native.VideoPlayer(controller),
    );
  }
}

class _JsUiVideoPlayerSurface extends StatelessWidget {
  const _JsUiVideoPlayerSurface({
    required this.backgroundColor,
    required this.child,
    this.fit = BoxFit.contain,
    this.videoSize,
  });

  final Color backgroundColor;
  final Widget child;
  final BoxFit fit;
  final Size? videoSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded =
            constraints.hasBoundedWidth && constraints.hasBoundedHeight;
        final surface = ColoredBox(color: backgroundColor, child: child);
        if (!bounded) {
          return surface;
        }
        final size = videoSize;
        if (size == null || size.width <= 0 || size.height <= 0) {
          return SizedBox.expand(child: surface);
        }
        return ClipRect(
          child: ColoredBox(
            color: backgroundColor,
            child: SizedBox.expand(
              child: FittedBox(
                fit: fit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
