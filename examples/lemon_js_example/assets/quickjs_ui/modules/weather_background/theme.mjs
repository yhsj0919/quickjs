const DEFAULT_ASSET_BASE =
  'assets/quickjs_ui/modules/weather_background/assets';

export const defaultWeatherTheme = Object.freeze(
  createWeatherTheme({ assetBase: DEFAULT_ASSET_BASE })
);

export function createWeatherTheme(options = {}) {
  const assetBase = String(options.assetBase ?? DEFAULT_ASSET_BASE).replace(
    /[\\/]+$/,
    ''
  );
  return {
    assetBase,
    asset(path) {
      return `${assetBase}/${path}`;
    }
  };
}
