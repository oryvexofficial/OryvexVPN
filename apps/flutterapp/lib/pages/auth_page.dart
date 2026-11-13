import 'package:flutter/material.dart';

import '../api/vexo_api.dart';
import '../widgets/vexo_theme.dart';

/// Site "auth-box": centered panel, logo, pill fields, full-width blue button.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.api, this.initialSignup = false});
  final VexoApi api;
  final bool initialSignup;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late bool _signup = widget.initialSignup;
  bool _adult = false;
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    if (_signup && !_adult) {
      setState(() => _error = 'You must be 18 or older to create an account.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = asMap(await widget.api.post(_signup ? '/auth/signup' : '/auth/login', body: {
        'username': _username.text.trim(),
        'password': _password.text,
        if (_signup) 'passwordConfirm': _confirm.text,
        if (_signup) 'adult': _adult,
      }));
      final token = (response['token'] ?? '').toString();
      if (token.isEmpty) throw const ApiException('The server did not issue a session.');
      await widget.api.saveToken(token);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(_signup ? 'Create account' : 'Log in')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.fromLTRB(32, 34, 32, 30),
              decoration: BoxDecoration(
                color: Vx.panel,
                borderRadius: BorderRadius.circular(Vx.radius2xl),
                border: Border.all(color: Vx.line),
                boxShadow: const [BoxShadow(color: Color(0xE6000000), blurRadius: 50, offset: Offset(0, 26), spreadRadius: -24)],
              ),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Align(alignment: Alignment.centerLeft, child: Image.asset('assets/brand/vexostream-logo-dark.png', height: 30)),
                  const SizedBox(height: 28),
                  Text(_signup ? 'Create your account' : 'Welcome back', style: t.headlineMedium),
                  const SizedBox(height: 8),
                  Text(_signup ? 'One account for the site and the app.' : 'Members and the site owner can sign in here.', style: t.bodyMedium?.copyWith(fontSize: 15)),
                  const SizedBox(height: 26),
                  TextField(
                    controller: _username,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'Username', prefixIcon: Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.person_outline_rounded))),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: !_show,
                    autofillHints: [_signup ? AutofillHints.newPassword : AutofillHints.password],
                    textInputAction: _signup ? TextInputAction.next : TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_signup) _submit();
                    },
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.lock_outline_rounded)),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: IconButton(
                          tooltip: _show ? 'Hide password' : 'Show password',
                          onPressed: () => setState(() => _show = !_show),
                          icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 19),
                        ),
                      ),
                    ),
                  ),
                  if (_signup) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirm,
                      obscureText: !_show,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(hintText: 'Repeat password', prefixIcon: Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.lock_reset_rounded))),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(Vx.radiusMd),
                      onTap: () => setState(() => _adult = !_adult),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Checkbox(value: _adult, onChanged: (v) => setState(() => _adult = v ?? false)),
                          Expanded(child: Text('I am 18 or older.', style: Vx.sans(size: 14, color: Vx.text2))),
                        ]),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(color: Vx.red.withValues(alpha: .1), borderRadius: BorderRadius.circular(Vx.radiusMd)),
                      child: Text(_error!, style: Vx.sans(size: 14, color: Vx.red)),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_signup ? 'Create account' : 'Log in'),
                  ),
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_signup ? 'Already have an account?' : 'New here?', style: Vx.sans(size: 14, color: Vx.text3)),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _signup = !_signup;
                                _error = null;
                              }),
                      child: Text(_signup ? 'Log in' : 'Create an account'),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
