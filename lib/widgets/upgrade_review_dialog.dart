import 'package:flutter/material.dart';

class UpgradeReviewDialog extends StatelessWidget {
  final Map<String, Map<String, String>> changes;
  final List<String> messages;

  const UpgradeReviewDialog({
    super.key,
    required this.changes,
    required this.messages,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Review Changes'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text('The following changes will be applied:'),
            const SizedBox(height: 8),
            ...changes.entries.map((entry) {
              final package = entry.key;
              final change = entry.value;
              return ListTile(
                title: Text(package),
                subtitle: Text('${change['from']} → ${change['to']}'),
              );
            }),
            const Divider(),
            const Text('Process log:'),
            const SizedBox(height: 8),
            ...messages.map((message) => Text('• $message')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Apply Changes'),
        ),
      ],
    );
  }
}
