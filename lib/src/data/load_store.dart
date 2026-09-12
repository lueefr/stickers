import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

/// Alpha value (of 255) from which a pixel counts as visible content.
///
/// The alpha plane of a lossy WebP is stored losslessly, so the transparent
/// margin of a sticker keeps a hard 0 and a low threshold is enough to tell it
/// apart from the content.
const int _visibleAlpha = 8;

/// Width, in pixels, of the preview the visible content is measured on.
///
/// Small enough to stay cheap for a multi-megapixel photo, and large enough to
/// place the boundaries of a 512x512 sticker exactly.
const int _contentPreviewWidth = 512;

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
    final source = await input.readAsString();
    // Small libraries are cheaper inline; large ones must not monopolize the
    // UI isolate while decoding JSON and allocating thousands of stickers.
    return source.length < 64 * 1024
        ? decodePacks(source)
        : compute(decodePacks, source, debugLabel: 'decode sticker library');
  }
  return List.empty(growable: true);
}

@visibleForTesting
List<StickerPack> decodePacks(String source) =>
    (jsonDecode(source) as List).map((json) => StickerPack.fromJson(json)).toList();

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

/// Stretches [region] of the image to a 1:1 (square) aspect ratio without
/// cutting anything away.
///
/// The shorter axis of the region is stretched to match the longer one, so the
/// whole region is kept and the result fills the standard 512x512 sticker canvas
/// (unlike [cropSticker], which cuts and centers what is left).
///
/// [region] is given in pixels of the image after [rotation] has been applied,
/// which is the space the crop screen reports its crop box in, or `null` to
/// stretch the whole image (what a photo that is not a sticker yet needs).
Future<Uint8List> stretchStickerToSquare(
    Uint8List rawImageData, double rotation, [Rect? region]) async {
  final option = ImageEditorOption();

  // Apply the same rotation the user performed in the crop screen, and clip
  // before scaling: [region] belongs to the rotated image.
  final int rot = rotation.truncate();
  if (rot != 0) {
    option.addOption(RotateOption(rot));
  }
  if (region != null) {
    option.addOption(ClipOption.fromRect(region));
  }

  // keepRatio: false stretches the shorter axis to fill the square canvas,
  // which is exactly "stretch to 1:1" (no cropping). The scale option also
  // fits the result onto the 512x512 sticker size.
  option.addOption(const ScaleOption(512, 512, keepRatio: false));
  option.outputFormat = const OutputFormat.webp_lossy(50);
  return (await ImageEditor.editImage(image: rawImageData, imageEditorOption: option))!;
}

/// The area of the sticker that [stretchStickerToSquare] should fill the square
/// with, in pixels of the rotated image, or `null` when there is nothing to
/// stretch.
///
/// [cropRect] is the crop box of the crop screen (`null` when there is none) and
/// [imageSize] the size of the image before [rotation] was applied.
///
/// A box the user narrowed wins, so a manual crop is respected. A box that still
/// covers the whole image means the user did not select anything: stickers are
/// stored on a square canvas with transparent margins around their content, and
/// stretching that whole canvas changes nothing at all — which is why the
/// visible content of the image is stretched instead in that case.
Future<Rect?> stretchRegion(
    Uint8List rawImageData, Size imageSize, {Rect? cropRect, double rotation = 0}) async {
  final int degrees = rotation.truncate();
  final Size rotated = rotatedImageSize(imageSize, degrees);
  if (rotated.isEmpty) return null;

  // The image editor refuses a clip that is empty or that reaches outside of the
  // image, and a fraction of a pixel of margin is not worth a crash: every
  // region is snapped to whole pixels inside the rotated image.
  final int width = rotated.width.floor();
  final int height = rotated.height.floor();
  if (width < 1 || height < 1) return null;

  // A box the user narrowed wins, so a manual crop is respected.
  if (cropRect != null && !_coversWholeImage(cropRect, rotated)) {
    return _toPixelRegion(cropRect, width, height);
  }

  // Rotations that are not quarter turns (the "+1°"/"-1°" buttons) resize the
  // canvas by an amount that is not worth predicting, so only the whole image is
  // stretched in that case.
  if (degrees % 90 != 0) return null;

  final Rect? content = await visibleContentBounds(rawImageData, rotation);
  if (content == null) return null;
  return _toPixelRegion(
    Rect.fromLTRB(content.left * width, content.top * height, content.right * width,
        content.bottom * height),
    width,
    height,
  );
}

/// Snaps [rect], in pixels of the rotated image, to whole pixels that lie inside
/// a [width]x[height] image, so that it can be used as a clip region.
Rect _toPixelRegion(Rect rect, int width, int height) {
  int left = rect.left.floor();
  int top = rect.top.floor();
  int right = rect.right.ceil();
  int bottom = rect.bottom.ceil();
  if (left < 0) left = 0;
  if (top < 0) top = 0;
  if (left > width - 1) left = width - 1;
  if (top > height - 1) top = height - 1;
  if (right > width) right = width;
  if (bottom > height) bottom = height;
  if (right <= left) right = left + 1;
  if (bottom <= top) bottom = top + 1;
  return Rect.fromLTRB(left.toDouble(), top.toDouble(), right.toDouble(), bottom.toDouble());
}

