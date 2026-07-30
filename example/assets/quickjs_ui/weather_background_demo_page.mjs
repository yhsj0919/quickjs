import {
    AutoRefresh,
    Canvas,
    Center,
    Column,
    Container,
    DateTimeText,
    Flexible,
    Page,
    Padding,
    Positioned,
    ResponsiveViewport,
    Row,
    SizedBox,
    Stack,
    Svg,
    Text,
    TextButton,
} from 'quickjs_ui';
import {
    WeatherBackground,
    WEATHER_TYPES,
    createWeatherTheme,
} from './modules/weather_background/index.mjs';

const WHITE = '#FFFFFFFF';
const WHITE_70 = '#B3FFFFFF';
const WHITE_85 = '#D9FFFFFF';
const GLASS = '#33FFFFFF';
const GLASS_STRONG = '#40FFFFFF';
const BORDER = '#55FFFFFF';
const TOP_TEXT_SHADOWS = [
    {color: '#66000000', offset: {x: 0, y: 1.5}, blurRadius: 3},
];

const DEFAULT_API_URL = 'https://ad.palsmon.com/api/app/weather/city';
const DEFAULT_REFRESH_MS = 10 * 60 * 1000;
const DEFAULT_RESOURCE_BASE_URL = 'assets/quickjs_ui';
const BACKGROUND_OPTIONS = Object.freeze([null, ...WEATHER_TYPES]);
const BACKGROUND_LABELS = Object.freeze({
    sunny: '晴天',
    cloudy: '多云',
    overcast: '阴天',
    lightRain: '小雨',
    moderateRain: '中雨',
    largeRain: '大雨',
    thunderstorm: '雷雨',
    heavyRain: '暴雨',
    lightSnow: '小雪',
    moderateSnow: '中雪',
    largeSnow: '大雪',
    heavySnow: '暴雪',
    haze: '霾',
    sandstorm: '沙尘',
});

// Packed lunar years 2000–2099. The high four bits store the leap month
// position (15 means no leap month); the low thirteen bits store month lengths.
const LUNAR_YEAR_DATA = [
    0x1E693, 0x0952B, 0x1E52B, 0x1EA5B, 0x0555A, 0x1E56A, 0x0FB55, 0x1EBA4, 0x1EB49, 0x0BA93,
    0x1EA95, 0x1E52D, 0x08AAD, 0x1EAB5, 0x135AA, 0x1E5D2, 0x1EDA5, 0x0DD4A, 0x1ED4A, 0x1EC95,
    0x0952E, 0x1E556, 0x1EAB5, 0x055B2, 0x1E6D2, 0x0CEA5, 0x1E725, 0x1E64B, 0x0AC97, 0x1ECAB,
    0x1E55A, 0x06AD6, 0x1EB69, 0x17752, 0x1EB52, 0x1EB25, 0x0DA4B, 0x1EA4B, 0x1E4AB, 0x0A55B,
    0x1E5AD, 0x1EB6A, 0x05B52, 0x1ED92, 0x0FD25, 0x1ED25, 0x1EA55, 0x0B4AD, 0x1E4B6, 0x1E5B5,
    0x06DAA, 0x1EEC9, 0x11E92, 0x1EE92, 0x1ED26, 0x0CA56, 0x1EA57, 0x1E4D6, 0x086D5, 0x1E755,
    0x1E749, 0x06E93, 0x1E693, 0x0F52B, 0x1E52B, 0x1EA5B, 0x0B55A, 0x1E56A, 0x1EB65, 0x0974A,
    0x1EB4A, 0x11A95, 0x1EA95, 0x1E52D, 0x0CAAD, 0x1EAB5, 0x1E5AA, 0x08BA5, 0x1EDA5, 0x1ED4A,
    0x07C95, 0x1EC96, 0x0F94E, 0x1E556, 0x1EAB5, 0x0B5B2, 0x1E6D2, 0x1EEA5, 0x08E4A, 0x1E64B,
    0x10C97, 0x1E4AB, 0x1E55B, 0x0CAD6, 0x1EB6A, 0x1E752, 0x09725, 0x1EB25, 0x1EA8B, 0x0549B,
];

