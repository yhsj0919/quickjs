import {
  AppBar,
  Column,
  ElevatedButton,
  Page,
  Padding,
  Scaffold,
  SizedBox,
  Text,
  TextField
} from 'quickjs_ui';
import pluginService from 'quickjs_extensions/plugin_service';
import storage from 'quickjs_extensions/storage';

export default Page({
  createState() {
    return {account: 'demo@example.com', message: '尚未登录'};
  },

  build(state, _props, actions) {
    return Scaffold({
      appBar: AppBar({titleText: '插件提供的登录页'}),
      body: Padding({
        padding: {all: 24},
        child: Column({
          crossAxisAlignment: 'stretch',
          children: [
            Text('这个页面和认证逻辑都来自 ui/login.mjs。'),
            SizedBox({height: 20}),
            TextField({
              value: state.account,
              labelText: '账号',
              onChanged: actions.changeAccount()
            }),
            SizedBox({height: 12}),
            ElevatedButton({
              onPressed: actions.login(),
              child: Text('调用 Core 登录')
            }),
            SizedBox({height: 16}),
            Text(state.message)
          ]
        })
      })
    });
  },

  changeAccount(state, payload) {
    return {...state, account: payload.value};
  },

  async login(state) {
    const result = await pluginService.call('submitLogin', state.account);
    if (result.status !== 'ok') {
      return {...state, message: String(result.error || '登录失败')};
    }
    await storage.set('account', result.data.account);
    return {...state, message: `登录成功：${result.data.account}`};
  }
});
