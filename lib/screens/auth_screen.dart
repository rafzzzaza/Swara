import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';

enum _Mode { login, register }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _Mode _mode = _Mode.login;
  bool _obscure = true;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      auth.showInlineError('Isi email dan kata sandi terlebih dahulu.');
      return;
    }
    if (password.length < 6) {
      auth.showInlineError('Kata sandi minimal 6 karakter.');
      return;
    }

    final ok = _mode == _Mode.register
        ? await auth.register(
            email: email,
            password: password,
            displayName: _name.text.trim().isEmpty
                ? email.split('@').first
                : _name.text.trim(),
          )
        : await auth.login(email: email, password: password);

    if (ok && mounted) {
      // Sewa nama/email akun ke profil lokal.
      final user = context.read<AuthProvider>().user;
      if (user != null) {
        await context
            .read<ProfileProvider>()
            .update(displayName: user.displayName, email: user.email);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Brand(),
                const SizedBox(height: 28),
                _ModeToggle(mode: _mode, onChanged: (m) {
                  setState(() => _mode = m);
                }),
                const SizedBox(height: 20),
                if (_mode == _Mode.register) ...[
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: _decoration(
                      label: 'Nama pengguna',
                      icon: Icons.person_outline,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: _decoration(
                    label: 'Email',
                    icon: Icons.mail_outline,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: _decoration(
                    label: 'Kata sandi',
                    icon: Icons.lock_outline,
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.white54,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (auth.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    auth.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFFFF6B6B), fontSize: 13),
                  ),
                ],
                const SizedBox(height: 20),
                if (auth.loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5)),
                  )
                else
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: kSwaraGold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: _submit,
                    child: Text(
                      _mode == _Mode.login ? 'Masuk' : 'Buat Akun',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: auth.loading
                      ? null
                      : () {
                          context.read<AuthProvider>().continueAsGuest();
                        },
                  child: const Text('Lanjut tanpa akun (mode tamu)'),
                ),
                const SizedBox(height: 14),
                Text(
                  'Akun & data tersimpan aman di database online '
                  '(Supabase). Riwayat pemutaranmu tersinkron otomatis.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.45)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration _decoration({required String label, required IconData icon}) =>
    InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: Colors.white54),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );

class _Brand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: kSwaraGold.withValues(alpha: 0.4)),
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.graphic_eq,
                color: Colors.black,
                size: 44,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Swara',
            style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2)),
        const SizedBox(height: 4),
        Text(
          'Streaming musik premium — full audio, tanpa iklan',
          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
        ),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onChanged;

  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _tab('Masuk', _Mode.login),
          _tab('Daftar', _Mode.register),
        ],
      ),
    );
  }

  Widget _tab(String label, _Mode value) {
    final selected = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? kSwaraGold : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.black : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}