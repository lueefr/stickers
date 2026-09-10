import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/delete_confirm_dialog.dart';
import 'package:stickers/src/dialogs/edit_pack_dialog.dart';
import 'package:stickers/src/dialogs/edit_sticker_dialog.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/dialogs/select_sticker_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/video/gif_to_webp.dart';
import 'package:stickers/src/util.dart';

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
                            : CustomPaint(
                                painter: CheckerPainter(context),
                                child: GestureDetector(
                                  child: Image.file(
                                    File(widget.pack.stickers[index].source),
                                    width: double.infinity,
                                    height: double.infinity,
                                    cacheWidth: 256,
                                    cacheHeight: 256,
                                    gaplessPlayback: true,
                                    fit: BoxFit.contain,
                                  ),
                                  onTap: () {
                                    showDialog<String>(
                                      context: context,
                                      builder: ((context) => EditStickerDialog(widget.pack, index)),
                                    ).then(
                                      (action) {
                                        if (action == "edit") {
                                          // The dialog can rebuild (or drop) this grid cell
                                          // while it is open, so navigate from the page's own
                                          // context instead of the cell one.
                                          if (!mounted) return;
                                          Navigator.of(this.context)
                                              .pushNamed(
                                                "/edit",
                                                arguments: EditArguments(
                                                  pack: widget.pack,
                                                  index: index,
                                                  mediaPath: widget.pack.stickers[index].source,
                                                  popCount: 1,
                                                ),
                                              )
                                              .then((_) => setState(() {}));
                                        } else {
                                          setState(() {});
                                        }
                                      },
                                    );
                                  },
                                ),
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

  Future<void> _showStaticStickerOptions(int index) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: Text("New image"),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndEditSingleImage(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.collections),
              title: Text("Multiple images"),
              subtitle: Text("Edit them one at a time"),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndEditMultipleImages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_fix_high),
              title: Text("Start with existing sticker"),
              onTap: () {
                Navigator.of(context).pop();
                _startWithExistingSticker();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAnimatedStickerOptions(int index) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_library),
              title: Text("Video"),
              subtitle: Text("Trim, crop and rotate"),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndEditVideo(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.gif_box),
              title: Text("GIF"),
              subtitle: Text("Create an animated sticker from a GIF"),
              onTap: () {
                Navigator.of(context).pop();
                _pickGif(index);
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

  Future<void> _pickAndEditVideo(int index) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        "/crop_video",
        arguments: EditArguments(
          pack: widget.pack,
          index: index,
          mediaPath: video.path,
        ),
      ).then((value) => setState(() {}));
    } on Exception catch (e) {
      _showLoadError(e);
    }
  }

  Future<void> _pickGif(int index) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ["gif"],
      );
      if (file == null || file.path == null) return;
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text("Creating animated sticker...")),
            ],
          ),
        ),
      );
      final service = GifToWebPService();
      Uint8List? best;
      double quality = 60;
      int fps = 12;
      for (var attempt = 0; attempt < 3; attempt++) {
        final output = "$mediaCacheDir/gif_${DateTime.now().millisecondsSinceEpoch}_$attempt.webp";
        await service.convert(
          inputFile: file.path!,
          outputFile: output,
          quality: quality,
          fps: fps,
        );
        final data = await File(output).readAsBytes();
        best = data;
        if (data.lengthInBytes / 1024 < 500) break;
        quality -= 20;
        fps = max<int>(6, (fps * .75).round());
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      if (best == null) return;
      if (best.lengthInBytes / 1024 > 500) {
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
      await addToPack(widget.pack, index, best);
      if (!mounted) return;
      setState(() {});
    } on Exception catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
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
