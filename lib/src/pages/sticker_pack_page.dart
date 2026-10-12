import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/create_pack_dialog.dart';
import 'package:stickers/src/dialogs/delete_confirm_dialog.dart';
import 'package:stickers/src/dialogs/edit_pack_dialog.dart';
import 'package:stickers/src/dialogs/edit_sticker_dialog.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/dialogs/select_sticker_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/video/common.dart';
import 'package:stickers/src/video/gif_to_webp.dart';
import 'package:stickers/src/video/media_sources.dart';
import 'package:stickers/src/util.dart';
import 'package:stickers/src/widgets/sticker_thumbnail.dart';
import 'package:stickers/src/widgets/toast.dart';

class StickerPackPage extends StatefulWidget {
  final StickerPack pack;
  final Function deleteCallback;

  const StickerPackPage(this.pack, this.deleteCallback, {super.key});

  static const routeName = "/pack";

  @override
  State<StickerPackPage> createState() => StickerPackPageState();
}

class StickerPackPageState extends State<StickerPackPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cellColor = Color.lerp(theme.colorScheme.primary, theme.colorScheme.surface, .7);
    final shadowColor = theme.brightness == Brightness.light ? Colors.black26 : Colors.black12;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: DefaultSliverActivity(
              actions: [
                IconButton(
                  tooltip: AppLocalizations.of(context)!.edit,
                  onPressed: () {
                    showDialog(context: context, builder: (context) => EditPackDialog(widget.pack))
                        .then((value) => setState(() {}));
                  },
                  icon: const Icon(Icons.edit),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context)!.delete,
                  onPressed: () {
                    showDialog<bool>(
                        context: context,
                        builder: (context) => DeleteConfirmDialog(widget.pack.title)).then(
                      (value) async {
                        if (value == true) {
                          packs.remove(widget.pack);
                          widget.deleteCallback();
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                          Directory("$packsDir/${widget.pack.id}").delete(recursive: true);
                          savePacks(packs);
                        }
                      },
                    );
                  },
                  icon: const Icon(Icons.delete),
                ),
              ],
              title: widget.pack.title,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: GridView.builder(
                    itemCount: widget.pack.stickers.length + 1,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: colCount(MediaQuery.of(context).size.width),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemBuilder: (context, index) {
                      if (index == widget.pack.stickers.length) {
                        bool disabled = widget.pack.stickers.length >= 30;
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: disabled ? Colors.grey : Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: disabled ? null : () => _createSticker(index),
                            child: Icon(
                              Icons.add,
                              size: 40,
                              color: disabled ? Colors.grey : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        );
                      }
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: cellColor,
                          boxShadow: [
                            BoxShadow(
                              offset: const Offset(1, 1),
                              blurRadius: 3,
                              color: shadowColor,
                            )
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: index >= widget.pack.stickers.length
                            ? null
                            : StickerThumbnail(
                                widget.pack.stickers[index].source,
                                cacheWidth: 256,
                                cacheHeight: 256,
                                onTap: () {
                                  EditStickerDialog.show(context, widget.pack, index).then(
                                    (action) {
                                      // The sheet can rebuild (or drop) this grid cell
                                      // while it is open, so navigate from the page's own
                                      // context instead of the cell one.
                                      if (!mounted) return;
                                      switch (action) {
                                        case StickerSheetAction.edit:
                                          // Go through the crop screen first; the final save
                                          // (addToPack) replaces the sticker at `index`
                                          // in-place, overwriting the edited sticker.
                                          Navigator.of(this.context)
                                              .pushNamed(
                                                "/crop",
                                                arguments: EditArguments(
                                                  pack: widget.pack,
                                                  index: index,
                                                  mediaPath: widget.pack.stickers[index].source,
                                                ),
                                              )
                                              .then((_) => setState(() {}));
                                        case StickerSheetAction.replace:
                                          // New media in the very same slot: the position
                                          // and the emojis of the sticker are kept.
                                          _replaceSticker(index);
                                        case null:
                                          // Dismissed, emojis saved or sticker deleted.
                                          setState(() {});
                                      }
                                    },
                                  );
                                },
                              ),
                      );
                    }),
              ),
            ),
          ),
          Material(
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.pack.stickers.length < 3)
                    Opacity(
                      opacity: .7,
                      child: Text(
                        AppLocalizations.of(context)!.youNeedAtLeast3Stickers,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (widget.pack.stickers.length >= 30)
                    Opacity(
                      opacity: .7,
                      child: Text(
                        AppLocalizations.of(context)!.youCanTHaveMoreThan30Stickers,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.share),
                        onPressed: () {
                          exportPack(widget.pack);
                        },
                        label: Text(AppLocalizations.of(context)!.export),
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: widget.pack.stickers.length < 3
                              ? null
                              : () => sendToWhatsappWithErrorHandling(widget.pack, context),
                          child: Text(AppLocalizations.of(context)!.addToWhatsapp),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _createSticker(int index) async {
    if (widget.pack.animated) {
      await _showAnimatedStickerOptions(index);
    } else {
      await _showStaticStickerOptions(index);
    }
  }

  /// Puts new media in the slot currently used by the sticker at [index].
  ///
  /// Every editor in the chain is handed the index of the sticker being
  /// replaced, so the final save (addToPack) overwrites that sticker instead
  /// of appending a new one — its position in the pack and its emojis stay
  /// untouched.
  Future<void> _replaceSticker(int index) async {
    if (index < 0 || index >= widget.pack.stickers.length) return;
    if (widget.pack.animated) {
      // An animated sticker is a video/GIF, so offer those sources again.
      await _showAnimatedStickerOptions(index);
    } else {
      await _pickAndEditSingleImage(index);
    }
  }

  Future<void> _showStaticStickerOptions(int index) async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: Text(l10n.newImage),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndEditSingleImage(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.collections),
              title: Text(l10n.multipleImages),
              subtitle: Text(l10n.multipleImagesHint),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndEditMultipleImages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_fix_high),
              title: Text(l10n.startWithExistingSticker),
              onTap: () {
                Navigator.of(context).pop();
                _startWithExistingSticker();
              },
            ),
            const Divider(height: 1),
            // A static pack cannot hold video or GIF stickers: WhatsApp only
            // accepts media of the kind the pack was created for, and it
            // refuses the whole pack otherwise. The sources are offered here
            // anyway so a video or a GIF can be turned into a sticker without
            // the user having to know that it needs an animated pack.
            ListTile(
              leading: const Icon(Icons.video_library),
              title: Text(l10n.video),
              subtitle: Text(l10n.videoHint),
              onTap: () {
                Navigator.of(context).pop();
                _createAnimatedPackFor(_pickAndEditVideo);
              },
            ),
            ListTile(
              leading: const Icon(Icons.gif_box),
              title: Text(l10n.gif),
              subtitle: Text(l10n.gifHint),
              onTap: () {
                Navigator.of(context).pop();
                _createAnimatedPackFor(_pickGif);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Asks for the animated pack a video or a GIF sticker has to live in and
  /// runs [start] on it.
  ///
  /// WhatsApp refuses a pack that mixes static and animated stickers, so a
  /// video or a GIF picked from a static pack cannot be added to it. Instead of
  /// hiding those sources (the video/GIF flows then looked broken) the app asks
  /// for the animated pack that will hold the sticker, and the new pack is shown
  /// when the sticker is in it.
  Future<void> _createAnimatedPackFor(Future<void> Function(StickerPack pack, int index) start) async {
    final created = await showDialog<StickerPack?>(
      context: context,
      builder: (context) => CreatePackDialog(packs, initialAnimated: true),
    );
    if (created == null || !mounted) return;
    // Persist the new pack right away: adding the sticker saves the packs
    // again, but the user can also cancel the picker and still keep the pack.
    await savePacks(packs);
    await start(created, 0);
    if (!mounted) return;
    setState(() {});
    if (created.stickers.isEmpty) return;
    // The sticker went to a pack the user is not looking at: show it, so the
    // result of the flow is visible.
    await Navigator.of(context).pushNamed("/pack", arguments: created);
    if (mounted) setState(() {});
  }

  Future<void> _showAnimatedStickerOptions(int index) async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_library),
              title: Text(l10n.video),
              subtitle: Text(l10n.videoHint),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndEditVideo(widget.pack, index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.gif_box),
              title: Text(l10n.gif),
              subtitle: Text(l10n.gifHint),
              onTap: () {
                Navigator.of(context).pop();
                _pickGif(widget.pack, index);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndEditSingleImage(int index) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        "/crop",
        arguments: EditArguments(
          pack: widget.pack,
          index: index,
          mediaPath: image.path,
        ),
      ).then((value) => setState(() {}));
    } on Exception catch (e) {
      _showLoadError(e);
    }
  }

  Future<void> _pickAndEditMultipleImages() async {
    try {
      final ImagePicker picker = ImagePicker();
      final images = await picker.pickMultiImage();
      if (images.isEmpty) return;
      for (final image in images) {
        if (!mounted) return;
        if (widget.pack.stickers.length >= 30) break;
        await Navigator.pushNamed(
          context,
          "/crop",
          arguments: EditArguments(
            pack: widget.pack,
            index: widget.pack.stickers.length,
            mediaPath: image.path,
          ),
        );
        if (mounted) setState(() {});
      }
    } on Exception catch (e) {
      _showLoadError(e);
    }
  }

  Future<void> _startWithExistingSticker() async {
    showDialog(
      context: context,
      builder: (_) => SelectStickerDialog(callback: (sticker) {
        Future.microtask(() {
          if (!mounted || widget.pack.stickers.length >= 30) return;
          Navigator.of(context)
              .pushNamed(
                "/edit",
                arguments: EditArguments(
                  pack: widget.pack,
                  index: widget.pack.stickers.length,
                  mediaPath: sticker.source,
                  popCount: 1,
                ),
              )
              .then((_) => setState(() {}));
        });
      }),
    );
  }

  /// Lets the user pick a video and trim it into the sticker slot [index] of
  /// [pack].
  ///
  /// The pack is a parameter (and not always [widget.pack]) because a video
  /// can also be picked from a static pack, in which case the caller first
  /// creates the animated pack that will hold the sticker.
  Future<void> _pickAndEditVideo(StickerPack pack, int index) async {
    try {
      final String? videoPath = await StickerMediaSources.instance.pickVideo();
      if (videoPath == null) return;
      if (!mounted) return;
      await Navigator.pushNamed(
        context,
        "/crop_video",
        arguments: EditArguments(
          pack: pack,
          index: index,
          mediaPath: videoPath,
          // The video and the GIF flows end in their own editor, which pops
          // itself; this page must stay on the stack until they are done.
          popCount: 0,
        ),
      );
      if (mounted) setState(() {});
    } on Exception catch (e) {
      _showLoadError(e);
    }
  }

  /// Lets the user pick a GIF and converts it into the sticker slot [index] of
  /// [pack].
  ///
  /// The pack is a parameter for the same reason as in [_pickAndEditVideo].
  Future<void> _pickGif(StickerPack pack, int index) async {
    // Whether the blocking progress dialog is on screen and still has to be
    // dismissed. It is tracked explicitly: popping "the top route" after a
    // failure would otherwise close this very page (it is a pushed route too).
    var progressShown = false;
    try {
      final String? gifPath = await StickerMediaSources.instance.pickGif();
      if (gifPath == null) return;
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(AppLocalizations.of(context)!.creatingAnimatedSticker)),
            ],
          ),
        ),
      );
      progressShown = true;
      // The cache directory can be wiped by the OS at any time without the app
      // restarting, so make sure it is there before writing into it.
      await ensureMediaCacheDir();
      final service = GifToWebPService();
      Uint8List? best;
      double quality = 60;
      int fps = 12;
      // Length of the GIF itself. A GIF longer than WhatsApp's limit is cut to
      // it by the converter (a longer sticker would make WhatsApp refuse the
      // pack), and the user is told that only a part of it became a sticker.
      var sourceDurationMs = 0;
      for (var attempt = 0; attempt < 3; attempt++) {
        final output = "$mediaCacheDir/gif_${DateTime.now().millisecondsSinceEpoch}_$attempt.webp";
        final reportedDurationMs = await service.convert(
          inputFile: gifPath,
          outputFile: output,
          quality: quality,
          fps: fps,
        );
        if (sourceDurationMs == 0 && reportedDurationMs > 0) sourceDurationMs = reportedDurationMs;
        final data = await File(output).readAsBytes();
        best = data;
        // WhatsApp's own limit for an animated sticker.
        if (data.lengthInBytes <= maxAnimatedStickerBytes) break;
        quality -= 20;
        fps = max<int>(6, (fps * .75).round());
      }
      if (!mounted) return;
      // Dismiss the progress dialog: the conversion (not the page) is done.
      if (progressShown) {
        progressShown = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (best == null) return;
      if (best.lengthInBytes > maxAnimatedStickerBytes) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.stickerTooLarge),
            content: Text(AppLocalizations.of(context)!.stickerTooLargeMsg),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(AppLocalizations.of(context)!.ok)),
            ],
          ),
        );
        return;
      }
      await addToPack(pack, index, best);
      if (!mounted) return;
      setState(() {});
      final l10n = AppLocalizations.of(context)!;
      final prefix = sourceDurationMs > maxAnimatedStickerDurationMs
          ? l10n.gifTrimmedToLimit(maxAnimatedStickerDurationMs ~/ 1000)
          : "";
      showToast("$prefix${l10n.animatedStickerReadyToSend}");
    } on Exception catch (e) {
      // Only the progress dialog may be closed here; this page has to stay.
      if (mounted && progressShown) {
        progressShown = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showLoadError(e);
    }
  }

  void _showLoadError(Object e) {
    if (mounted) {
      showDialog(
          context: context,
          builder: (context) {
            return ErrorDialog(
              title: AppLocalizations.of(context)!.couldntLoadMedia,
              message: e.toString(),
            );
          });
    }
  }

}
