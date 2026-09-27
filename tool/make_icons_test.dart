// Makes the app icons from the logo (the chip with "PF", see LogoPainter)
// for Android, iOS, the web and Windows.
//
// Run from the project root:  flutter test tool/make_icons_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/ui/widgets/logo.dart';

/// Background for icons that can't be see-through (iOS, web "maskable").
const _background = Color(0xFF0B0F12);

Future<Uint8List> render(int size, {Color? background, double? chip}) async {
  final recorder = ui.PictureRecorder();
  LogoPainter(background: background, chip: chip).paint(Canvas(recorder), Size.square(size.toDouble()));
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// A Windows .ico holding one PNG per size.
Future<Uint8List> ico(List<int> sizes) async {
  final images = [for (final size in sizes) await render(size)];
  final header = ByteData(6 + 16 * sizes.length)
    ..setUint16(2, 1, Endian.little) // icon
    ..setUint16(4, sizes.length, Endian.little);
  var offset = header.lengthInBytes;
  for (var i = 0; i < sizes.length; i++) {
    final entry = 6 + 16 * i;
    header
      ..setUint8(entry, sizes[i] >= 256 ? 0 : sizes[i]) // 0 means 256
      ..setUint8(entry + 1, sizes[i] >= 256 ? 0 : sizes[i])
      ..setUint16(entry + 4, 1, Endian.little) // planes
      ..setUint16(entry + 6, 32, Endian.little) // bits per pixel
      ..setUint32(entry + 8, images[i].length, Endian.little)
      ..setUint32(entry + 12, offset, Endian.little);
    offset += images[i].length;
  }
  return Uint8List.fromList([...header.buffer.asUint8List(), for (final png in images) ...png]);
}

void main() {
  testWidgets('make the app icons', (tester) async {
    await tester.runAsync(() async {
      // Android launcher icons: the chip with see-through corners.
      for (final (density, size) in const [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]) {
        File('android/app/src/main/res/mipmap-$density/ic_launcher.png').writeAsBytesSync(await render(size));
      }

      // iOS: every size the asset catalog lists (points x scale); no transparency allowed.
      final ios = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
      for (final file in ios.listSync().whereType<File>().where((f) => f.path.endsWith('.png'))) {
        final match = RegExp(r'(\d+(?:\.\d+)?)x\d+(?:\.\d+)?@(\d)x\.png$').firstMatch(file.path)!;
        final size = (double.parse(match.group(1)!) * int.parse(match.group(2)!)).round();
        file.writeAsBytesSync(await render(size, background: _background));
      }

      // Web: favicon and app icons; "maskable" ones get a background and
      // stay inside the safe zone (the middle 80%).
      File('web/favicon.png').writeAsBytesSync(await render(16));
      for (final size in const [192, 512]) {
        File('web/icons/Icon-$size.png').writeAsBytesSync(await render(size));
        File('web/icons/Icon-maskable-$size.png')
            .writeAsBytesSync(await render(size, background: _background, chip: 0.74));
      }

      // Windows: one .ico with every common size.
      File('windows/runner/resources/app_icon.ico').writeAsBytesSync(await ico(const [16, 24, 32, 48, 64, 128, 256]));

      // A large copy to look at.
      File('build/logo_1024.png').writeAsBytesSync(await render(1024));
    });
  });
}
