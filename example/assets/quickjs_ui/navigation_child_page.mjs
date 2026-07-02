import { Column, Container, ElevatedButton, Page, Text } from 'quickjs_ui';

export default Page({
  name: 'quickjs-ui-navigation-child',

  createState(props) {
    return {
      localCount: 10 + (props.count ?? 0)
    };
  },

  build(state, props, page) {
    return Column({
      padding: 16,
      crossAxisAlignment: 'stretch',
      gap: 12,
      children: [
        Text('JSUI 子页', {
          style: { fontSize: 22, fontWeight: 'w700' }
        }),
        Text(`source: ${props.source ?? 'none'}`),
        Text(`itemId: ${props.itemId ?? 'none'}`),
        Text(`parent count: ${props.count ?? 'none'}`),
        Container({
          padding: 12,
          decoration: {
            color: '$surfaceContainerHighest',
            borderRadius: 8
          },
          child: Text(`child local count: ${state.localCount}`)
        }),
        ElevatedButton({
          child: Text('子页计数 +1'),
          onPressed: page.increment()
        }),
        ElevatedButton({
          child: Text('替换当前 JSUI 子页'),
          onPressed: page.replaceSelf()
        }),
        ElevatedButton({
          child: Text('返回 JSUI 详情页'),
          onPressed: page.popToDetail()
        })
      ]
    });
  },

  increment(state) {
    return {
      ...state,
      localCount: state.localCount + 1
    };
  },

  replaceSelf(state, _payload, props) {
    quickjsUiNavigation.replace({
      route: 'quickjs-ui.navigation.child.replaced',
      path: './navigation_child_page.mjs',
      params: {
        source: 'jsui-child-replaced',
        itemId: props.itemId,
        count: 30
      }
    });
    return state;
  },

  popToDetail(state, _payload, props) {
    return quickjsUiNavigation.pop({
      from: 'jsui-child',
      itemId: props.itemId,
      localCount: state.localCount
    });
  }
});
