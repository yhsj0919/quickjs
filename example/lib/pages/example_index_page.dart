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
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('quickjs 示例'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Core'),
              Tab(text: 'quickjs_ui'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _ExamplePageList(pages: examplePages),
            _ExamplePageList(pages: quickjsUiExamplePages),
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
