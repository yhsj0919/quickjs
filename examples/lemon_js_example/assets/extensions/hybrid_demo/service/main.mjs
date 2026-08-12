export function getHome() {
  return {
    status: 'ok',
    data: {
      title: 'Core 返回的首页数据',
      items: ['混合插件', '原生数据页', 'JSUI 登录页']
    }
  };
}

export function submitLogin(account) {
  const normalized = String(account || '').trim();
  return normalized.length === 0
    ? {status: 'error', error: '请输入账号'}
    : {
        status: 'ok',
        data: {account: normalized, authenticated: true}
      };
}
