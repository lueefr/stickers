import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/globals.dart';
import 'package:whatsapp_stickers_plus/whatsapp_stickers.dart';

class StickerPack {
  String title;
  String author;
  String id;
  String imageDataVersion;
  bool animated;
  String? publisherWebsite;
  String? privacyPolicyWebsite;
  String? licenseAgreementWebsite;
  List<Sticker> stickers;
  String? trayIcon;

  StickerPack(this.title, this.author, this.id, this.stickers, this.imageDataVersion, this.animated,
      {this.trayIcon, this.publisherWebsite, this.licenseAgreementWebsite, this.privacyPolicyWebsite});

  Future<void> sendToWhatsapp() async {
    if (stickers.isEmpty) throw Exception("No stickers!");

    ImageEditorOption scale = ImageEditorOption();
    scale.addOption(const ScaleOption(96, 96));
    scale.outputFormat = const OutputFormat.png();
    final File? scaledTray = await ImageEditor.editFileImageAndGetFile(
      file: File(trayIcon ?? stickers.first.source),
      imageEditorOption: scale,
    );
    if (scaledTray == null) {
      throw Exception("Could not prepare the tray image for WhatsApp");
    }
    // The tray icon has to live next to the stickers: WhatsApp reads it through
    // the content provider, which serves files by their path. The directory can
    // be missing when every other file of the pack was removed, and copying is
    // more forgiving than renaming onto an existing file.
    final directory = Directory("$packsDir/$id");
    if (!await directory.exists()) await directory.create(recursive: true);
    final File trayIconFile = await scaledTray.copy("$packsDir/$id/tray.png");
    // The scaled image is only a temporary file in the cache directory.
    if (await scaledTray.exists()) await scaledTray.delete();

    var stickerPack = WhatsappStickers(
      identifier: id,
      name: title,
      publisher: author,
      trayImageFileName: WhatsappStickerImage.fromFile(trayIconFile.path),
      imageDataVersion: imageDataVersion,
      publisherWebsite: publisherWebsite,
      privacyPolicyWebsite: privacyPolicyWebsite,
      licenseAgreementWebsite: licenseAgreementWebsite,
      animatedStickerPack: animated,
    );

    for (var sticker in stickers) {
      stickerPack.addSticker(sticker.getWhatsappStickerImage(), sticker.emojis);
    }

    debugPrint("Adding $title ($id)  v=$imageDataVersion to Whatsapp");
    await stickerPack.sendToWhatsApp();
  }

  void onEdit() {
    // Bump before saving: savePacks() serialises the pack synchronously, so
    // the new version has to be in place while the JSON is built. Saving
    // first would persist the previous imageDataVersion, and WhatsApp refuses
    // to refresh a pack whose version it has already seen — the replaced
    // sticker would never show up.
    imageDataVersion = (int.parse(imageDataVersion) + 1).toString();
    savePacks(packs);
  }

  Map<String, Object?> toJson() {
    return {
      "id": id,
      "title": title,
      "author": author,
      "imageDataVersion": imageDataVersion,
      "animated": animated,
      "stickers": stickers.map((sticker) => sticker.toJson()).toList(),
      "trayIcon": trayIcon,
      "publisherWebsite": publisherWebsite,
      "privacyPolicyWebsite": privacyPolicyWebsite,
      "licenseAgreementWebsite": licenseAgreementWebsite,
    };
  }

  factory StickerPack.fromJson(Map<String, dynamic> json) {
    return StickerPack(
      json["title"],
      json["author"],
      json["id"],
      (json["stickers"] as List).map((sticker) => Sticker.fromJson(sticker)).toList(),
      json["imageDataVersion"],
      json["animated"] ?? false,
      trayIcon: json["trayIcon"],
      publisherWebsite: json["publisherWebsite"],
      privacyPolicyWebsite: json["privacyPolicyWebsite"],
      licenseAgreementWebsite: json["licenseAgreementWebsite"],
    );
  }

  void setTray(String source) {
    Directory parent = Directory("$packsDir/$id/");
    File output = File("$packsDir/$id/tray_${DateTime.now().millisecondsSinceEpoch}.webp");
    if (!parent.existsSync()) parent.createSync(recursive: true);
    File(source).copySync(output.path);
    trayIcon = output.path;
  }
}
