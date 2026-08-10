import { suffix, tag } from './modules/helper.js';

let locale = 'en-US';

export function init(context) {
  locale = context.locale || locale;
  return { locale, tag };
}

export function hello(name) {
  return `hello ${name}${suffix} (${locale})`;
}

export function profile(name, score) {
  return {
    name,
    score,
    locale,
    source: 'zip',
    tag,
  };
}
