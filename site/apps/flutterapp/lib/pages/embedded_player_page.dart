import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/provider_embed.dart';
import '../api/vexo_api.dart';
import '../widgets/provider_embed_view.dart';
import '../widgets/vexo_theme.dart';

/// The app's playback surface is VexoStream's own web player, hosted in a
/// first-party WebView. There is no native media-kit playback path.
class PlayerPage extends StatelessWidget {
  const PlayerPage({
    super.key,
    required this.api,
    required this.video,
    required this.onSignIn,
  });

  final VexoApi api;
  final Map<String, dynamic> video;
  final Future<void> Function() onSignIn;

  String get _title => firstText(video, const ['title', 'name']);
  String get _target => firstText(video, const ['url', 'video_url', 'link', 'href']);

  Future<void> _copy(BuildContext context, String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final embed = providerEmbedForVideo(video);
    final title = _title.isEmpty ? 'VexoStream Player' : _title;
    final provider = firstText(video, const ['provider']);

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (embed != null)
            IconButton(
              tooltip: 'Copy VexoStream embed link',
              onPressed: () => _copy(context, embed.embedUri.toString(), 'VexoStream embed link copied'),
              icon: const Icon(Icons.link_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageBody(
        maxWidth: 1240,
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Vx.radiusXl),
              child: ColoredBox(
                color: Colors.black,
                child: embed == null
                    ? _unsupportedSource(context)
                    : VexoEmbedView(
                        embed: embed,
                        api: api,
                        onBack: () => Navigator.of(context).maybePop(),
                        onSignIn: onSignIn,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 24)),
          const SizedBox(height: 10),
          Row(children: [
            if (provider.isNotEmpty) ...[
              ProviderIcon(id: provider.toLowerCase(), name: provider, size: 22),
              const SizedBox(width: 8),
              Text(
                provider[0].toUpperCase() + provider.substring(1),
                style: Vx.sans(size: 14, color: Vx.text2, weight: FontWeight.w500),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(
                _target,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Vx.mono(size: 12),
              ),
            ),
            TextButton.icon(
              onPressed: () => _copy(context, _target, 'Original video link copied'),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy link'),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            'Playback and quality controls are provided by the VexoStream player.',
            style: Vx.sans(size: 13, color: Vx.text2),
          ),
        ],
      ),
    );
  }

  Widget _unsupportedSource(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_off_rounded, size: 42, color: Colors.white70),
                const SizedBox(height: 14),
                Text(
                  'Unsupported video link',
                  textAlign: TextAlign.center,
                  style: Vx.sans(size: 20, color: Colors.white, weight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'This link does not match a supported provider video page, so it cannot be opened in the VexoStream player.',
                  textAlign: TextAlign.center,
                  style: Vx.sans(size: 14, color: Vx.text2),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => _copy(context, _target, 'Original video link copied'),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy original link'),
                ),
              ],
            ),
          ),
        ),
      );
}
