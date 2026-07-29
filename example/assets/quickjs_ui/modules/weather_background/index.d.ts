import type { JsonValue, QuickjsUiNode } from 'quickjs_ui';

export type WeatherType =
  | 'sunny'
  | 'cloudy'
  | 'overcast'
  | 'haze'
  | 'sandstorm'
  | 'lightRain'
  | 'moderateRain'
  | 'largeRain'
  | 'thunderstorm'
  | 'heavyRain'
  | 'lightSnow'
  | 'moderateSnow'
  | 'largeSnow'
  | 'heavySnow';

export type WeatherTheme = {
  assetBase: string;
  asset(path: string): string;
};

export type WeatherBackgroundProps = {
  key?: string;
  weather?: WeatherType;
  width?: number;
  height?: number;
  intensity?: number;
  paused?: boolean;
  playToken?: JsonValue;
  borderRadius?: number;
  theme?: WeatherTheme;
  child?: QuickjsUiNode;
};

export declare const WEATHER_TYPES: readonly WeatherType[];
export declare const defaultWeatherTheme: WeatherTheme;
export declare function createWeatherTheme(options?: {
  assetBase?: string;
}): WeatherTheme;
export declare function WeatherBackground(
  props?: WeatherBackgroundProps
): QuickjsUiNode;
