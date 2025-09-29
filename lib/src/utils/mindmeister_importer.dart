import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class MindmeisterImporter {
  Future<String> toMarkdown(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final mapFile = archive.files.firstWhere(
      (file) => file.name == 'map.json',
      orElse: () => throw const FormatException('map.json missing'),
    );
    final jsonString = utf8.decode(mapFile.content as List<int>);
    final root = _extractRoot(jsonDecode(jsonString));
    final lines = <String>[];
    _walk(root, 0, lines);
    return lines.join(String.fromCharCode(10));
  }

  Map<String, dynamic> _extractRoot(dynamic json) {
    if (json is Map<String, dynamic>) {
      if (json.containsKey('root') && json['root'] is Map<String, dynamic>) {
        return json['root'] as Map<String, dynamic>;
      }
      if (json.containsKey('mindmap') &&
          json['mindmap'] is Map<String, dynamic>) {
        final map = json['mindmap'] as Map<String, dynamic>;
        if (map.containsKey('root') && map['root'] is Map<String, dynamic>) {
          return map['root'] as Map<String, dynamic>;
        }
      }
    }
    throw const FormatException('Unsupported MindMeister format');
  }

  void _walk(Map<String, dynamic> node, int depth, List<String> lines) {
    final title = _cleanText(node['title'] ?? node['text']);
    final note = _cleanText(node['note'] ?? node['notes'] ?? node['plainText']);
    final indent = ' ' * (depth * 4);
    var line = '$indent- $title';
    if (note.isNotEmpty) {
      line += ' :: $note';
    }
    lines.add(line);
    for (final child in _childNodes(node['children'])) {
      _walk(child, depth + 1, lines);
    }
  }

  Iterable<Map<String, dynamic>> _childNodes(dynamic source) sync* {
    if (source is List) {
      for (final item in source) {
        final node = _asNode(item);
        if (node != null) {
          yield node;
        }
      }
      return;
    }
    if (source is Map) {
      for (final value in source.values) {
        if (value is List) {
          for (final item in value) {
            final node = _asNode(item);
            if (node != null) {
              yield node;
            }
          }
        } else {
          final node = _asNode(value);
          if (node != null) {
            yield node;
          }
        }
      }
    }
  }

  Map<String, dynamic>? _asNode(dynamic value) {
    if (value is Map<String, dynamic>) {
      if (value.containsKey('node') && value['node'] is Map<String, dynamic>) {
        return value['node'] as Map<String, dynamic>;
      }
      return value;
    }
    return null;
  }

  String _cleanText(dynamic value) {
    if (value == null) {
      return '';
    }
    final text = value.toString().replaceAll(RegExp('[\n\r]+'), ' ').trim();
    return text;
  }
}