const QWEATHER_TO_METEOCONS = {
    100: 'clear-day',
    150: 'clear-night',
    101: 'partly-cloudy-day',
    102: 'partly-cloudy-day',
    103: 'partly-cloudy-day',
    104: 'overcast',
    151: 'partly-cloudy-night',
    152: 'partly-cloudy-night',
    153: 'partly-cloudy-night',
    300: 'partly-cloudy-day-rain',
    301: 'partly-cloudy-day-rain',
    350: 'partly-cloudy-night-rain',
    351: 'partly-cloudy-night-rain',
    302: 'thunderstorms-day-rain',
    303: 'thunderstorms',
    304: 'hail',
    305: 'drizzle',
    306: 'rain',
    307: 'rain',
    308: 'extreme-rain',
    309: 'drizzle',
    310: 'extreme-rain',
    311: 'extreme-rain',
    312: 'extreme-rain',
    313: 'sleet',
    314: 'drizzle',
    315: 'rain',
    316: 'rain',
    317: 'extreme-rain',
    318: 'extreme-rain',
    399: 'rain',
    400: 'snow',
    401: 'snow',
    402: 'snow',
    403: 'extreme-snow',
    404: 'sleet',
    405: 'sleet',
    406: 'partly-cloudy-day-sleet',
    407: 'partly-cloudy-day-snow',
    408: 'snow',
    409: 'snow',
    410: 'extreme-snow',
    456: 'partly-cloudy-night-sleet',
    457: 'partly-cloudy-night-snow',
    499: 'snow',
    500: 'mist',
    501: 'fog',
    502: 'haze',
    503: 'wind-dust',
    504: 'dust',
    507: 'wind-dust',
    508: 'wind-dust',
    509: 'fog',
    510: 'fog',
    511: 'haze',
    512: 'haze',
    513: 'haze',
    514: 'fog',
    515: 'fog',
    900: 'thermometer-warmer',
    901: 'thermometer-colder',
    999: 'not-available',
};

let refreshTimer = 0;

const EMPTY_CITY = {
    name: '加载中...',
    condition: '',
    iconSource: null,
    temp: '--',
    high: '--',
    low: '--',
    air: '-',
    aqi: '-',
    alert: '-',
    bodyTemp: '--',
    humidity: '--',
    uv: '-',
    hourly: [],
    daily: [],
};

export default Page({
    name: 'quickjs-ui-weather-demo',

    createState(props) {
        return {
            refreshCount: 0,
            backgroundIndex: 0,
            date: formatSystemDate(),
            loading: true,
            error: '',
            axiosStatus: '正在检测 Axios...',
            city: null,
            apiUrl: props.apiUrl ?? DEFAULT_API_URL,
            resourceBaseUrl: normalizeResourceBaseUrl(props.resourceBaseUrl),
            viewportWidth: Number(props.width) || 360,
            viewportHeight: Number(props.height) || 640,
        };
    },

    async onMount(state, _payload, props, _event, ctx) {
        if (ctx?.actions?.refresh) {
            refreshTimer = setInterval(
                () => ctx.actions.refresh(),
                props.refreshMs ?? DEFAULT_REFRESH_MS,
            );
        }
        return loadWeather(state, props);
    },

    onDispose() {
        if (refreshTimer) {
            clearInterval(refreshTimer);
            refreshTimer = 0;
        }
    },

    build(state, _props, actions) {
        const city = state.city ?? EMPTY_CITY;
        return Stack({
            fit: 'expand',
            children: [
                weatherBackground(city, state),
                Padding({
                    padding: {left: 50, top: 50, right: 50, bottom: 150},
                    child: Column({
                        children: [
                            Flexible({flex: 1, child: Container({})}),
                            errorBanner(state.error),
                            header(city, state),
                            Flexible({flex: 1, child: Container({})}),
                            hourlyCard(city.hourly),
                            dailyCard(city.daily),
                            metricsCard(city, state.resourceBaseUrl),
                        ].filter(Boolean),
                    })
                }),
                backgroundSwitcher(state, actions),
            ],
        });
    },

    cycleBackground(state) {
        return {
            backgroundIndex: (state.backgroundIndex + 1) % BACKGROUND_OPTIONS.length,
        };
    },

    async refresh(state, _payload, props) {
        const next = await loadWeather(state, props);
        return {...next, refreshCount: state.refreshCount + 1};
    },

});

