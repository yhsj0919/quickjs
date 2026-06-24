import 'package:flutter/material.dart';

import '../example_pages.dart';

/// example 页面索引，用于集中进入各个手动验收页面。
class ExampleIndexPage extends StatelessWidget {
  const ExampleIndexPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('quickjs 示例')),
      body: ListView.separated(
        itemCount: examplePages.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final page = examplePages[index];
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
      ),
    );
  }
}
