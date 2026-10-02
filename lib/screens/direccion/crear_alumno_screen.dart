import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/mensaje_error.dart';
import '../../models/usuario.dart';
import '../../services/auth_service.dart';
import '../../services/db_service.dart';
import 'alumno_perfil_screen.dart';

class CrearAlumnoScreen extends StatefulWidget {
  final Usuario perfil;

  const CrearAlumnoScreen({super.key, required this.perfil});

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
  // Algunos alumnos (muy jóvenes, o que deciden no usarla) no
  // necesitan poder iniciar sesión — igualmente deben constar en la
  // base de datos para que un profesor pueda puntuarlos/marcar su
  // asistencia. Ver CLAUDE.md.
  bool _tieneCuenta = true;

  Future<void> _crear() async {
    if (_nombreCtrl.text.trim().isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }
    if (_tieneCuenta && _emailCtrl.text.trim().isEmpty) {
      setState(() => _error = 'El email es obligatorio si el alumno tendrá acceso a la app.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      String? nuevoUid;
      if (_tieneCuenta) {
        final password = await _authService.crearAlumno(
          nombre: _nombreCtrl.text.trim(),
          apellidos: _apellidosCtrl.text.trim().isEmpty ? null : _apellidosCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          instrumento: _instrumentoCtrl.text.trim().isEmpty ? null : _instrumentoCtrl.text.trim(),
        );
        if (!mounted) return;
        await _mostrarPasswordGenerada(password);
        nuevoUid = (await DbService().obtenerUsuarioPorEmail(_emailCtrl.text.trim()))?.uid;
      } else {
        nuevoUid = await _authService.crearAlumnoSinCuenta(
          nombre: _nombreCtrl.text.trim(),
          apellidos: _apellidosCtrl.text.trim().isEmpty ? null : _apellidosCtrl.text.trim(),
          instrumento: _instrumentoCtrl.text.trim().isEmpty ? null : _instrumentoCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      await _ofrecerMatricular(nuevoUid);
    } catch (e) {
      setState(() => _error = mensajeError(e, porDefecto: 'No se pudo crear el alumno. Inténtalo de nuevo.'));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Tras el alta, lo natural es matricularlo: se ofrece ir directo a
  /// su ficha (donde está "Matricular en una asignatura").
  Future<void> _ofrecerMatricular(String? uid) async {
    final alumno = uid == null ? null : await DbService().obtenerUsuario(uid);
    if (!mounted) return;
    if (alumno == null) {
      Navigator.pop(context);
      return;
    }
    final matricular = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('${alumno.nombre} ya está dado de alta'),
        content: const Text('¿Quieres matricularlo ahora en sus asignaturas?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Más tarde')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Matricular ahora')),
        ],
      ),
    );
    if (!mounted) return;
    if (matricular == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AlumnoPerfilScreen(alumno: alumno, perfil: widget.perfil)),
      );
    } else {
      Navigator.pop(context);
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Este alumno podrá acceder a la app (tiene email)'),
                  subtitle: const Text(
                    'Desactívalo para alumnos que no vayan a usar la app (muy '
                    'jóvenes, o que decidan no hacerlo) — igualmente podrá ser '
                    'matriculado y puntuado por un profesor.',
                  ),
                  value: _tieneCuenta,
                  onChanged: (v) => setState(() => _tieneCuenta = v),
                ),
                if (_tieneCuenta) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email (real, del alumno o tutor)'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
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