async function loadWeather(state, props = {}) {
    const resourceBaseUrl = normalizeResourceBaseUrl(
        props.resourceBaseUrl ?? state.resourceBaseUrl,
    );
    try {
        const apiUrl = props.apiUrl ?? state.apiUrl ?? DEFAULT_API_URL;
        const data = await requestJson(apiUrl);
        return {
            loading: false,
            error: '',
            axiosStatus: axiosStatusText(),
            city: mapWeatherPayload(data, `${resourceBaseUrl}/weatherIcon`),
            apiUrl,
            resourceBaseUrl,
            date: formatSystemDate(),
        };
    } catch (error) {
        return {
            loading: false,
            error: describeError(error),
            axiosStatus: axiosStatusText(),
            city: state.city ?? null,
            resourceBaseUrl,
            date: formatSystemDate(),
        };
    }
}

async function requestJson(url) {
    if (typeof axios === 'function') {
        const response = await axios.get(url);
        console.log('weather api response', JSON.stringify(response.data));
        return response.data;
    }
    if (typeof fetch === 'function') {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        const data = await response.json();
        console.log('weather api response', JSON.stringify(data));
        return data;
    }
    throw new Error('Axios/Fetch 未注入');
}

function axiosStatusText() {
    if (typeof axios === 'function') {
        return `Axios ${axios.VERSION ?? '已注入'} · Fetch/XHR 已启用`;
    }
    return 'Axios 未注入';
}

function mapWeatherPayload(data, weatherIconBaseUrl) {
    const payload = data?.data ?? data;
    const item = payload?.list?.[0];
    if (!item) {
        throw new Error(`天气接口未返回 list 数据，实际 keys: ${Object.keys(payload ?? {}).join(',') || 'empty'}`);
    }

    const now = item.now ?? {};
    const location = payload.location ?? {};
    const air = item.current_airquality?.[0];
    const alert = item.current_weatheralert?.alerts?.[0];
    const uv = item.indices?.find((entry) => entry.name === '紫外线指数');
    const today = item.days?.[0] ?? {};

    return {
        name: location.city_name ?? `${item.city ?? '未知'}市`,
        condition: now.text ?? '',
        iconSource: weatherIconSource(now.icon, weatherIconBaseUrl),
        weatherCode: now.icon,
        temp: toNumber(now.temp),
        high: toNumber(today.tempMax),
        low: toNumber(today.tempMin),
        air: air?.category ?? '-',
        aqi: air?.aqi ?? '-',
        alert: alert?.eventType?.name ?? '无',
        bodyTemp: toNumber(now.feelsLike),
        humidity: toNumber(now.humidity),
        uv: uv?.category ?? '-',
        hourly: mapHourly(item.hours ?? [], weatherIconBaseUrl),
        daily: mapDaily(item.days ?? [], item.daily_airquality ?? [], weatherIconBaseUrl),
    };
}

function mapHourly(hours, weatherIconBaseUrl) {
    const now = Date.now();
    const upcoming = hours.filter((hour) => {
        const time = Date.parse(hour.fxTime ?? '');
        return Number.isFinite(time) && time >= now - 60 * 60 * 1000;
    });

    return upcoming.slice(0, 7).map((hour) => ({
        time: formatHourTime(hour.fxTime),
        iconSource: weatherIconSource(hour.icon, weatherIconBaseUrl),
        temp: toNumber(hour.temp),
    }));
}

function mapDaily(days, dailyAir, weatherIconBaseUrl) {
    return days.slice(0, 7).map((day, index) => {
        const airEntry = dailyAir[index]?.indexes?.[0];
        return {
            day: dayLabel(index, day.fxDate),
            date: formatShortDate(day.fxDate),
            iconSource: weatherIconSource(day.iconDay, weatherIconBaseUrl),
            text: day.textDay ?? '',
            high: toNumber(day.tempMax),
            low: toNumber(day.tempMin),
            air: airEntry?.category ?? '-',
        };
    });
}


