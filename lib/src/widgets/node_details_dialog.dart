import 'package:flutter/material.dart';

Future<String?> showNodeDetailsEditorDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NodeDetailsDialog(
      title: title,
      initialValue: initialValue,
    ),
  );
}

class _NodeDetailsDialog extends StatefulWidget {
  const _NodeDetailsDialog({
    required this.title,
    required this.initialValue,
  });

  final String title;
  final String initialValue;

  @override
  State<_NodeDetailsDialog> createState() => _NodeDetailsDialogState();
}

class _NodeDetailsDialogState extends State<_NodeDetailsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 400),
        child: SizedBox(
          width: 520,
          child: TextField(
            controller: _controller,
            autofocus: true,
            maxLines: null,
            minLines: 6,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'Add details using Markdown formatting',
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.replaceAll('\r\n', '\n');
            Navigator.of(context).pop(value);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
