import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/backend.dart';
import '../../core/cloudflare_relay.dart';
import '../../core/platform_links.dart';
import '../theme.dart';
import 'section.dart';

Future<void> showCloudflareRelaySetup(BuildContext context, {required CoreBackend backend}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _CloudflareRelayDialog(backend: backend),
  );
}

class _CloudflareRelayDialog extends StatefulWidget {
  const _CloudflareRelayDialog({required this.backend});
  final CoreBackend backend;
  @override
  State<_CloudflareRelayDialog> createState() => _CloudflareRelayDialogState();
}

class _CloudflareRelayDialogState extends State<_CloudflareRelayDialog> {
  final _token = TextEditingController();
  final _client = CloudflareRelayClient();
  List<CloudflareAccount> _accounts = const [];
  CloudflareAccount? _account;
  CloudflareRelayDeployment? _deployment;
  CloudflareRelayUnlinkedException? _unlinked;
  String? _health;
  String? _error;
  bool _busy = false;
  bool _loaded = false;
  bool _showToken = false;

  @override
  void dispose() {
    _token.clear();
    _token.dispose();
    _client.close();
    super.dispose();
  }

  Future<void> _openTokenTemplate() async {
    final ok = await openCloudflareTemplate(CloudflareRelayClient.tokenTemplateUrl);
    if (!mounted) return;
    if (!ok) setState(() => _error = 'Could not open Cloudflare in your browser. Open the token template from Cloudflare and return here.');
  }

