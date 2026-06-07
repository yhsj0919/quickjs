import 'package:flutter/material.dart';

import '../example_pages.dart';

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
