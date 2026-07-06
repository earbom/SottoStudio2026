import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String? _error;
  bool _cargando = false;

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
      setState(() => _error = 'Credenciales incorrectas.');
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Sotto Studio', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passCtrl,
                  decoration: const InputDecoration(labelText: 'Contraseña'),
                  obscureText: true,
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
                      : const Text('Iniciar sesión'),
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
