import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/version.dart';
import '../theme.dart';

export '../../core/version.dart';

/// The OryvexVPN mark (orbit ring + core slipping out through its gap), from assets/logo-mark.svg.
class OxMark extends StatelessWidget {
  const OxMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/logo-mark.svg',
      package: 'oryvex_shared',
      width: size,
      height: size,
      semanticsLabel: kAppName,
    );
  }
}

/// The full app icon tile, from assets/logo.svg.
class OxLogoTile extends StatelessWidget {
  const OxLogoTile({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset('assets/logo.svg', package: 'oryvex_shared', width: size, height: size);
  }
}

/// "OryvexVPN", set like an Apple product name: one face, the suffix in the brand blue.
class OxWordmark extends StatelessWidget {
  const OxWordmark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Oryvex', style: Ox.headline(size, weight: FontWeight.w700)),
          TextSpan(text: 'VPN', style: Ox.headline(size, weight: FontWeight.w600, color: Ox.blue)),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
  }
}

/// The credit line every page ends with.
class OxCredit extends StatelessWidget {
  const OxCredit({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Center(
        child: Text('Made by $kCreator', style: Ox.body(13, color: Ox.tertiary, weight: FontWeight.w500)),
      ),
    );
  }
}
