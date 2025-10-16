import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

Future<void> saveTextFile(String filename, String content, String mimeType) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([Uint8List.fromList(bytes)], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
