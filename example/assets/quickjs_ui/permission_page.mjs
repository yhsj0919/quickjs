import { Column, Container, Page, Text } from 'quickjs_ui';

export default Page({
  name: 'quickjs-ui-permission-page',

  createState() {
    return {
      loadedAt: 'created'
    };
  },

  build(state, props) {
    const permissions = props.permissions ?? [];
    return Column({
      crossAxisAlignment: 'stretch',
      gap: 12,
      children: [
        Text('权限测试 JS 页面', {
          style: { fontSize: 22, fontWeight: 'w700' }
        }),
        Text(`加载状态：${state.loadedAt}`),
        Text(`权限策略：${props.policyName ?? 'unrestricted'}`),
        Text(`页面声明权限：${permissions.join(', ')}`),
        Container({
          padding: 12,
          decoration: {
            color: '$surfaceContainerHighest',
            borderRadius: 8
          },
          child: Column({
            crossAxisAlignment: 'stretch',
            gap: 8,
            children: [
              Text('说明', { style: { fontWeight: 'w700' } }),
              Text('此页面只验证 manifest permissions 与宿主策略。'),
              Text('权限不会自动授予能力；真实可调用能力仍由 mounts 决定。')
            ]
          })
        })
      ]
    });
  }
});