  Future<void> _loadAccounts() async {
    final token = _token.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Paste a scoped Cloudflare API token first.');
      return;
    }
    setState(() { _busy = true; _error = null; _loaded = false; });
    try {
      final accounts = await _client.listAccounts(token);
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _account = accounts.first;
        _loaded = true;
      });
    } on CloudflareRelayException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deploy() async {
    final token = _token.text.trim();
    final account = _account;
    if (token.isEmpty || account == null) return;
    setState(() { _busy = true; _error = null; _deployment = null; _unlinked = null; _health = null; });
    try {
      final deployment = await _client.deployAndConfigureFox(token: token, account: account, backend: widget.backend);
      try {
        await CloudflareRelayStore.remember(deployment);
      } catch (_) {
        // Relay deployment has already succeeded; local history is best-effort.
      }
      if (!mounted) return;
      _token.clear();
      setState(() => _deployment = deployment);
    } on CloudflareRelayUnlinkedException catch (e) {
      if (mounted) setState(() { _unlinked = e; _error = e.message; });
    } on CloudflareRelayException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = 'Worker deployed, but Fox settings could not be saved: ${e.message}');
    } catch (_) {
      if (mounted) setState(() => _error = 'Deployment did not finish. The API token was not saved by OryvexVPN.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryLink() async {
    final pending = _unlinked;
    if (pending == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _client.configureFoxRelay(widget.backend, pending.relayUrl);
      final host = Uri.tryParse(pending.publicUrl)?.host ?? '';
      final deployment = CloudflareRelayDeployment(
        scriptName: host.split('.').first,
        publicUrl: pending.publicUrl,
      );
      try {
        await CloudflareRelayStore.remember(deployment);
      } catch (_) {
        // Fox is linked; local history is best-effort.
      }
      if (!mounted) return;
      _token.clear();
      setState(() {
        _deployment = deployment;
        _unlinked = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save Fox settings. You can retry without creating another Worker.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testRelay() async {
    setState(() { _busy = true; _health = null; });
    try {
      final result = await widget.backend.foxRequest('POST', '/api/relay/test', {});
      if (mounted) setState(() => _health = result['ok'] == true
          ? 'Relay health check passed from this device.'
          : 'Relay was saved, but the health check could not confirm reachability. Try another network.');
    } catch (_) {
      if (mounted) setState(() => _health = 'Relay was saved, but the health check could not finish.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 540, maxHeight: MediaQuery.sizeOf(context).height - 48),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.cloud_upload_outlined, color: Ox.blue, size: 24),
                const SizedBox(width: 10),
                Expanded(child: Text('Deploy a Fox relay', style: Ox.headline(24))),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'OryvexVPN will create a restricted Worker in your Cloudflare account and configure it for Fox. It carries Fox account and service requests, not general VPN traffic. The Firefox sign-in page itself still connects directly.',
                style: Ox.body(14, color: Ox.secondary),
              ),
              const SizedBox(height: 16),
              OxTile(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'The Cloudflare token is sent only to Cloudflare and kept in memory for this setup. It is never saved in OryvexVPN settings. The relay can handle Firefox Account requests, so deploy only to an account you control.',
                  style: Ox.body(13, color: Ox.secondary),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _token,
                enabled: !_busy && _deployment == null,
                obscureText: !_showToken,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [],
                decoration: InputDecoration(
                  labelText: 'Cloudflare API token',
                  hintText: 'Paste a scoped token, not a Global API Key',
                  suffixIcon: IconButton(
                    tooltip: _showToken ? 'Hide token' : 'Show token',
                    onPressed: () => setState(() => _showToken = !_showToken),
                    icon: Icon(_showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  ),
                ),
                onChanged: (_) => setState(() { _loaded = false; _accounts = const []; _account = null; }),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _openTokenTemplate,
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: const Text('Open Token Template'),
                ),
              ),
              Text('In Cloudflare, restrict the template from all accounts to your intended account. Check that Account Settings Read and Workers Scripts Edit are selected before creating the token.', style: Ox.body(12, color: Ox.secondary)),
              const SizedBox(height: 12),
              if (!_loaded)
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _loadAccounts,
                  icon: const Icon(Icons.manage_search_rounded),
                  label: const Text('Validate token and load accounts'),
                )
              else ...[
                DropdownButtonFormField<CloudflareAccount>(
                  value: _account,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Cloudflare account'),
                  items: [for (final account in _accounts) DropdownMenuItem(value: account, child: Text(account.name, overflow: TextOverflow.ellipsis))],
                  onChanged: _busy ? null : (value) => setState(() => _account = value),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy || _account == null || _unlinked != null ? null : _deploy,
                  icon: const Icon(Icons.rocket_launch_rounded),
                  label: const Text('Deploy and configure Fox'),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text('Working with Cloudflare and Fox…', textAlign: TextAlign.center, style: Ox.body(13, color: Ox.secondary)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Semantics(liveRegion: true, child: Text(_error!, style: Ox.body(13, color: Ox.warn))),
              ],
              if (_unlinked != null) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _retryLink,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Retry linking this Worker'),
                ),
                Text('Keep this dialog open to retry. The private relay address is kept only in memory until Fox saves it.', style: Ox.body(12, color: Ox.secondary)),
              ],
              if (_deployment != null) ...[
                const SizedBox(height: 18),
                OxTile(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Icon(Icons.check_circle_rounded, color: Ox.success), const SizedBox(width: 8), Expanded(child: Text('Relay deployed and linked to Fox', style: Ox.body(15, weight: FontWeight.w600)))]),
                    const SizedBox(height: 8),
                    SelectableText(_deployment!.publicUrl, style: Ox.code(12)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => Clipboard.setData(ClipboardData(text: _deployment!.publicUrl)),
                        icon: const Icon(Icons.copy_rounded, size: 17),
                        label: const Text('Copy public status URL'),
                      ),
                    ),
                  ]),
                ),
                if (_health != null) Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(liveRegion: true, child: Text(_health!, style: Ox.body(13, color: Ox.secondary))),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: _busy ? null : _testRelay, icon: const Icon(Icons.health_and_safety_outlined), label: const Text('Test relay health')),
                FilledButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Done')),
              ],
              if (_deployment == null && !_busy) ...[
                const SizedBox(height: 12),
                Text('Deploying again creates a new Worker and replaces Fox’s saved relay URL. The previous Worker is not deleted.', style: Ox.body(12, color: Ox.tertiary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
