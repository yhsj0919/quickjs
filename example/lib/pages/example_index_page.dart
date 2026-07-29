import 'package:flutter/material.dart';

import '../example_pages.dart';
import '../example_page_spec.dart';
import '../quickjs_ui_example_pages.dart';

/// example 页面索引，用于集中进入各个手动验收页面。
class ExampleIndexPage extends StatelessWidget {
  const ExampleIndexPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('quickjs 示例'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Core'),
              Tab(text: '入门加载'),
              Tab(text: 'UI 基础'),
              Tab(text: '宿主工程'),
              Tab(text: '场景'),
              Tab(text: '实验室'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _ExamplePageList(pages: <ExamplePageSpec>[...examplePages]),
            _ExamplePageList(pages: quickjsUiGettingStartedExamplePages),
            _ExamplePageList(pages: quickjsUiFoundationExamplePages),
            _ExamplePageList(pages: quickjsUiPlatformExamplePages),
            _ExamplePageList(pages: quickjsUiScenarioExamplePages),
            _ExamplePageList(pages: quickjsUiLabExamplePages),
          ],
        ),
      ),
    );
  }
}

class _ExamplePageList extends StatelessWidget {
  const _ExamplePageList({required this.pages});

  final List<ExamplePageSpec> pages;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: pages.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final page = pages[index];
        return ListTile(
          leading: SizedBox(
            width: 32,
            child: Text(
              (index + 1).toString().padLeft(2, '0'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          title: Text(page.title),
          subtitle: Text(page.description),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: page.builder,
                settings: RouteSettings(name: page.title),
              ),
            );
          },
        );
      },
    );
  }
}
