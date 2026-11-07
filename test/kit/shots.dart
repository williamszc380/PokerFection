/// Screenshots of widget tests, to look at layouts in every size and
/// language. A library, not a test: a test calls [pumpShot] to show a
/// screen at a size and in a language, then [shot] to save it as a PNG.
/// PNGs are written only when the test runs with
/// `--dart-define=SHOTS=<folder>`; otherwise [shot] does nothing.
///
/// Real fonts are loaded (Roboto, Material Icons, a Chinese font, and one
/// with the suit symbols ♠ ♥ ♦ ♣) when they are on this computer, so text
/// takes its real width in the checks too.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';

/// The folder PNGs go to; empty: none are written.
const shotsFolder = String.fromEnvironment('SHOTS');

/// The sizes every game screen is checked at: sideways phones, a phone
/// upright (browsers), a PC.
const shotSizes = [Size(568, 320), Size(592, 360), Size(390, 844), Size(1280, 800)];

final _boundary = GlobalKey();
var _fontsLoaded = false;

/// Loads Roboto and Material Icons from Flutter's own copy, and a Chinese
/// font and Segoe UI Symbol (the suits, as devices draw them with their own
/// symbol fonts) from Windows, if they are there. Call it in setUpAll.
Future<void> loadShotFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\Users\willi\dev\flutter';
  final fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
  await _font('Roboto', ['$fonts/roboto-regular.ttf', '$fonts/roboto-medium.ttf', '$fonts/roboto-bold.ttf']);
  await _font('MaterialIcons', ['$fonts/materialicons-regular.otf']);
  await _font('CJK', ['C:/Windows/Fonts/Deng.ttf', 'C:/Windows/Fonts/Dengb.ttf']);
  await _font('Symbols', ['C:/Windows/Fonts/seguisym.ttf']);
}

Future<void> _font(String family, List<String> files) async {
  final found = [for (final f in files) if (File(f).existsSync()) f];
  if (found.isEmpty) return;
  final loader = FontLoader(family);
  for (final f in found) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

/// The app's theme, with the Chinese font and then the symbols behind the others.
ThemeData shotTheme() {
  final base = PokerFectionApp.theme;
  return base.copyWith(textTheme: base.textTheme.apply(fontFamilyFallback: const ['CJK', 'Symbols']));
}

/// Shows [home] at [size] (logical pixels, 1 pixel each) in [language],
/// inside the app's theme, settings and (when given) [wrap]: a KitScope.
Future<void> pumpShot(
  WidgetTester tester,
  Widget home, {
  required Size size,
  AppLanguage language = AppLanguage.english,
  Widget Function(Widget child)? wrap,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettings()..language = language;
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: shotTheme(),
    locale: language.locale,
    supportedLocales: [for (final l in AppLanguage.values) l.locale],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => TooltipVisibility(visible: false, child: child!),
    home: home,
  );
  await tester.pumpWidget(RepaintBoundary(
    key: _boundary,
    child: AppSettingsScope(settings: settings, child: wrap == null ? app : wrap(app)),
  ));
}

/// A name for [size] and [language]: `en_568x320`.
String shotTag(Size size, AppLanguage language) => '${language.code}_${size.width.toInt()}x${size.height.toInt()}';

/// Saves the screen as `<SHOTS>/<name>.png` (only with --dart-define=SHOTS),
/// at [pixelRatio] image pixels per logical pixel (3: as a phone shows it).
Future<void> shot(WidgetTester tester, String name, {double pixelRatio = 1}) async {
  if (shotsFolder.isEmpty) return;
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(shotsFolder).createSync(recursive: true);
    File('$shotsFolder/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
