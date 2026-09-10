import 'dart:convert';
import 'dart:io';

import 'package:stickers/src/data/sticker_pack.dart';

/// Each pack has its own media directory so identical filenames cannot collide.
Future<void> writePackBackup(List<StickerPack> packs, Directory directory) async {
  final entries = <Map<String, Object?>>[];
  for (var p = 0; p < packs.length; p++) {
    final pack = packs[p];
    final prefix = 'pack_$p';
    await Directory('${directory.path}/$prefix').create(recursive: true);
    final data = pack.toJson();
    final stickers = pack.stickers.map((s) => s.toJson()).toList();
    for (var i = 0; i < stickers.length; i++) {
      final source = '$prefix/$i.webp';
      await File(pack.stickers[i].source).copy('${directory.path}/$source');
      stickers[i]['source'] = source;
    }
    data['stickers'] = stickers;
    if (pack.trayIcon != null) {
      final source = '$prefix/tray.webp';
      await File(pack.trayIcon!).copy('${directory.path}/$source');
      data['trayIcon'] = source;
    }
    entries.add(data);
  }
  await File('${directory.path}/packs.json').writeAsString(jsonEncode({
    'version': 1,
    'packs': entries,
  }));
}

/// Reads the multi-pack format and the original single-pack pack.json format.
Future<List<StickerPack>> readPackBackup(Directory directory) async {
  final manifest = File('${directory.path}/packs.json');
  final List<dynamic> entries;
  if (await manifest.exists()) {
    final data = jsonDecode(await manifest.readAsString());
    if (data is! Map || data['version'] != 1 || data['packs'] is! List) {
      throw const FormatException('Invalid sticker backup manifest');
    }
    entries = data['packs'] as List;
    if (entries.isEmpty) throw const FormatException('Empty sticker backup');
  } else {
    entries = [jsonDecode(await File('${directory.path}/pack.json').readAsString())];
  }
  try {
    final result = <StickerPack>[];
    for (final entry in entries) {
      final pack = StickerPack.fromJson(entry as Map<String, dynamic>);
      for (final sticker in pack.stickers) {
        sticker.source = await _resolveFile(directory, sticker.source);
      }
      if (pack.trayIcon != null) {
        pack.trayIcon = await _resolveFile(directory, pack.trayIcon!);
      }
      result.add(pack);
    }
    return result;
  } on TypeError {
    throw const FormatException('Invalid sticker pack metadata');
  }
}

Future<String> _resolveFile(Directory root, String relative) async {
  if (relative.isEmpty || relative.startsWith('/') ||
      relative.contains('\\') || relative.contains(':') ||
      relative.split('/').any((part) => part == '..' || part == '.')) {
    throw const FormatException('Invalid backup media path');
  }
  final source = '${root.path}/$relative';
  await validateBackupFile(root, source);
  return source;
}

/// Rejects missing files and references outside the extracted archive.
Future<void> validateBackupFile(Directory root, String source) async {
  final rootPath = await root.resolveSymbolicLinks();
  final file = File(source);
  final resolved = await file.resolveSymbolicLinks();
  if (!resolved.startsWith('$rootPath${Platform.pathSeparator}') ||
      !await file.exists()) {
    throw const FormatException('Invalid backup media file');
  }
}