function weatherBackground(city, state) {
    const theme = createWeatherTheme({
        assetBase: `${state.resourceBaseUrl}/modules/weather_background/assets`,
    });
    return WeatherBackground({
        weather: BACKGROUND_OPTIONS[state.backgroundIndex]
            ?? weatherTypeForCode(city.weatherCode),
        width: Number(state.viewportWidth) || 360,
        height: Number(state.viewportHeight) || 640,
        responsive: true,
        borderRadius: 0,
        fps: 30,
        theme,
    });
}

function backgroundSwitcher(state, actions) {
    const weather = BACKGROUND_OPTIONS[state.backgroundIndex];
    const label = weather == null ? '自动' : BACKGROUND_LABELS[weather];
    return Positioned({
        top: 16,
        right: 16,
        child: Container({
            decoration: {
                color: '#40FFFFFF',
                borderRadius: 18,
                border: {color: '#55FFFFFF', width: 1},
            },
            child: TextButton({
                label: `背景：${label}`,
                onPressed: actions.cycleBackground(),
                style: {
                    foregroundColor: WHITE,
                    padding: {horizontal: 14, vertical: 8},
                    textStyle: {fontSize: 13, fontWeight: 'w700'},
                },
            }),
        }),
    });
}

function weatherTypeForCode(value) {
    const code = Number(value);
    if ([101, 102, 103, 151, 152, 153].includes(code)) return 'cloudy';
    if ([104, 154, 500, 501, 509, 510, 514, 515].includes(code)) return 'overcast';
    if ([302, 303, 304].includes(code)) return 'thunderstorm';
    if ([300, 305, 309, 313, 314, 350, 399].includes(code)) return 'lightRain';
    if ([301, 306, 315, 351].includes(code)) return 'moderateRain';
    if ([307, 308, 316, 317].includes(code)) return 'largeRain';
    if ([310, 311, 312, 318].includes(code)) return 'heavyRain';
    if ([400, 407, 457, 499].includes(code)) return 'lightSnow';
    if ([401, 404, 405, 406, 408, 409, 456].includes(code)) return 'moderateSnow';
    if (code === 402) return 'largeSnow';
    if ([403, 410].includes(code)) return 'heavySnow';
    if ([502, 511, 512, 513].includes(code)) return 'haze';
    if ([503, 504, 507, 508].includes(code)) return 'sandstorm';
    return 'sunny';
}

function weatherIconSource(iconCode, weatherIconBaseUrl) {
    if (iconCode == null || iconCode === '') {
        return null;
    }
    const name = QWEATHER_TO_METEOCONS[Number(iconCode)] ?? 'not-available';
    return `${weatherIconBaseUrl}/${name}.svg`;
}

function normalizeResourceBaseUrl(value) {
    return String(value ?? DEFAULT_RESOURCE_BASE_URL).replace(/[\\/]+$/, '');
}

function weatherIconView(source, size = 36) {
    if (!source) {
        return SizedBox({width: size, height: size});
    }
    return Svg({
        src: source,
        width: size,
        height: size,
        fit: 'contain',
        semanticLabel: 'weather icon',
    });
}

function formatSystemDate(date = new Date()) {
    const week = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][date.getDay()];
    const lunar = formatLunarDate(date);
    return `${date.getMonth() + 1}月${date.getDate()}日 ${week}${lunar ? ` ${lunar}` : ''}`;
}

