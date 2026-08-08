import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';

class CrearAlumnoScreen extends StatefulWidget {
  const CrearAlumnoScreen({super.key});

  @override
  State<CrearAlumnoScreen> createState() => _CrearAlumnoScreenState();
}

class _CrearAlumnoScreenState extends State<CrearAlumnoScreen> {
  final _authService = AuthService();
  final _nombreCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _instrumentoCtrl = TextEditingController();
  String? _error;
  bool _cargando = false;

  Future<void> _crear() async {
    if (_nombreCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Nombre y email son obligatorios.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final nombreCompleto = [
        _nombreCtrl.text.trim(),
        _apellidosCtrl.text.trim(),
      ].where((s) => s.isNotEmpty).join(' ');

      final password = await _authService.crearAlumno(
        nombre: nombreCompleto,
        email: _emailCtrl.text.trim(),
        instrumento: _instrumentoCtrl.text.trim().isEmpty ? null : _instrumentoCtrl.text.trim(),
      );

      if (!mounted) return;
      await _mostrarPasswordGenerada(password);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'No se pudo crear el alumno: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _mostrarPasswordGenerada(String password) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Alumno creado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Contraseña temporal (solo se muestra una vez):'),
            const SizedBox(height: 8),
            SelectableText(password, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'Compártela con el alumno o su familia. El alumno podrá cambiarla luego desde su cuenta.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: password));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Contraseña copiada')),
              );
            },
            child: const Text('Copiar'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Hecho')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo alumno')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _apellidosCtrl,
                  decoration: const InputDecoration(labelText: 'Apellidos'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email (real, del alumno o tutor)'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _instrumentoCtrl,
                  decoration: const InputDecoration(labelText: 'Instrumento (opcional)'),
                ),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                FilledButton(
                  onPressed: _cargando ? null : _crear,
                  child: _cargando
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Crear alumno'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
