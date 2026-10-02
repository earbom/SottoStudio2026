import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/mensaje_error.dart';
import '../../services/auth_service.dart';

class CambiarPasswordScreen extends StatefulWidget {
  const CambiarPasswordScreen({super.key});

  @override
  State<CambiarPasswordScreen> createState() => _CambiarPasswordScreenState();
}

class _CambiarPasswordScreenState extends State<CambiarPasswordScreen> {
  final _authService = AuthService();
  final _actualCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _repiteCtrl = TextEditingController();
  String? _error;
  bool _cargando = false;
  bool _mostrarActual = false;
  bool _mostrarNueva = false;
  bool _mostrarRepite = false;

  Future<void> _cambiar() async {
    if (_nuevaCtrl.text != _repiteCtrl.text) {
      setState(() => _error = 'Las contraseñas nuevas no coinciden.');
      return;
    }
    if (!_authService.contrasenaValida(_nuevaCtrl.text)) {
      setState(() => _error =
          'La nueva contraseña debe tener al menos 8 caracteres, mayúscula, minúscula, dígito y símbolo (@#\$%^&+=!_-).');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await _authService.cambiarPassword(
        passwordActual: _actualCtrl.text,
        passwordNueva: _nuevaCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contraseña actualizada.')),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = switch (e.code) {
            'wrong-password' || 'invalid-credential' => 'La contraseña actual no es correcta.',
            'too-many-requests' => 'Demasiados intentos. Prueba de nuevo en unos minutos.',
            'requires-recent-login' => 'Por seguridad, cierra sesión y vuelve a entrar antes de cambiarla.',
            _ => 'No se pudo cambiar la contraseña (${e.code}).',
          });
    } catch (e) {
      setState(() => _error = mensajeError(e, porDefecto: 'No se pudo cambiar la contraseña.'));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cambiar contraseña')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _actualCtrl,
                  decoration: InputDecoration(
                    labelText: 'Contraseña actual',
                    suffixIcon: IconButton(
                      icon: Icon(_mostrarActual ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _mostrarActual = !_mostrarActual),
                    ),
                  ),
                  obscureText: !_mostrarActual,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nuevaCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
                    helperText: 'Mín. 8 caracteres, mayúscula, minúscula, dígito y símbolo',
                    suffixIcon: IconButton(
                      icon: Icon(_mostrarNueva ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _mostrarNueva = !_mostrarNueva),
                    ),
                  ),
                  obscureText: !_mostrarNueva,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _repiteCtrl,
                  decoration: InputDecoration(
                    labelText: 'Repite la nueva contraseña',
                    suffixIcon: IconButton(
                      icon: Icon(_mostrarRepite ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _mostrarRepite = !_mostrarRepite),
                    ),
                  ),
                  obscureText: !_mostrarRepite,
                ),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                FilledButton(
                  onPressed: _cargando ? null : _cambiar,
                  child: _cargando
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Cambiar contraseña'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
