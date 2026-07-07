import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs_ui/quickjs_ui.dart';
import 'package:video_player/video_player.dart' as native;

const String quickjsUiVideoPlayerModuleSpecifier = 'quickjs_ui/video_player';

/// VideoPlayer 缁勪欢瀵瑰簲鐨勫唴鑱?ES module 婧愮爜銆?
///
/// JS 渚ч€氳繃 `import { VideoPlayer } from 'quickjs_ui/video_player'` 浣跨敤銆?
const String quickjsUiVideoPlayerModuleSource = '''
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

/// QuickJS UI 瑙嗛鎾斁鍣ㄧ殑瀹樻柟鎻掍欢鍏ュ彛銆?
///
/// 瀵瑰鍙毚闇?[plugin]锛氬悓鏃跺寘鍚?JS 妯″潡 mount 涓?Flutter `VideoPlayer` 娓叉煋娉ㄥ唽銆?
/// 鍦?[QuickjsUiView] 鐨?`uiPlugins` 涓紶鍏ュ嵆鍙紝鏃犻渶鍗曠嫭閰嶇疆 mount 鎴?registry銆?
final class QuickjsUiVideoPlayerPlugin {
  const QuickjsUiVideoPlayerPlugin._();

  /// 鍐呴儴 JS runtime mount锛屾敞鍐?`quickjs_ui/video_player` 妯″潡銆?
  static const QuickjsHostMount _mount = QuickjsHostMount(
    name: 'quickjs_ui:plugin:video_player',
    modules: <QuickjsHostModule>[
      QuickjsHostModule.esModule(
        specifier: quickjsUiVideoPlayerModuleSpecifier,
        source: quickjsUiVideoPlayerModuleSource,
      ),
    ],
  );

  /// 鍙洿鎺ヤ紶缁?[QuickjsUiView.uiPlugins] 鐨?UI 鎻掍欢瀹炰緥銆?
  static final QuickjsUiPlugin plugin = QuickjsUiPlugin(
    name: 'quickjs_ui:plugin:video_player',
    mounts: const <QuickjsHostMount>[_mount],
    configureRegistry: _configureRegistry,
  );

  static void _configureRegistry(QuickjsUiComponentRegistry registry) {
    registry.register('VideoPlayer', build);
  }

  /// 灏?schema 鑺傜偣 `type: 'VideoPlayer'` 鏋勫缓涓?Flutter Widget銆?
  ///
  /// - [context]锛氬綋鍓嶆覆鏌撲笂涓嬫枃锛岀敤浜庢淳鍙戜簨浠朵笌璇诲彇涓婚銆?
  /// - [node]锛氳В鏋愬悗鐨?UI schema 鑺傜偣銆?
  static Widget build(QuickjsUiRenderContext context, QuickjsUiNode node) {
    return _QuickjsUiVideoPlayerHost(context: context, node: node);
  }
}

class _QuickjsUiVideoPlayerHost extends StatefulWidget {
  const _QuickjsUiVideoPlayerHost({required this.context, required this.node});

  final QuickjsUiRenderContext context;
  final QuickjsUiNode node;

  @override
  State<_QuickjsUiVideoPlayerHost> createState() =>
      _QuickjsUiVideoPlayerHostState();
}

class _QuickjsUiVideoPlayerHostState extends State<_QuickjsUiVideoPlayerHost> {
  static const int _progressDispatchIntervalMs = 50;
  static const Duration _stalePauseRecoveryThreshold = Duration(seconds: 30);

  native.VideoPlayerController? _controller;
  bool _initialized = false;
  bool _endedDispatched = false;
  String? _activeSource;
  QuickjsUiResourceKind? _activeResourceKind;
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
  void didUpdateWidget(covariant _QuickjsUiVideoPlayerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final resource = _tryResourceFromNode(widget.node);
    if (resource == null) {
      return;
    }
    final source = resource.location;
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
    final source = resource.location;

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
    final onReady = QuickjsUiProps.event(widget.node.props['onReady']);
    if (onReady != null) {
      widget.context.dispatchEvent(
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
      await _applyPlaybackSpeed(controller, _playbackSpeedFromNode(widget.node));
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
      final onEnded = QuickjsUiProps.event(widget.node.props['onEnded']);
      if (onEnded != null) {
        widget.context.dispatchEvent(onEnded);
      }
    }
  }

  void _dispatchProgress({required int positionMs, bool force = false}) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final onProgress = QuickjsUiProps.event(widget.node.props['onProgress']);
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
    widget.context.dispatchEvent(
      onProgress,
      defaultCoalesceKey:
          'VideoPlayer:${widget.node.props['key'] ?? 'video-player'}:onProgress',
      kind: QuickjsUiEventKind.sample,
      payload: <String, Object?>{
        'positionMs': positionMs,
        'durationMs': durationMs,
        'isPlaying': controller.value.isPlaying,
      },
    );
  }

  void _dispatchError(String message) {
    final onError = QuickjsUiProps.event(widget.node.props['onError']);
    if (onError == null) {
      return;
    }
    widget.context.dispatchEvent(
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

  QuickjsUiResourceReference? _tryResourceFromNode(QuickjsUiNode node) {
    try {
      return _resourceFromNode(node);
    } catch (error) {
      _dispatchError('$error');
      return null;
    }
  }

  QuickjsUiResourceReference _resourceFromNode(QuickjsUiNode node) {
    final rawSource = node.props['source'];
    if (rawSource == null) {
      throw const FormatException('quickjs_ui VideoPlayer.source is required');
    }
    final resource = QuickjsUiResourceReference.parse(
      rawSource,
      name: 'VideoPlayer.source',
    );
    return switch (resource.kind) {
      QuickjsUiResourceKind.network || QuickjsUiResourceKind.file => resource,
      _ => throw FormatException(
        'quickjs_ui VideoPlayer source must be a network or file resource: '
        '${resource.kind.name}',
      ),
    };
  }

  native.VideoPlayerController _controllerForResource(
    QuickjsUiResourceReference resource,
  ) {
    return _controllerForSource(resource.location, resource.kind);
  }

  native.VideoPlayerController _controllerForSource(
    String source,
    QuickjsUiResourceKind? kind,
  ) {
    if (kind == QuickjsUiResourceKind.file) {
      final uri = Uri.tryParse(source);
      final path = uri != null && uri.scheme == 'file'
          ? uri.toFilePath()
          : source;
      return native.VideoPlayerController.file(File(path));
    }
    return native.VideoPlayerController.networkUrl(Uri.parse(source));
  }

  bool _loopFromNode(QuickjsUiNode node) {
    return node.props['loop'] == true;
  }

  double _playbackSpeedFromNode(QuickjsUiNode node) {
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

  BoxFit _fitFromNode(QuickjsUiNode node) {
    return QuickjsUiProps.boxFit(node.props['fit']) ?? BoxFit.contain;
  }

  Color _backgroundColorFromNode(QuickjsUiNode node) {
    return QuickjsUiProps.color(
          node.props['backgroundColor'] ?? node.props['color'],
        ) ??
        const Color(0xFF111827);
  }

  bool _showLoadingFromNode(QuickjsUiNode node) {
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
      return _QuickjsUiVideoPlayerSurface(
        backgroundColor: backgroundColor,
        child: _showLoadingFromNode(widget.node)
            ? const Center(child: CircularProgressIndicator())
            : const SizedBox.shrink(),
      );
    }
    return _QuickjsUiVideoPlayerSurface(
      backgroundColor: backgroundColor,
      fit: _fitFromNode(widget.node),
      videoSize: controller.value.size,
      child: native.VideoPlayer(controller),
    );
  }
}

class _QuickjsUiVideoPlayerSurface extends StatelessWidget {
  const _QuickjsUiVideoPlayerSurface({
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
