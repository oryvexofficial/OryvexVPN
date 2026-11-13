import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vexostream_app/widgets/vexo_theme.dart';

void main() {
  test('site fonts are bundled in the app folder and declared in pubspec', () {
    const files = [
      'Geist-Regular', 'Geist-Medium', 'Geist-SemiBold', 'Geist-Bold',
      'GeistMono-Regular', 'GeistMono-Medium', 'GeistMono-SemiBold',
      'Vazirmatn-Regular', 'Vazirmatn-Medium', 'Vazirmatn-SemiBold', 'Vazirmatn-Bold',
      'NotoSansArabic-Regular', 'NotoSansArabic-Bold',
    ];
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final name in files) {
      expect(File('assets/fonts/$name.ttf').existsSync(), isTrue, reason: '$name.ttf is missing');
      expect(pubspec.contains('assets/fonts/$name.ttf'), isTrue, reason: '$name.ttf is not declared');
    }
    expect(pubspec.contains('google_fonts'), isFalse);
  });

  test('app text uses the bundled Latin and Persian fonts, never a network font', () {
    final sans = Vx.sans();
    expect(sans.fontFamily, 'Geist');
    expect(sans.fontFamilyFallback, containsAllInOrder(['Vazirmatn', 'NotoSansArabic']));
    expect(Vx.mono().fontFamily, 'Geist Mono');
    expect(buildVexoTheme().textTheme.bodyLarge?.fontFamily, 'Geist');
  });
}
