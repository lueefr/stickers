import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';

/// Opaque "image" bytes: [saveTemp] writes them verbatim, it never decodes.
final Uint8List _bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('media_cache_test');
    mediaCacheDir = '${tmp.path}/media';
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('saveTemp writes even when the cache directory was wiped', () async {
    // Nothing creates the directory here, which is what "Clear cache" (or the
    // system reclaiming space) leaves behind: the app keeps running with a
    // mediaCacheDir that points at a directory that is no longer there.
    expect(Directory(mediaCacheDir).existsSync(), isFalse);

    final File output = await saveTemp(_bytes);

    expect(output.existsSync(), isTrue);
    expect(await output.readAsBytes(), _bytes);
  });

  test('saveTemp keeps working when the directory is already there', () async {
    await Directory(mediaCacheDir).create(recursive: true);

    final File first = await saveTemp(_bytes);
    final File second = await saveTemp(_bytes);

    expect(first.existsSync(), isTrue);
    expect(second.existsSync(), isTrue);
  });
}
