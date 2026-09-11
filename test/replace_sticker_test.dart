import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';

/// Opaque "image" bytes. [addToPack] writes them verbatim, it never decodes.
final Uint8List _stickerBytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

void main() {
  late Directory tmp;
  late StickerPack pack;
  late File first;
  late File second;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('replace_sticker_test');
    packsDir = '${tmp.path}/packs';
    mediaCacheDir = '${tmp.path}/media';
    await Directory(packsDir).create(recursive: true);
    await Directory(mediaCacheDir).create(recursive: true);
    first = File('$packsDir/sticker_0_old.webp')..writeAsBytesSync(_stickerBytes);
    second = File('$packsDir/sticker_1_old.webp')..writeAsBytesSync(_stickerBytes);
    pack = StickerPack(
      'test pack',
      'author',
      'pack_test',
      [Sticker(first.path, ['❤']), Sticker(second.path, ['😂'])],
      '1',
      false,
    );
    packs = [pack];
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('saving over an existing index replaces it instead of appending', () async {
    await addToPack(pack, 0, _stickerBytes);

    expect(pack.stickers, hasLength(2), reason: 'a replaced sticker must not be appended');
    expect(pack.stickers[0].source, isNot(first.path));
    expect(File(pack.stickers[0].source).existsSync(), isTrue);
    expect(first.existsSync(), isFalse, reason: 'the replaced file is deleted');
  });

  test('a replaced sticker keeps its slot and its emojis', () async {
    await addToPack(pack, 0, _stickerBytes);

    expect(pack.stickers[0].emojis, ['❤'], reason: 'the emojis belong to the slot');
    expect(pack.stickers[1].source, second.path, reason: 'the other stickers must not move');
    expect(pack.stickers[1].emojis, ['😂']);
  });

  test('the bumped image data version is the one that gets persisted', () async {
    await addToPack(pack, 0, _stickerBytes);

    expect(pack.imageDataVersion, '2');
    final reloaded = await getPacks();
    expect(reloaded, hasLength(1));
    expect(
      reloaded.single.imageDataVersion,
      '2',
      reason: 'WhatsApp ignores a pack whose version it has already seen, so a '
          'replaced sticker would never show up after a restart',
    );
    expect(reloaded.single.stickers[0].source, pack.stickers[0].source);
    expect(reloaded.single.stickers, hasLength(2));
  });

  test('an index past the end still appends a new sticker', () async {
    await addToPack(pack, 2, _stickerBytes);

    expect(pack.stickers, hasLength(3));
    expect(pack.stickers[2].emojis, ['❤']);
    expect(File(pack.stickers[2].source).existsSync(), isTrue);
  });

  test('index 30 replaces the tray icon and leaves the stickers alone', () async {
    await addToPack(pack, 30, _stickerBytes);

    expect(pack.stickers, hasLength(2));
    expect(pack.trayIcon, isNotNull);
    expect(File(pack.trayIcon!).existsSync(), isTrue);
    expect(first.existsSync(), isTrue);
    expect(second.existsSync(), isTrue);
  });
}
