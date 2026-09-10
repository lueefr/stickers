import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:image_editor/image_editor.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/pack_backup.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';

Future<void> savePacks(List<StickerPack> packs) async {
  File output = File("$packsDir/packs.json");
  await output.writeAsString(jsonEncode(packs.map((pack) => pack.toJson()).toList()));
}

Future<void> exportPack(StickerPack pack) => exportPacks([pack]);

/// Shares one archive, regardless of how many packs were selected.
Future<void> exportPacks(List<StickerPack> selected) async {
  if (selected.isEmpty) return;
  final cache = await Directory(exportCacheDir).create(recursive: true);
  final work = await cache.createTemp('backup_');
  final contents = await Directory('${work.path}/contents').create();
  try {
    await writePackBackup(selected, contents);
    final zip = File('${work.path}/sticker_pack.zip');
    await ZipFile.createFromDirectory(sourceDir: contents, zipFile: zip);
    await SharePlus.instance.share(ShareParams(files: [XFile(zip.path)]));
  } finally {
    await contents.delete(recursive: true);
    // Keep the shared ZIP in the export cache: the receiving app may read it later.
  }
}

Future<void> importPack(File f) async {
  //TODO show progress
  Stopwatch sw = Stopwatch()..start();
  Directory importDir = Directory(mediaCacheDir);
  await importDir.create(recursive: true);
  final unzipDir = await importDir.createTemp("pack_");
  final createdDirs = <Directory>[];
  try {
    await ZipFile.extractToDirectory(zipFile: f, destinationDir: unzipDir);
    debugPrint("Unzip t=${sw.elapsedMilliseconds}ms");

    List<StickerPack> packsToAdd = [];

    switch (f.path.split(".").last.toLowerCase()) {
      case "wastickers":
        final dirContents = unzipDir.listSync();
        final pack = StickerPack(
            (await File("${unzipDir.path}/title.txt").readAsString()).replaceAll("\n", ""),
            (await File("${unzipDir.path}/author.txt").readAsString()).replaceAll("\n", ""),
            "pack_${DateTime.timestamp().millisecondsSinceEpoch}",
            dirContents
                .map((entry) => entry.path)
                .where((path) => path.toLowerCase().endsWith(".webp"))
                .map((path) => Sticker(path, ["❤"]))
                .toList(),
            "1000",
            false, // It's not possible to directly export animated packs from that app.
            trayIcon: dirContents.where((entry) => entry.path.toLowerCase().endsWith(".png")).firstOrNull?.path);
        packsToAdd.add(pack);
        break;
      case "stickify":
        final dirs = unzipDir.listSync().whereType<Directory>();
        for (final dir in dirs) {
          final json = jsonDecode(File("${dir.path}/contents.json").readAsStringSync());
          for (final packJson in json["sticker_packs"]) {
            final pack = StickerPack(
              packJson["name"],
              packJson["publisher"],
              packJson["identifier"],
              (packJson["stickers"] as List)
                  .map((sticker) => Sticker(
                        "${dir.path}/${sticker["image_file"]}",
                        (sticker["emojis"] as List).isEmpty ? ["❤"] : sticker["emojis"],
                      ))
                  .toList(),
              packJson["image_data_version"],
              packJson["animated_sticker_pack"],
              publisherWebsite: packJson["publisher_website"],
              licenseAgreementWebsite: packJson["license_agreement_website"],
              privacyPolicyWebsite: packJson["privacy_policy_website"],
            );
            packsToAdd.add(pack);
          }
        }
        break;
      default:
        packsToAdd.addAll(await readPackBackup(unzipDir));
    }
    debugPrint("Parse t=${sw.elapsedMilliseconds}ms");

    // Validate every referenced file before changing the user's library.
    for (final pack in packsToAdd) {
      for (final source in [
        ...pack.stickers.map((sticker) => sticker.source),
        if (pack.trayIcon != null) pack.trayIcon!,
      ]) {
        await validateBackupFile(unzipDir, source);
      }
    }
    await Directory(packsDir).create(recursive: true);
    for (final pack in packsToAdd) {
      // Never use an untrusted archive identifier as a destination path.
      final destination = await Directory(packsDir).createTemp('imported_');
      createdDirs.add(destination);
      pack.id = destination.uri.pathSegments.where((s) => s.isNotEmpty).last;
      for (var i = 0; i < pack.stickers.length; i++) {
        final file = await File(pack.stickers[i].source)
            .copy('${destination.path}/imported_$i.webp');
        pack.stickers[i].source = file.path;
      }
      if (pack.trayIcon != null) {
        pack.trayIcon = (await File(pack.trayIcon!)
            .copy('${destination.path}/imported_tray.webp')).path;
      }
    }
    await savePacks([...packs, ...packsToAdd]);
    packs.addAll(packsToAdd);
  } catch (_) {
    for (final directory in createdDirs) {
      await directory.delete(recursive: true);
    }
    rethrow;
  } finally {
    await unzipDir.delete(recursive: true);
    // The selected file (and its parent) belongs to the user, not to us.
  }
}

