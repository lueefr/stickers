import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/edit_sticker_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/sticker_pack_page.dart';

/// 1x1 transparent PNG, just so Image.file has something to decode.
const String _kPng1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAgAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

void main() {
  late Directory tmp;
  late File stickerFile;
  late StickerPack pack;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sticker_sheet_test');
    stickerFile = File('${tmp.path}/sticker_0.webp');
    await stickerFile.writeAsBytes(base64Decode(_kPng1x1));
    pack = StickerPack('test pack', 'author', 'pack_test', [Sticker(stickerFile.path, ['❤'])], '1', false);
    // onEdit() -> savePacks() touches these globals.
    packs = [pack];
    packsDir = tmp.path;
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  MaterialApp app({Widget? home, RouteFactory? onGenerateRoute}) {
    return MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
      onGenerateRoute: onGenerateRoute,
    );
  }

  testWidgets('tapping a sticker shows the edit sheet with all actions', (tester) async {
    await tester.pumpWidget(app(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => EditStickerDialog.show(context, pack, 0),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The widget must actually be visible on screen (the reported bug was
    // "barrier dims but nothing renders").
    expect(find.text('Edit sticker'), findsOneWidget);
    expect(find.text('Associated emojis'), findsOneWidget);
    expect(find.text('Delete sticker'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('edit action on the pack page routes to /crop with the sticker source', (tester) async {
    String? pushedRoute;
    EditArguments? args;
    await tester.pumpWidget(app(
      onGenerateRoute: (settings) {
        if (settings.name == '/crop') {
          pushedRoute = settings.name;
          args = settings.arguments as EditArguments;
          return MaterialPageRoute(builder: (_) => const Scaffold(body: Text('crop page')));
        }
        return MaterialPageRoute(builder: (_) => StickerPackPage(pack, () {}));
      },
    ));
    await tester.pumpAndSettle();

    // Tap the sticker cell (the only Image in the grid).
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.text('Edit sticker'), findsOneWidget);

    // The sheet's Edit button (the app bar also has one, so pick the last).
    await tester.tap(find.byIcon(Icons.edit).last);
    await tester.pumpAndSettle();

    expect(pushedRoute, '/crop');
    expect(args, isNotNull);
    expect(args!.index, 0);
    expect(args!.mediaPath, stickerFile.path);
    expect(find.text('crop page'), findsOneWidget);
  });

  testWidgets('done saves the emojis over the sticker', (tester) async {
    String? result = 'sentinel';
    await tester.pumpWidget(app(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => EditStickerDialog.show(context, pack, 0).then((r) => result = r),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '🔥');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(pack.stickers.single.emojis, ['🔥']);
    expect(result, isNull);
  });

  testWidgets('delete removes the sticker from the pack', (tester) async {
    await tester.pumpWidget(app(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => EditStickerDialog.show(context, pack, 0),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete sticker'));
    await tester.pumpAndSettle();

    expect(pack.stickers, isEmpty);
  });
}
