import { ListView, Page, RefreshIndicator, Text } from 'quickjs_ui';

const pageSize = 40;

export default Page({
  name: 'InfiniteListPage',

  createState() {
    return {
      loadedCount: pageSize,
      loading: false,
      page: 1,
      resetToken: 0,
      loadRequest: 0,
    };
  },

  build(state, _props, page) {
    return RefreshIndicator({
      onRefresh: page.refresh(),
      child: ListView.builder({
        key: 'infinite-list',
        itemCount: state.loadedCount,
        hasMore: true,
        loading: state.loading,
        loadingText: `正在加载第 ${state.page + 1} 页…`,
        loadMoreThreshold: 8,
        onLoadMore: page.loadMore(),
        resetToken: state.resetToken,
        prefetchItemCount: 20,
        cacheExtent: 320,
        padding: { vertical: 8 },
        itemKey: index => `infinite-row-${index}`,
        itemBuilder: index =>
          Text(`无限列表项 ${index + 1} · 第 ${Math.floor(index / pageSize) + 1} 页`),
      }),
    });
  },

  loadMore(state, _payload, _props, _event, ctx) {
    if (state.loading) {
      return null;
    }
    const requestToken = state.loadRequest + 1;
    setTimeout(
      () => ctx.call('finishLoadMore', { requestToken }),
      500
    );
    return { loading: true, loadRequest: requestToken };
  },

  finishLoadMore(state, payload) {
    if (payload?.requestToken !== state.loadRequest || !state.loading) {
      return null;
    }
    return {
      loadedCount: state.loadedCount + pageSize,
      loading: false,
      page: state.page + 1,
    };
  },

  refresh(state) {
    return {
      loadedCount: pageSize,
      loading: false,
      page: 1,
      resetToken: state.resetToken + 1,
      loadRequest: state.loadRequest + 1,
    };
  },
});