function formatLunarDate(date) {
    const dayMs = 24 * 60 * 60 * 1000;
    let remaining = Math.floor((Date.UTC(
        date.getFullYear(),
        date.getMonth(),
        date.getDate(),
    ) - Date.UTC(2000, 1, 5)) / dayMs);
    if (remaining < 0) return '';

    let yearIndex = 0;
    while (yearIndex < LUNAR_YEAR_DATA.length) {
        const yearDays = lunarYearDays(LUNAR_YEAR_DATA[yearIndex]);
        if (remaining < yearDays) break;
        remaining -= yearDays;
        yearIndex += 1;
    }
    if (yearIndex >= LUNAR_YEAR_DATA.length) return '';

    const packed = LUNAR_YEAR_DATA[yearIndex];
    const leapAfter = packed >> 13;
    const monthCount = leapAfter === 15 ? 12 : 13;
    let sequenceMonth = 1;
    while (sequenceMonth <= monthCount) {
        const monthDays = 29 + ((packed >> (sequenceMonth - 1)) & 1);
        if (remaining < monthDays) break;
        remaining -= monthDays;
        sequenceMonth += 1;
    }

    const isLeap = leapAfter !== 15 && sequenceMonth === leapAfter + 1;
    const lunarMonth = isLeap
        ? leapAfter
        : sequenceMonth - (leapAfter !== 15 && sequenceMonth > leapAfter + 1 ? 1 : 0);
    const monthNames = ['正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊'];
    return `${isLeap ? '闰' : ''}${monthNames[lunarMonth - 1]}月${lunarDayName(remaining + 1)}`;
}

function lunarYearDays(packed) {
    const monthCount = packed >> 13 === 15 ? 12 : 13;
    let days = monthCount * 29;
    for (let index = 0; index < monthCount; index += 1) {
        days += (packed >> index) & 1;
    }
    return days;
}

function lunarDayName(day) {
    if (day === 10) return '初十';
    if (day === 20) return '二十';
    if (day === 30) return '三十';
    const prefixes = ['初', '十', '廿'];
    const digits = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];
    return `${prefixes[Math.floor((day - 1) / 10)]}${digits[(day - 1) % 10]}`;
}

function formatHourTime(fxTime) {
    const match = `${fxTime ?? ''}`.match(/T(\d{2}:\d{2})/);
    return match?.[1] ?? '--:--';
}

function parseDate(dateStr) {
    if (!dateStr) {
        return null;
    }
    const date = new Date(`${dateStr}T12:00:00`);
    return Number.isNaN(date.getTime()) ? null : date;
}

function formatShortDate(dateStr) {
    const date = parseDate(dateStr);
    if (!date) {
        return '--/--';
    }
    return `${String(date.getMonth() + 1).padStart(2, '0')}/${String(date.getDate()).padStart(2, '0')}`;
}

function dayLabel(index, fxDate) {
    if (index === 0) return '今天';
    if (index === 1) return '明天';
    if (index === 2) return '后天';
    const date = parseDate(fxDate);
    const week = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return date ? week[date.getDay()] : `第${index + 1}天`;
}

function toNumber(value) {
    const number = Number(value);
    return Number.isFinite(number) ? number : value ?? '-';
}

function describeError(error) {
    if (error == null) return '未知错误';
    if (typeof axios !== 'undefined' && axios.isAxiosError?.(error)) {
        const status = error.response?.status;
        const message = error.response?.data?.msg ?? error.message ?? 'Axios 请求失败';
        return status == null ? message : `HTTP ${status}: ${message}`;
    }
    if (typeof error === 'string') return error;
    if (error && typeof error.message === 'string') return error.message;
    return String(error);
}

function errorBanner(message) {
    if (!message) {
        return null;
    }
    return Container({
        margin: {bottom: 12},
        padding: {all: 12},
        decoration: {
            color: '#66FF5252',
            borderRadius: 12,
            border: {color: '#FFFF5252', width: 1},
        },
        child: Text(message, {
            style: {color: WHITE, fontSize: 13, fontWeight: 'w600'},
        }),
    });
}

