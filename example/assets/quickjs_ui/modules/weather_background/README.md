# quickjs_ui weather_background module

This directory is a self-contained JS module. It uses only public
`quickjs_ui` nodes and does not require a host plugin.

```js
import {
  WeatherBackground,
  createWeatherTheme
} from './modules/weather_background/index.mjs';

const theme = createWeatherTheme({
  assetBase: 'assets/my_page/modules/weather_background/assets'
});

WeatherBackground({
  weather: 'heavyRain',
  width: 360,
  height: 560,
  intensity: 0.8,
  fps: 30,
  paused: false,
  theme
});
```

Move the entire directory, preserve its internal layout, and update only
`assetBase`. Demo/page state is intentionally kept outside this module.
