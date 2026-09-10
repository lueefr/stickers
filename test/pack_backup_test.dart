import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/data/pack_backup.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';

void main() {
  late Directory work;
  late Directory backup;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('pack_backup_test_');
    backup = await Directory('${work.path}/backup').create();
  });

  tearDown(() async => work.delete(recursive: true));

  Future<StickerPack> makePack(String name, List<int> bytes) async {
    final source = await File('${work.path}/$name.webp').writeAsBytes(bytes);
    return StickerPack(name, 'Autor', 'same_id', [Sticker(source.path, ['❤', '😀'])], '42', true,
        trayIcon: source.path, publisherWebsite: 'https://example.com',
        privacyPolicyWebsite: 'https://example.com/privacy',
        licenseAgreementWebsite: 'https://example.com/license');
  }

  test('multiple packs preserve metadata, media and order without changing originals', () async {
    final first = await makePack('Primeiro', [1, 2, 3]);
    final second = await makePack('Segundo', [4, 5, 6]);
    final original = jsonEncode([first.toJson(), second.toJson()]);
    await writePackBackup([first, second], backup);
    final restored = await readPackBackup(backup);
    expect(restored.map((p) => p.title), ['Primeiro', 'Segundo']);
    for (var i = 0; i < restored.length; i++) {
      final pack = restored[i];
      final source = [first, second][i];
      expect(pack.author, source.author);
      expect(pack.animated, isTrue);
      expect(pack.imageDataVersion, '42');
      expect(pack.publisherWebsite, source.publisherWebsite);
      expect(pack.privacyPolicyWebsite, source.privacyPolicyWebsite);
      expect(pack.licenseAgreementWebsite, source.licenseAgreementWebsite);
      expect(pack.stickers.single.emojis, source.stickers.single.emojis);
      expect(await File(pack.stickers.single.source).readAsBytes(),
          await File(source.stickers.single.source).readAsBytes());
      expect(await File(pack.trayIcon!).readAsBytes(), await File(source.trayIcon!).readAsBytes());
    }
    expect(jsonEncode([first.toJson(), second.toJson()]), original);
  });

  test('legacy single-pack archive is still supported', () async {
    final pack = await makePack('Legacy', [1]);
    final data = pack.toJson();
    data['stickers'] = [ {'source': '0.webp', 'emojis': ['❤']} ];
    data['trayIcon'] = null;
    await File(pack.stickers.single.source).copy('${backup.path}/0.webp');
    await File('${backup.path}/pack.json').writeAsString(jsonEncode(data));
    final restored = await readPackBackup(backup);
    expect(restored.single.title, 'Legacy');
    expect(restored.single.trayIcon, isNull);
  });

  test('empty pack without tray icon round trips', () async {
    final pack = StickerPack('Empty', 'Author', 'id', [], '1', false);
    await writePackBackup([pack], backup);
    final restored = await readPackBackup(backup);
    expect(restored.single.stickers, isEmpty);
    expect(restored.single.trayIcon, isNull);
    expect(restored.single.animated, isFalse);
  });

  test('missing media rejects the backup', () async {
    await writePackBackup([await makePack('Missing', [1])], backup);
    await File('${backup.path}/pack_0/0.webp').delete();
    await expectLater(readPackBackup(backup), throwsA(isA<FileSystemException>()));
  });

  test('path traversal in metadata is rejected', () async {
    final pack = await makePack('Outside', [1]);
    final data = pack.toJson();
    data['stickers'] = [ {'source': '../Outside.webp', 'emojis': ['❤']} ];
    data['trayIcon'] = null;
    await File('${backup.path}/pack.json').writeAsString(jsonEncode(data));
    await expectLater(readPackBackup(backup), throwsFormatException);
  });

  test('unknown manifest versions and malformed metadata are rejected', () async {
    final manifest = File('${backup.path}/packs.json');
    for (final data in [
      {'version': 2, 'packs': []},
      {'version': 1, 'packs': []},
      {'version': 1, 'packs': [{}]},
    ]) {
      await manifest.writeAsString(jsonEncode(data));
      await expectLater(readPackBackup(backup), throwsFormatException);
    }
  });
}