function header(city, state) {
    return Column({
        crossAxisAlignment: 'center',
        children: [
            Text(city.name, {
                textAlign: 'center',
                style: {color: WHITE, fontSize: 28, fontWeight: 'w700', shadows: TOP_TEXT_SHADOWS},
            }),
            Row({
                mainAxisAlignment: 'center',
                children: [
                    AutoRefresh({
                        intervalMs: 1000,
                        child: DateTimeText({
                            format: 'HH:mm',
                            style: {color: WHITE, fontSize: 72, fontWeight: 'w300', shadows: TOP_TEXT_SHADOWS},
                        }),
                    }),
                    Padding({
                        padding: {left: 10, top: 16},
                        child: Column({
                            crossAxisAlignment: 'start',
                            children: [
                                Row({
                                    crossAxisAlignment: 'center',
                                    children: [
                                        Text(`${city.temp}°`, {
                                            style: {color: WHITE, fontSize: 38, fontWeight: 'w400', shadows: TOP_TEXT_SHADOWS},
                                        }),
                                        Padding({
                                            padding: {left: 8},
                                            child: weatherIconView(city.iconSource, 42),
                                        }),
                                    ],
                                }),
                                Text(`${city.high}° / ${city.low}°`, {
                                    style: {color: WHITE, fontSize: 18, fontWeight: 'w700', shadows: TOP_TEXT_SHADOWS},
                                }),
                            ],
                        }),
                    }),
                ],
            }),
            Text(state.date, {
                textAlign: 'center',
                style: {color: WHITE, fontSize: 18, fontWeight: 'w700', shadows: TOP_TEXT_SHADOWS},
            }),
            SizedBox({height: 32}),
        ],
    });
}

function fixedHourlyItems(items) {
    const source = Array.isArray(items) ? items.slice(0, 7) : [];
    while (source.length < 7) {
        source.push({time: '--:--', iconSource: null, temp: '--'});
    }
    return source;
}

function fixedDailyItems(items) {
    const source = Array.isArray(items) ? items.slice(0, 7) : [];
    while (source.length < 7) {
        source.push(emptyDailyItem(source.length));
    }
    return source;
}

function emptyDailyItem(index) {
    return {
        day: index === 0 ? '今天' : '--',
        date: '--/--',
        iconSource: null,
        text: '--',
        high: '--',
        low: '--',
        air: '-',
    };
}

function hourlyCard(items) {
    const displayItems = fixedHourlyItems(items);
    return glassCard({
        margin: {bottom: 18},
        child: Column({
            crossAxisAlignment: 'stretch',
            children: [
                Row({
                    mainAxisAlignment: 'spaceBetween',
                    children: displayItems.map((item) => hourlyTime(item)),
                }),
                Container({
                    height: 1,
                    margin: {top: 14, bottom: 4},
                    color: '#33FFFFFF',
                }),
                Row({
                    mainAxisAlignment: 'spaceBetween',
                    children: displayItems.map((item) => hourlyWeather(item)),
                }),
            ],
        }),
    });
}

function hourlyTime(item) {
    return SizedBox({
        width: 68,
        child: Text(item.time, {
            textAlign: 'center',
            style: {color: WHITE, fontSize: 15, fontWeight: 'w700'},
        }),
    });
}

function hourlyWeather(item) {
    return SizedBox({
        width: 68,
        height: 92,
        child: Column({
            crossAxisAlignment: 'center',
            children: [
                SizedBox({
                    height: 64,
                    child: Center({
                    child: weatherIconView(item.iconSource, 36),
                    }),
                }),
                Text(`${item.temp}°`, {
                    textAlign: 'center',
                    style: {color: WHITE, fontSize: 14, fontWeight: 'w700'},
                }),
            ],
        }),
    });
}

function dailyCard(items) {
    const displayItems = fixedDailyItems(items);
    return glassCard({
        margin: {bottom: 18},
        child: Column({
            crossAxisAlignment: 'stretch',
            children: [
                Row({
                    mainAxisAlignment: 'spaceBetween',
                    children: displayItems.map((item) => dailyColumn(item)),
                }),
                Padding({
                    padding: {top: 18, bottom: 10},
                    child: temperatureChart(displayItems),
                }),
                Row({
                    mainAxisAlignment: 'spaceBetween',
                    children: displayItems.map((item) => airPill(item.air)),
                }),
            ],
        }),
    });
}

