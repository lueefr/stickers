import 'dart:io';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/delete_confirm_dialog.dart';
import 'package:stickers/src/dialogs/edit_pack_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/sticker_pack_page.dart';

class StickerPackPreviewCard extends StatefulWidget {
  final StickerPack pack;
  final Function deleteCallback;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelectionChanged;
  final VoidCallback? onLongPress;

  const StickerPackPreviewCard(
    this.pack,
    this.deleteCallback, {
    super.key,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
    this.onLongPress,
  });

  @override
  State<StickerPackPreviewCard> createState() => _StickerPackPreviewCardState();
}

class _StickerPackPreviewCardState extends State<StickerPackPreviewCard> {
  @override
  Widget build(BuildContext context) {
    final Color surface = ElevationOverlay.applySurfaceTint(
      Theme.of(context).colorScheme.surface,
      Theme.of(context).colorScheme.primary,
      2,
    );

    if (widget.selectionMode) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Card(
          color: widget.selected ? Theme.of(context).colorScheme.primaryContainer : surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onSelectionChanged,
            onLongPress: widget.onLongPress,
            child: _buildContent(context, showCheckbox: true),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: OpenContainer(
        closedColor: surface,
        openColor: Theme.of(context).colorScheme.surface,
        middleColor: surface,
        closedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        closedBuilder: (context, action) => GestureDetector(
          onLongPress: widget.onLongPress,
          // Provide our own (transparent) Material so the ListTile and the
          // IconButtons inside always have a Material ancestor, no matter in
          // which part of the container-transform tree the card is rebuilt.
          // Fixes "No Material widget found. ListTile widgets require a
          // Material widget ancestor" crashes on the packs list.
          child: Material(
            type: MaterialType.transparency,
            child: _buildContent(context),
          ),
        ),
        openBuilder: (BuildContext context, void Function({Object? returnValue}) action) =>
            StickerPackPage(widget.pack, widget.deleteCallback),
      ),
    );
  }

  Widget _buildContent(BuildContext context, {bool showCheckbox = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(widget.pack.title),
          subtitle: Opacity(
            opacity: .8,
            child: Text(widget.pack.author),
          ),
          leading: widget.pack.stickers.isEmpty
              ? (showCheckbox ? Checkbox(value: widget.selected, onChanged: (_) => widget.onSelectionChanged?.call()) : null)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showCheckbox)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Checkbox(value: widget.selected, onChanged: (_) => widget.onSelectionChanged?.call()),
                      ),
                    Container(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: [
                        BoxShadow(
                          offset: Offset(1, 1),
                          blurRadius: 3,
                          color: Theme.of(context).brightness == Brightness.light ? Colors.black26 : Colors.black12,
                        )
                      ]),
                      clipBehavior: Clip.antiAlias,
                      child: CustomPaint(
                        painter: CheckerPainter(context),
                        child: Image.file(
                          File(widget.pack.trayIcon ?? widget.pack.stickers.first.source),
                          width: 48,
                          height: 48,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
          trailing: showCheckbox
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        tooltip: AppLocalizations.of(context)!.edit,
                        icon: const Icon(Icons.edit),
                        onPressed: () {
                          showDialog(context: context, builder: (context) => EditPackDialog(widget.pack)).then(
                            (_) => setState(() {}),
                          );
                        }),
                    IconButton(
                      tooltip: AppLocalizations.of(context)!.delete,
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        showDialog<bool>(context: context, builder: (context) => DeleteConfirmDialog(widget.pack.title))
                            .then(
                          (value) async {
                            if (value == true) {
                              packs.remove(widget.pack);
                              widget.deleteCallback();
                              Directory("$packsDir/${widget.pack.id}").delete(recursive: true);
                              savePacks(packs);
                            }
                          },
                        );
                      },
                    ),
                  ],
                ),
        ),
        Container(
          height: 100,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: ListView.builder(
            shrinkWrap: true,
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              var sticker = widget.pack.stickers[index];
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(defaultBorderRadius), boxShadow: [
                    BoxShadow(
                      offset: Offset(1, 1),
                      blurRadius: 3,
                      color: Theme.of(context).brightness == Brightness.light ? Colors.black26 : Colors.black12,
                    )
                  ]),
                  clipBehavior: Clip.antiAlias,
                  child: CustomPaint(
                    painter: CheckerPainter(context),
                    child: Image.file(
                      File(sticker.source),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              );
            },
            itemCount: widget.pack.stickers.length,
          ),
        ),
      ],
    );
  }
}
