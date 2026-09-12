import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';

import 'src/app.dart';
import 'src/settings/settings_controller.dart';
import 'src/settings/settings_service.dart';

Future<void> main() async {
  final sw = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();

  // Sticker lists decode many small thumbnails; keep them cached while
  // scrolling, but cap both count and bytes so a large library does not push
  // the Android process into memory pressure and trigger GC jank.
  PaintingBinding.instance.imageCache.maximumSize = 500;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 << 20;

  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(
      ['Google fonts'],
      'SIL Open Font License\n\n$license',
    );
  });

  final settingsService = SettingsService();
  final settingsTask = _loadSettings(settingsService);
  final packsTask = _loadPacks();

  // These operations are independent. The previous startup code waited on a
  // mutable task list twice, which serialized parts of initialization and
  // made the first frame needlessly dependent on the second wait.
  await Future.wait<Object?>([
    settingsTask,
    packsTask,
    createDirs(),
  ]);
  packs = await packsTask;

  debugPrint('Startup data ready: ${sw.elapsedMilliseconds}ms');

  // Keep the real home screen (with saved theme, locale and library) as the
  // first frame, not a splash that merely hides unfinished initialization.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('Startup first frame: ${sw.elapsedMilliseconds}ms');
    unawaited(_loadPackageInfo());
    unawaited(_reportReady());
  });
  runApp(StickersApp(settingsController: settingsController));
}

Future<void> _loadSettings(SettingsService service) async {
  await service.waitForInit();
  final controller = SettingsController(service);
  await controller.loadSettings();
  settingsController = controller;
}

Future<List<StickerPack>> _loadPacks() async {
  final documents = await getApplicationDocumentsDirectory();
  packsDir = '${documents.path}/packs';
  await Directory(packsDir).create(recursive: true);
  return getPacks();
}

Future<void> _loadPackageInfo() async {
  try {
    info = await PackageInfo.fromPlatform();
  } catch (error) {
    debugPrint('Package info unavailable: $error');
  }
}

Future<void> _reportReady() async {
  if (!Platform.isAndroid) return;
  try {
    await const MethodChannel('de.loicezt.stickers/methods').invokeMethod<void>('reportReady');
  } on PlatformException catch (error) {
    debugPrint('Startup metric unavailable: $error');
  }
}

Future<void> createDirs() async {
  final directory = await getApplicationCacheDirectory();
  cacheDir = '${directory.path}/cache';
  exportCacheDir = '$cacheDir/exported_packs';
  mediaCacheDir = '$cacheDir/media';
  fontsCacheDir = '$cacheDir/fonts';
  await Future.wait<void>([
    Directory(mediaCacheDir).create(recursive: true),
    Directory(exportCacheDir).create(recursive: true),
    Directory(fontsCacheDir).create(recursive: true),
  ]);
}