function dailyColumn(item) {
    return SizedBox({
        width: 68,
        child: Column({
            crossAxisAlignment: 'center',
            children: [
                Text(item.day, {
                    textAlign: 'center',
                    style: {color: WHITE, fontSize: 15, fontWeight: 'w700'},
                }),
                Text(item.date, {
                    textAlign: 'center',
                    style: {color: WHITE_85, fontSize: 12},
                }),
                Padding({
                    padding: {top: 12, bottom: 8},
                    child: weatherIconView(item.iconSource, 36),
                }),
                Text(item.text, {
                    textAlign: 'center',
                    style: {color: WHITE, fontSize: 14, fontWeight: 'w700'},
                }),
            ],
        }),
    });
}

function temperatureChart(items) {
    const width = 520;
    const height = 118;
    const high = items.map((item) => numericTemperature(item.high));
    const low = items.map((item) => numericTemperature(item.low));
    const values = [...high, ...low].filter(Number.isFinite);
    const minimum = values.length === 0 ? 0 : Math.min(...values);
    const maximum = values.length === 0 ? 1 : Math.max(...values);
    const span = Math.max(4, maximum - minimum);
    const yAt = (value) => 108 - (value - minimum) / span * 84;
    const xAt = (index) => index * width / Math.max(1, items.length - 1);

    return SizedBox({
        height,
        child: Stack({
            fit: 'expand',
            children: [
                Padding({
                    padding: {horizontal: 34},
                    child: ResponsiveViewport({
                        designWidth: width,
                        designHeight: height,
                        fit: 'fill',
                        child: Canvas({
                            width,
                            height,
                            staticDraw(ctx) {
                                drawTemperatureLine(ctx, high, xAt, yAt, '#FFFFC857');
                                drawTemperatureLine(ctx, low, xAt, yAt, '#FF7DD3FC');
                            },
                        }),
                    }),
                }),
                Row({
                    mainAxisAlignment: 'spaceBetween',
                    children: items.map((item, index) => temperatureColumn(
                        item,
                        high[index],
                        low[index],
                        yAt,
                    )),
                }),
            ],
        }),
    });
}

function drawTemperatureLine(ctx, values, xAt, yAt, color) {
    const points = values
        .map((value, index) => Number.isFinite(value)
            ? {x: xAt(index), y: yAt(value)}
            : null)
        .filter(Boolean);
    if (points.length === 0) return;
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();
    points.forEach((point, index) => {
        if (index === 0) ctx.moveTo(point.x, point.y);
        else ctx.lineTo(point.x, point.y);
    });
    ctx.stroke();
}

function temperatureColumn(item, high, low, yAt) {
    return SizedBox({
        width: 68,
        height: 118,
        child: Stack({
            children: [
                ...temperatureMarkers(item.high, high, yAt, '#FFFFC857'),
                ...temperatureMarkers(item.low, low, yAt, '#FF7DD3FC'),
            ],
        }),
    });
}

function temperatureMarkers(label, value, yAt, color) {
    if (!Number.isFinite(value)) return [];
    const y = yAt(value);
    return [
        Positioned({
            left: 0,
            top: Math.max(0, y - 25),
            child: SizedBox({
                width: 68,
                child: Text(`${label}\u00B0C`, {
                    textAlign: 'center',
                    style: {color: WHITE, fontSize: 12},
                }),
            }),
        }),
        Positioned({
            left: 30,
            top: y - 4,
            child: Container({
                width: 8,
                height: 8,
                decoration: {color, borderRadius: 4},
            }),
        }),
    ];
}

function numericTemperature(value) {
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
}

function airPill(text) {
    return SizedBox({
        width: 68,
        child: Center({
            child: Container({
                width: 40,
                padding: {vertical: 4},
                decoration: {
                    color: GLASS_STRONG,
                    borderRadius: 16,
                },
                child: Text(text, {
                    textAlign: 'center',
                    style: {color: WHITE, fontSize: 12, fontWeight: 'w700'},
                }),
            }),
        }),
    });
}