Future<List<StickerPack>> getPacks() async {
  File input = File("$packsDir/packs.json");
  if (await input.exists()) {
    return (jsonDecode(await input.readAsString()) as List).map((json) => StickerPack.fromJson(json)).toList();
  }
  return List.empty(growable: true);
}

Future<Uint8List> cropSticker(
    Rect cropRect, Uint8List rawImageData, StickerPack pack, int index, double rotation) async {
  // Apply crop then scale then put on 512x512 transparent image in center

  final crop = ImageEditorOption();
  Size oldSize = cropRect.size;
  crop.addOption(RotateOption(rotation.toInt()));
  crop.addOption(ClipOption.fromRect(cropRect));
  Size newSize;
  // Make the longest border exactly 512 pixels wide, preserving aspect ratio
  if (oldSize.height > oldSize.width) {
    newSize = Size(oldSize.width * 512 / oldSize.height, 512);
  } else {
    newSize = Size(512, oldSize.height * 512 / oldSize.width);
  }
  crop.addOption(
    ScaleOption(
      newSize.width.toInt(),
      newSize.height.toInt(),
    ),
  );
  crop.outputFormat = const OutputFormat.png(); // Ensure the format supports transparency
  final intermediate = (await ImageEditor.editImage(image: rawImageData, imageEditorOption: crop))!;

  final option = ImageMergeOption(
    canvasSize: const Size.square(512),
    format: const OutputFormat.webp_lossy(50),
  );

  option.addImage(
    MergeImageConfig(
      image: MemoryImageSource(intermediate),
      position: ImagePosition(
        Offset((512 - newSize.width) / 2, (512 - newSize.height) / 2),
        newSize,
      ),
    ),
  );
  return (await ImageMerger.mergeToMemory(option: option))!;
}

/// Stretches the image to a 1:1 (square) aspect ratio without cutting anything.
///
/// It automatically detects which axis is shorter and stretches it to match the
/// longer one, so the whole image is kept and the result is a perfect square.
/// The square is then fitted to the standard 512x512 sticker size.
Future<Uint8List> stretchStickerToSquare(
    Uint8List rawImageData, double rotation) async {
  final option = ImageEditorOption();

  // Apply the same rotation the user performed in the crop screen.
  final int rot = rotation.truncate();
  if (rot != 0) {
    option.addOption(RotateOption(rot));
  }

  // keepRatio: false stretches the shorter axis to fill the square canvas,
  // which is exactly "stretch to 1:1" (no cropping). The scale option also
  // fits the result onto the 512x512 sticker size.
  option.addOption(ScaleOption(512, 512, keepRatio: false));
  option.outputFormat = const OutputFormat.webp_lossy(50);
  return (await ImageEditor.editImage(image: rawImageData, imageEditorOption: option))!;
}

/// Adds a sticker to a sticker pack
/// Copies the file to the required place
///
/// If [index] is 30 it changes the tray icon.
void addToPack(StickerPack pack, int index, Uint8List data) {
  Directory("$packsDir/${pack.id}").createSync(recursive: true);
  File output;
  if (index == 30) {
    output = File("$packsDir/${pack.id}/tray_${DateTime.now().millisecondsSinceEpoch}.webp");
    output.writeAsBytesSync(data);
    pack.trayIcon = output.path;
  } else {
    output = File("$packsDir/${pack.id}/sticker_${index}_${DateTime.now().millisecondsSinceEpoch}.webp");
    output.writeAsBytesSync(data);
    if (index >= 0 && index < pack.stickers.length) {
      final oldSource = pack.stickers[index].source;
      pack.stickers[index].source = output.path;
      try {
        final oldFile = File(oldSource);
        if (oldFile.existsSync() && oldFile.path != output.path) {
          oldFile.deleteSync();
        }
      } on FileSystemException catch (_) {
        // The sticker may point at an imported or shared file that is no longer writable.
      }
    } else {
      pack.stickers.add(Sticker(output.path, ["❤"]));
    }
  }
  pack.onEdit();
  savePacks(packs);
  // Clear media cache after importing a sticker
  print("Clearing media cache");
  Directory(mediaCacheDir).list().listen((entry) => entry.delete());
}

Future<File> saveTemp(Uint8List data) async {
  File output = File("$mediaCacheDir/${DateTime.now().millisecondsSinceEpoch}.tmp.webp");
  await output.writeAsBytes(data);
  return output;
}
