import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/globals.dart';

class SelectStickerDialog extends StatelessWidget {
  const SelectStickerDialog({super.key, required this.callback});

  final void Function(Sticker) callback;

  @override
  Widget build(BuildContext context) {
    final stickers = packs.expand((p) => p.stickers).toList(growable: false);
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.chooseASticker),
      content: SizedBox(
        // The old 10000x10000 placeholder made the dialog ask the layout
        // engine for a massive viewport. Keep the same scrollable grid, but
        // bound it to the actual window so only visible cells are laid out.
        width: min(MediaQuery.sizeOf(context).width - 48, 640),
        height: min(MediaQuery.sizeOf(context).height * .7, 640),
        child: GridView.builder(
          itemCount: stickers.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    offset: const Offset(1, 1),
                    blurRadius: 3,
                    color: Theme.of(context).brightness == Brightness.light ? Colors.black26 : Colors.black12,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: CheckerPainter(context),
                  child: InkWell(
                    onTap: () {
                      callback(stickers[index]);
                      Navigator.of(context).pop();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(stickers[index].source),
                      width: double.infinity,
                      height: double.infinity,
                      cacheWidth: 256,
                      cacheHeight: 256,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.low,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