function metricsCard(city, resourceBaseUrl) {
    return glassCard({
        child: Row({
            mainAxisAlignment: 'spaceBetween',
            children: [
                aqiGauge(city.air, city.aqi),
                metricColumn(metricIcon(resourceBaseUrl, 'code-orange.svg', '天气预警'), city.alert, '预警'),
                metricColumn(metricIcon(resourceBaseUrl, 'thermometer-celsius.svg', '体感温度'), `${city.bodyTemp}℃`, '体感温度'),
                metricColumn(metricIcon(resourceBaseUrl, 'humidity.svg', '湿度'), `${city.humidity}%`, '湿度'),
                metricColumn(metricIcon(resourceBaseUrl, 'uv-index.svg', '紫外线'), city.uv, '紫外线'),
            ],
        }),
    });
}

function aqiGauge(category, value) {
    const aqi = Number(value);
    const normalized = Number.isFinite(aqi) ? Math.max(0, Math.min(500, aqi)) : 0;
    const start = Math.PI * 0.75;
    const sweep = Math.PI * 1.5;
    return SizedBox({
        width: 86,
        height: 112,
        child: Column({
            mainAxisAlignment: 'end',
            crossAxisAlignment: 'center',
            children: [
                SizedBox({
                    width: 86,
                    height: 86,
                    child: Stack({
                        fit: 'expand',
                        children: [
                            Canvas({
                                width: 86,
                                height: 86,
                                staticDraw(ctx) {
                                    ctx.lineWidth = 5;
                                    ctx.lineCap = 'round';
                                    ctx.strokeStyle = '#66FFFFFF';
                                    ctx.beginPath();
                                    ctx.arc(43, 43, 34, start, start + sweep);
                                    ctx.stroke();
                                    if (normalized > 0) {
                                        ctx.strokeStyle = aqiColor(normalized);
                                        ctx.beginPath();
                                        ctx.arc(
                                            43,
                                            43,
                                            34,
                                            start,
                                            start + sweep * normalized / 500,
                                        );
                                        ctx.stroke();
                                    }
                                },
                            }),
                            Center({
                                child: Column({
                                    mainAxisSize: 'min',
                                    crossAxisAlignment: 'center',
                                    children: [
                                        Text(category || '-', {
                                            textAlign: 'center',
                                            style: {color: WHITE, fontSize: 15, fontWeight: 'w700'},
                                        }),
                                        Text(Number.isFinite(aqi) ? String(Math.round(aqi)) : '-', {
                                            textAlign: 'center',
                                            style: {color: WHITE_85, fontSize: 11},
                                        }),
                                    ],
                                }),
                            }),
                        ],
                    }),
                }),
                Text('空气质量', {
                    textAlign: 'center',
                    style: {color: WHITE_85, fontSize: 12, fontWeight: 'w700'},
                }),
            ],
        }),
    });
}

function aqiColor(value) {
    if (value <= 50) return '#FF00C853';
    if (value <= 100) return '#FFFFD600';
    if (value <= 150) return '#FFFF9100';
    if (value <= 200) return '#FFFF3D00';
    if (value <= 300) return '#FFAA00FF';
    return '#FF8D2C3A';
}

function metricIcon(resourceBaseUrl, name, semanticLabel) {
    return Svg({
        src: `${resourceBaseUrl}/weatherIcon/${name}`,
        width: 54,
        height: 54,
        fit: 'contain',
        semanticLabel,
    });
}

function metricColumn(icon, value, label) {
    return SizedBox({
        width: 86,
        height: 112,
        child: Column({
            mainAxisAlignment: 'end',
            crossAxisAlignment: 'center',
            children: [
                typeof icon === 'string'
                    ? Text(icon, {
                        textAlign: 'center',
                        style: {color: WHITE, fontSize: 28, fontWeight: 'w700'},
                    })
                    : icon,
                Padding({
                    padding: {top: 8, bottom: 6},
                    child: Text(value, {
                        textAlign: 'center',
                        style: {color: WHITE, fontSize: 16, fontWeight: 'w700'},
                    }),
                }),
                Text(label, {
                    textAlign: 'center',
                    style: {color: WHITE_85, fontSize: 12, fontWeight: 'w700'},
                }),
            ],
        }),
    });
}

function glassCard({child, margin = {bottom: 0}}) {
    return Container({
        margin,
        padding: {all: 16},
        decoration: {
            color: GLASS,
            borderRadius: 14,
            border: {color: BORDER, width: 1},
        },
        child,
    });
}
