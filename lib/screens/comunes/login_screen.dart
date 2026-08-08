import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../widgets/logo_oh.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passFocus = FocusNode();
  String? _error;
  bool _cargando = false;
  bool _mostrarPassword = false;

  @override
  void dispose() {
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await _authService.iniciarSesion(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      // La navegación real a cada dashboard según rol se resuelve
      // en el widget raíz (ver main.dart) escuchando el stream de
      // usuario + su documento en Firestore.
    } catch (e) {
      setState(() => _error = AppLocalizations.of(context)!.loginCredencialesIncorrectas);
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _recuperarPassword() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final enviar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.loginRecuperarContrasenaTitulo),
        content: TextField(
          controller: emailCtrl,
          decoration: InputDecoration(labelText: AppLocalizations.of(context)!.loginEmail),
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context)!.comunCancelar)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context)!.loginEnviarEnlace)),
        ],
      ),
    );

    if (enviar != true || emailCtrl.text.trim().isEmpty) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;

    try {
      await _authService.enviarEmailDeRecuperacion(emailCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loginEmailEnviado)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loginEmailError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LogoOh(
                  size: 96,
                  sobreFondoOscuro: Theme.of(context).brightness == Brightness.dark,
                ),
                const SizedBox(height: 16),
                const Text('Sotto Studio', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailCtrl,
                  decoration: InputDecoration(labelText: l10n.loginEmail),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passFocus.requestFocus(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passCtrl,
                  focusNode: _passFocus,
                  decoration: InputDecoration(
                    labelText: l10n.loginPassword,
                    suffixIcon: IconButton(
                      icon: Icon(_mostrarPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _mostrarPassword = !_mostrarPassword),
                    ),
                  ),
                  obscureText: !_mostrarPassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _cargando ? null : _iniciarSesion(),
                ),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                FilledButton(
                  onPressed: _cargando ? null : _iniciarSesion,
                  child: _cargando
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.loginIniciarSesion),
                ),
                TextButton(
                  onPressed: _cargando ? null : _recuperarPassword,
                  child: Text(l10n.loginOlvidasteContrasena),
                ),
                // TODO: enlace a pantalla de registro.
              ],
            ),
          ),
        ),
      ),
    );
  }
}
