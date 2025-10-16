import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveTextFile(String filename, String content, String mimeType) async {
  final directory = await getTemporaryDirectory();
  final file = File(p.join(directory.path, filename));
  await file.writeAsString(content);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: mimeType, name: filename)],
    subject: filename,
  );
}
