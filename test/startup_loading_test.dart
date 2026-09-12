import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/widgets/initialization_gate.dart';

void main() {
  Widget app(Future<void> Function() initialize, WidgetBuilder builder) => MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: InitializationGate(initialize: initialize, builder: builder),
      );

  testWidgets('lazy resources block only their consumer and initialize once', (tester) async {
    final ready = Completer<void>();
    var calls = 0;
    var builds = 0;
    Future<void> initialize() { calls++; return ready.future; }
    Widget content(BuildContext _) { builds++; return const Text('editor ready'); }
    await tester.pumpWidget(app(initialize, content));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(builds, 0);
    await tester.pumpWidget(app(initialize, content));
    expect(calls, 1);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('editor ready'), findsOneWidget);
  });

  testWidgets('failed initialization offers retry without constructing editor', (tester) async {
    var calls = 0;
    Future<void> initialize() async {
      if (++calls == 1) throw StateError('transient native registration failure');
    }
    await tester.pumpWidget(app(initialize, (_) => const Text('ready')));
    await tester.pumpAndSettle();
    expect(find.text('ready'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('leaving while resources load does not update disposed widget', (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(app(() => ready.future, (_) => const Text('ready')));
    await tester.pumpWidget(const SizedBox());
    ready.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('library loading', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('startup-library');
      packsDir = directory.path;
    });
    tearDown(() async => directory.delete(recursive: true));

    test('first install returns a growable empty library', () async {
      final loaded = await getPacks();
      expect(loaded, isEmpty);
      loaded.add(StickerPack('a', 'b', 'id', [], '0', false));
      expect(loaded, hasLength(1));
    });

    test('large isolate path preserves order, animation and every metadata field', () async {
      final original = List.generate(500, (i) => StickerPack(
        'Pack $i', 'Author ❤', 'pack_$i',
        List.generate(30, (j) => Sticker('/packs/$i/$j.webp', ['❤', '🎉'])),
        '$i', i.isEven, trayIcon: '/packs/$i/tray.webp',
        publisherWebsite: 'https://example.com',
        licenseAgreementWebsite: 'https://example.com/license',
        privacyPolicyWebsite: 'https://example.com/privacy',
      ));
      final encoded = jsonEncode(original.map((p) => p.toJson()).toList());
      expect(encoded.length, greaterThan(64 * 1024));
      await File('$packsDir/packs.json').writeAsString(encoded);
      final loaded = await getPacks();
      expect(loaded.map((p) => p.toJson()).toList(), original.map((p) => p.toJson()).toList());
    });

    test('corrupt library is never silently overwritten with empty packs', () async {
      final file = File('$packsDir/packs.json');
      await file.writeAsString('invalid');
      await expectLater(getPacks(), throwsFormatException);
      expect(await file.readAsString(), 'invalid');
    });
  });
}
