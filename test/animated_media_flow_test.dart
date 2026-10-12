import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/sticker_pack_page.dart';
import 'package:stickers/src/video/media_sources.dart';

/// 1x1 transparent PNG, just so Image.file has something to decode.
const String _kPng1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAgAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

/// Stands in for the platform pickers, which cannot run in a widget test.
class _FakeMediaSources implements StickerMediaSources {
  _FakeMediaSources({this.videoPath, this.gifPath});

  final String? videoPath;
  final String? gifPath;
  int videoPicks = 0;
  int gifPicks = 0;

  @override
  Future<String?> pickVideo() async {
    videoPicks++;
    return videoPath;
  }

  @override
  Future<String?> pickGif() async {
    gifPicks++;
    return gifPath;
  }
}

void main() {
  late Directory tmp;
  late File stickerFile;
  late StickerPack pack;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('animated_media_test');
    packsDir = tmp.path;
    mediaCacheDir = '${tmp.path}/media';
    await Directory(mediaCacheDir).create(recursive: true);
    stickerFile = File('${tmp.path}/sticker_0.webp');
    await stickerFile.writeAsBytes(base64Decode(_kPng1x1));
    // A static pack: the case in which video and GIF used to dead-end.
    pack = StickerPack('test pack', 'author', 'pack_test', [Sticker(stickerFile.path, ['❤'])], '1', false);
    packs = [pack];
  });

  tearDown(() async {
    StickerMediaSources.instance = const PlatformStickerMediaSources();
    await tmp.delete(recursive: true);
  });

  MaterialApp app({required RouteFactory onGenerateRoute}) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateRoute: onGenerateRoute,
    );
  }

  /// Advances a flow that does both kinds of work until [done] holds.
  ///
  /// The widget test clock is fake, so the page's own continuations need a
  /// pump, while the file I/O of saving a pack and the mocked platform channel
  /// of the converter need the real event loop ([WidgetTester.runAsync]).
  /// Alternating the two lets a flow run to its end; the trace says what the
  /// flow was doing when it did not get there.
  Future<bool> pumpUntil(
    WidgetTester tester,
    bool Function() done, {
    int rounds = 200,
    String Function()? trace,
  }) async {
    for (var round = 0; round < rounds; round++) {
      if (round % 25 == 0) {
        final line = trace?.call();
        if (line != null) print('round $round: $line');
      }
      if (done()) return true;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    return done();
  }

  /// Lets whatever was just shown run out, so the test does not end with a
  /// pending timer (the notice that says the sticker is ready, for example).
  ///
  /// Bounded pumps instead of [WidgetTester.pumpAndSettle]: the flow shows a
  /// progress indicator while it converts, and an animation that never ends
  /// only makes the settle time out, hiding the real state.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    for (var round = 0; round < 10; round++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// What a flow has done so far. Reported when it did not get where the test
  /// wanted it: a widget test that fails here is otherwise a black box.
  String flowTrace(WidgetTester tester, {int conversions = 0}) {
    final dialog = find.byType(ErrorDialog);
    final error = dialog.evaluate().isEmpty ? 'none' : tester.widget<ErrorDialog>(dialog).message;
    final cache = Directory(mediaCacheDir);
    final media = cache.existsSync() ? cache.listSync().map((entry) => entry.path.split('/').last).join(',') : 'missing';
    return 'conversions=$conversions dialogs=${find.byType(AlertDialog).evaluate().length} '
        'error=$error stickers=${packs.map((entry) => entry.stickers.length).toList()} '
        'media=[$media] page=${find.text('new pack page').evaluate().isNotEmpty}';
  }

  /// Whether the notice that ends a GIF flow is on screen.
  ///
  /// The messenger shows it in every Scaffold registered with it (the pack page
  /// and a page pushed on top of it), so "on screen" means at least one copy.
  bool noticeShown(String text) => find.textContaining(text, skipOffstage: false).evaluate().isNotEmpty;

  /// Fails with the message the flow itself reported when an error dialog is on
  /// screen: "nothing was added" then says why instead of leaving the test to
  /// guess.
  void expectNoFlowError(WidgetTester tester) {
    final dialog = find.byType(ErrorDialog);
    if (dialog.evaluate().isEmpty) return;
    fail('the flow reported an error: ${tester.widget<ErrorDialog>(dialog).message}');
  }

  /// Opens the "new sticker" sheet of the pack page by tapping the empty cell.
  Future<void> openNewStickerSheet(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
  }

  /// Types a title and an author into the open create-pack dialog and confirms.
  Future<void> confirmCreatePackDialog(WidgetTester tester, {String title = 'Animado'}) async {
    expect(find.text('Create sticker pack'), findsOneWidget);
    // The animated segment has to be preselected: a video or a GIF sticker
    // cannot be added to a static pack.
    final segmented = tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
    expect(segmented.selected, {true});
    expect(find.text('Animated'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), title);
    await tester.enterText(find.byType(TextFormField).at(1), 'author');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  testWidgets('a static pack offers video and GIF as sticker sources', (tester) async {
    await tester.pumpWidget(app(
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => StickerPackPage(pack, () {})),
    ));
    await tester.pumpAndSettle();

    await openNewStickerSheet(tester);

    expect(find.text('New image'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('GIF'), findsOneWidget);
  });

  testWidgets('picking a video from a static pack creates the animated pack it needs', (tester) async {
    const videoPath = '/tmp/movie.mp4';
    StickerMediaSources.instance = _FakeMediaSources(videoPath: videoPath);
    EditArguments? arguments;
    await tester.pumpWidget(app(
      onGenerateRoute: (settings) {
        if (settings.name == '/crop_video') {
          arguments = settings.arguments as EditArguments;
          return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('trim page')));
        }
        return MaterialPageRoute<void>(builder: (_) => StickerPackPage(pack, () {}));
      },
    ));
    await tester.pumpAndSettle();

    await openNewStickerSheet(tester);
    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();

    await confirmCreatePackDialog(tester);
    final trimmed = await pumpUntil(tester, () => find.text('trim page').evaluate().isNotEmpty);
    expect(trimmed, isTrue, reason: 'the trimmer opens: ${flowTrace(tester)}');
    await settle(tester);

    expect(packs, hasLength(2), reason: 'the user asked for a new pack and got one');
    final created = packs.last;
    expect(created.animated, isTrue);
    expect(created.title, 'Animado');
    expect(created.stickers, isEmpty, reason: 'nothing is added before the user trims a video');

    // The new pack is persisted even though the picker below can be cancelled.
    final saved = jsonDecode(File('$packsDir/packs.json').readAsStringSync()) as List;
    expect(saved.map((entry) => (entry as Map)['title']), contains('Animado'));

    expect(find.text('trim page'), findsOneWidget);
    expect(arguments, isNotNull);
    expect(arguments!.pack.id, created.id, reason: 'the sticker goes into the new animated pack');
    expect(arguments!.index, 0);
    expect(arguments!.mediaPath, videoPath);
    expect(arguments!.popCount, 0, reason: 'the pack page has to stay behind the trimmer');
  });

  testWidgets('cancelling the create-pack dialog leaves the library alone', (tester) async {
    StickerMediaSources.instance = _FakeMediaSources(videoPath: '/tmp/movie.mp4');
    await tester.pumpWidget(app(
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => StickerPackPage(pack, () {})),
    ));
    await tester.pumpAndSettle();

    await openNewStickerSheet(tester);
    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(packs, hasLength(1));
    expect(find.text('test pack'), findsWidgets, reason: 'the user is back on the pack page');
  });

  testWidgets('a GIF becomes a sticker of a new animated pack, cut to the limit', (tester) async {
    const gifPath = '/tmp/animation.gif';
    final sources = _FakeMediaSources(gifPath: gifPath);
    StickerMediaSources.instance = sources;
    // The native GIF converter writes the animated WebP and answers with the
    // length of the source GIF (12s here, i.e. longer than WhatsApp allows).
    var conversions = 0;
    const channel = MethodChannel('de.loicezt.stickers/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'convertGif') return null;
      conversions++;
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['maxDurationMs'], 10 * 1000, reason: 'the native side is told the limit too');
      await File(args['outputFile']! as String).writeAsBytes(base64Decode(_kPng1x1));
      return 12000;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(app(
      onGenerateRoute: (settings) {
        if (settings.name == '/pack') {
          return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('new pack page')));
        }
        return MaterialPageRoute<void>(builder: (_) => StickerPackPage(pack, () {}));
      },
    ));
    await tester.pumpAndSettle();

    await openNewStickerSheet(tester);
    await tester.tap(find.text('GIF'));
    // Only bounded pumps here: the flow shows a progress indicator while it
    // converts, so settling on it would never return.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await confirmCreatePackDialog(tester, title: 'GIF pack');
    final added = await pumpUntil(
      tester,
      () => packs.last.stickers.isNotEmpty && noticeShown('Sticker ready'),
      trace: () => flowTrace(tester, conversions: conversions),
    );
    expect(added, isTrue, reason: 'the GIF becomes a sticker: ${flowTrace(tester, conversions: conversions)}');
    expectNoFlowError(tester);
    print('flow: ${flowTrace(tester, conversions: conversions)}');

    expect(sources.gifPicks, 1);
    expect(packs, hasLength(2));
    final created = packs.last;
    expect(created.animated, isTrue);
    expect(created.stickers, hasLength(1), reason: 'the GIF became a sticker of the new pack');
    expect(File(created.stickers.single.source).existsSync(), isTrue);
    expect(pack.stickers, hasLength(1), reason: 'the static pack is left untouched');
    // The user has to know that only part of the GIF fitted the limit. It is
    // checked before the notice runs out (it lives for a few seconds).
    expect(find.textContaining('Sticker ready', skipOffstage: false), findsWidgets);
    expect(find.textContaining('first 10 seconds of the GIF', skipOffstage: false), findsWidgets);
    // The pack the sticker went to is opened once the flow is done with it.
    await pumpUntil(tester, () => find.text('new pack page').evaluate().isNotEmpty);
    expect(find.text('new pack page'), findsOneWidget, reason: 'the pack the sticker went to is shown');
    // Let the notice run out so the test does not end with its timer pending.
    await settle(tester);
  });

  testWidgets('an animated pack converts a GIF into its own slot', (tester) async {
    const gifPath = '/tmp/animation.gif';
    final animated = StickerPack('test pack', 'author', 'pack_test', [Sticker(stickerFile.path, ['❤'])], '1', true);
    packs = [animated];
    StickerMediaSources.instance = _FakeMediaSources(gifPath: gifPath);
    var conversions = 0;
    const channel = MethodChannel('de.loicezt.stickers/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'convertGif') return null;
      conversions++;
      final args = call.arguments as Map<Object?, Object?>;
      await File(args['outputFile']! as String).writeAsBytes(base64Decode(_kPng1x1));
      return 3000;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(app(
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => StickerPackPage(animated, () {})),
    ));
    await tester.pumpAndSettle();

    // Replacing the only sticker of the animated pack: no new pack is created.
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GIF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final replaced = await pumpUntil(
      tester,
      () => animated.stickers.single.source != stickerFile.path && noticeShown('Sticker ready'),
      trace: () => flowTrace(tester, conversions: conversions),
    );
    expect(replaced, isTrue, reason: 'the GIF replaces the sticker: ${flowTrace(tester, conversions: conversions)}');
    expectNoFlowError(tester);
    print('flow: ${flowTrace(tester, conversions: conversions)}');

    expect(packs, hasLength(1));
    expect(animated.stickers, hasLength(1), reason: 'the sticker is replaced, not appended');
    expect(File(animated.stickers.single.source).existsSync(), isTrue);
    // A GIF inside the limit is not reported as cut, and the flow still says it
    // is done. As above: checked while the notice is on screen.
    expect(find.textContaining('fit WhatsApp', skipOffstage: false), findsNothing);
    expect(find.textContaining('Sticker ready', skipOffstage: false), findsWidgets);
    await settle(tester);
  });
}
