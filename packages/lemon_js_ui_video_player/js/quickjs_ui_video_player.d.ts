import type {
  BoxFit,
  ColorValue,
  JsUiEvent,
  JsUiNode,
  JsUiResourceReference
} from 'quickjs_ui';

declare module 'quickjs_ui/video_player' {
  export type VideoPlayerEvent = JsUiEvent;

  export type VideoPlayerProps = {
    key?: string;
    playerKey?: string;
    source: JsUiResourceReference;
    playing?: boolean;
    loop?: boolean;
    fit?: BoxFit;
    backgroundColor?: ColorValue;
    /** Whether to show a progress indicator while initializing. Defaults to true. */
    showLoading?: boolean;
    /** @deprecated Use showLoading. */
    showProgress?: boolean;
    /** Increment to recreate the native player for the current source. */
    restartToken?: number;
    /** Increment to apply seekPositionMs, including repeated seeks to one position. */
    seekToken?: number;
    seekPositionMs?: number;
    /** Progress event throttle in milliseconds. Defaults to 250. */
    progressThrottleMs?: number;
    progressCoalesceKey?: string;
    /** Playback speed multiplier. Defaults to 1. */
    playbackSpeed?: number;
    onReady?: VideoPlayerEvent;
    onProgress?: VideoPlayerEvent;
    onEnded?: VideoPlayerEvent;
    onError?: VideoPlayerEvent;
  };

  export function VideoPlayer(props: VideoPlayerProps): JsUiNode;
}