/// Bounding box of the visible (non transparent) part of [rawImageData], as
/// fractions of the image size (0..1), or `null` when there is nothing to trim:
/// a fully transparent image, one whose content already covers it, or one that
/// cannot be decoded.
///
/// [rotation] is the rotation the crop screen applied (degrees, clockwise), so
/// that the result can be used on the rotated image the editor produces.
Future<Rect?> visibleContentBounds(Uint8List rawImageData, [double rotation = 0]) async {
  final int degrees = rotation.truncate();
  if (degrees % 360 == 0) {
    // Nothing to rotate: measure on the file itself. Only a small preview is
    // decoded, which keeps even a 12 megapixel photo cheap.
    return _contentBounds(rawImageData, _contentPreviewWidth);
  }

  // Rotate a proportionally downscaled copy and measure on that: fractions of
  // the image survive the resize, and the rotation makes sure the content ends
  // up where the rotated image puts it.
  final option = ImageEditorOption();
  option.addOption(RotateOption(degrees));
  option.addOption(const ScaleOption(_contentPreviewWidth, _contentPreviewWidth, keepRatio: true));
  option.outputFormat = const OutputFormat.png();
  try {
    final Uint8List? preview = await ImageEditor.editImage(image: rawImageData, imageEditorOption: option);
    if (preview == null) return null;
    return await _contentBounds(preview, null);
  } catch (_) {
    // Failing to measure only costs the trim, the stretch itself still works.
    return null;
  }
}

/// Bounds of the opaque pixels of [encoded], in fractions of the image size, or
/// `null` when the image has no visible content or is covered by it.
///
/// [targetWidth] bounds the size of the decoded image, so that measuring a big
/// photo does not cost a full size bitmap.
Future<Rect?> _contentBounds(Uint8List encoded, int? targetWidth) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(encoded, targetWidth: targetWidth, allowUpscaling: false);
    image = (await codec.getNextFrame()).image;
    final int width = image.width;
    final int height = image.height;
    if (width <= 0 || height <= 0) return null;
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final Uint8List pixels = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    int left = width;
    int top = height;
    int right = -1;
    int bottom = -1;
    for (int y = 0; y < height; y++) {
      // The alpha byte of the first pixel of this row.
      int alpha = y * width * 4 + 3;
      for (int x = 0; x < width; x++, alpha += 4) {
        if (pixels[alpha] < _visibleAlpha) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    // Every pixel transparent: there is no content to stretch.
    if (right < 0) return null;

    final Rect bounds =
        Rect.fromLTRB(left / width, top / height, (right + 1) / width, (bottom + 1) / height);
    // The content already covers the image: there is nothing to trim.
    return bounds.width >= .999 && bounds.height >= .999 ? null : bounds;
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

/// Size of the canvas the image editor produces after rotating [size] by
/// [degrees], i.e. the bounding box of the rotated image.
///
/// Quarter turns, the only angles [stretchRegion] maps, are exact.
Size rotatedImageSize(Size size, int degrees) {
  final double radians = degrees * math.pi / 180;
  final double cosine = math.cos(radians).abs();
  final double sine = math.sin(radians).abs();
  return Size(
    size.width * cosine + size.height * sine,
    size.width * sine + size.height * cosine,
  );
}

/// Whether [rect] still covers all of [size], i.e. whether the crop box was left
/// untouched (a rounded box a pixel off still counts as untouched).
bool _coversWholeImage(Rect rect, Size size) {
  const double tolerance = .01;
  return rect.left <= size.width * tolerance &&
      rect.top <= size.height * tolerance &&
      rect.right >= size.width * (1 - tolerance) &&
      rect.bottom >= size.height * (1 - tolerance);
}

/// Adds a sticker to a sticker pack
/// Copies the file to the required place
///
/// If [index] is 30 it changes the tray icon.
///
/// Async on purpose: synchronous file I/O here would block the UI thread and
/// drop frames right when the editor closes.
Future<void> addToPack(StickerPack pack, int index, Uint8List data) async {
  final dir = await Directory("$packsDir/${pack.id}").create(recursive: true);
  late final File output;
  if (index == 30) {
    output = File("${dir.path}/tray_${DateTime.now().millisecondsSinceEpoch}.webp");
    await output.writeAsBytes(data);
    pack.trayIcon = output.path;
  } else {
    output = File("${dir.path}/sticker_${index}_${DateTime.now().millisecondsSinceEpoch}.webp");
    await output.writeAsBytes(data);
    if (index >= 0 && index < pack.stickers.length) {
      final oldSource = pack.stickers[index].source;
      pack.stickers[index].source = output.path;
      try {
        final oldFile = File(oldSource);
        if (await oldFile.exists() && oldFile.path != output.path) {
          await oldFile.delete();
        }
      } on FileSystemException catch (_) {
        // The sticker may point at an imported or shared file that is no longer writable.
      }
    } else {
      pack.stickers.add(Sticker(output.path, ["❤"]));
    }
  }
  pack.onEdit();
  await savePacks(packs);
  // Clear media cache after importing a sticker
  debugPrint("Clearing media cache");
  unawaited(_clearMediaCache());
}

Future<void> _clearMediaCache() async {
  try {
    await for (final entry in Directory(mediaCacheDir).list()) {
      try {
        await entry.delete();
      } on FileSystemException catch (_) {}
    }
  } on FileSystemException catch (_) {}
}

Future<File> saveTemp(Uint8List data) async {
  File output = File("$mediaCacheDir/${DateTime.now().millisecondsSinceEpoch}.tmp.webp");
  await output.writeAsBytes(data);
  return output;
}
