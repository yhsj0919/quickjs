import type { BoxFit, JsonValue, QuickjsUiEvent, QuickjsUiNode } from 'quickjs_ui';

declare module 'quickjs_ui/video_player' {
  export type VideoPlayerEvent = QuickjsUiEvent;

  export type VideoPlayerProps = {
    key?: string;
    playerKey?: string;
    source: string;
    playing?: boolean;
    loop?: boolean;
    fit?: BoxFit;
    backgroundColor?: string | number;
    restartToken?: number;
    seekToken?: number;
    seekPositionMs?: number;
    /** Progress event throttle in milliseconds. Defaults to 250. */
    progressThrottleMs?: number;
    progressCoalesceKey?: string;
    onReady?: VideoPlayerEvent;
    onProgress?: VideoPlayerEvent;
    onEnded?: VideoPlayerEvent;
    onError?: VideoPlayerEvent;
    [key: string]: JsonValue | VideoPlayerEvent | undefined;
  };

  export function VideoPlayer(props: VideoPlayerProps): QuickjsUiNode;
}
