import 'package:flutter/material.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/db_service.dart';

/// Acciones de dirección sobre la cuenta de un alumno o profesor,
/// compartidas entre `AlumnoPerfilScreen` y `ProfesorAsignaturasScreen`.

/// Menú "⋮" con texto para la AppBar de la ficha de un usuario.
/// [onCambio] se llama tras editar o dar de baja, para refrescar.
class MenuAccionesUsuario extends StatelessWidget {
  final Usuario usuario;
  final VoidCallback? onEditado;
  final bool esAlumno;

  const MenuAccionesUsuario({super.key, required this.usuario, required this.esAlumno, this.onEditado});

  @override
  Widget build(BuildContext context) {
    final puedeRestablecer = usuario.tieneCuenta && (usuario.email?.isNotEmpty ?? false);
    final esUnoMismo = AuthService().usuarioActual?.uid == usuario.uid;
    return PopupMenuButton<String>(
      tooltip: 'Más opciones',
      onSelected: (opcion) async {
        switch (opcion) {
          case 'editar':
            if (await editarDatosUsuario(context, usuario, esAlumno: esAlumno)) onEditado?.call();
          case 'password':
            await restablecerPassword(context, usuario);
          case 'baja':
            if (await darDeBajaDelCentro(context, usuario, esAlumno: esAlumno) && context.mounted) {
              Navigator.pop(context);
            }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'editar',
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar datos')),
        ),
        if (puedeRestablecer)
          const PopupMenuItem(
            value: 'password',
            child: ListTile(
              leading: Icon(Icons.lock_reset_outlined),
              title: Text('Enviar enlace para nueva contraseña'),
            ),
          ),
        if (!esUnoMismo)
          const PopupMenuItem(
            value: 'baja',
            child: ListTile(
              leading: Icon(Icons.person_off_outlined, color: Colors.red),
              title: Text('Dar de baja del centro'),
            ),
          ),
      ],
    );
  }
}

/// Devuelve true si se guardaron cambios.
Future<bool> editarDatosUsuario(BuildContext context, Usuario usuario, {required bool esAlumno}) async {
  final nombreCtrl = TextEditingController(text: usuario.nombre);
  final apellidosCtrl = TextEditingController(text: usuario.apellidos ?? '');
  final instrumentoCtrl = TextEditingController(text: usuario.instrumento ?? '');
  String? error;

  final guardar = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setStateDialog) => AlertDialog(
        title: const Text('Editar datos'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: InputDecoration(labelText: 'Nombre', errorText: error),
              ),
              TextField(
                controller: apellidosCtrl,
                decoration: const InputDecoration(labelText: 'Apellidos'),
              ),
              if (esAlumno)
                TextField(
                  controller: instrumentoCtrl,
                  decoration: const InputDecoration(labelText: 'Instrumento (opcional)'),
                ),
              const SizedBox(height: 16),
              Text(
                usuario.tieneCuenta
                    ? 'Email de acceso: ${usuario.email ?? '—'}\n'
                        'El email no se puede cambiar desde la app. Si está mal escrito, '
                        'da de baja esta cuenta y crea una nueva con el email correcto.'
                    : 'Sin acceso a la app (no tiene email).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (nombreCtrl.text.trim().isEmpty) {
                setStateDialog(() => error = 'El nombre es obligatorio.');
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
  if (guardar != true || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  String? vacioANull(String t) => t.trim().isEmpty ? null : t.trim();
  try {
    await DbService().actualizarDatosUsuario(
      usuario.uid,
      nombre: nombreCtrl.text.trim(),
      apellidos: vacioANull(apellidosCtrl.text),
      instrumento: esAlumno ? vacioANull(instrumentoCtrl.text) : usuario.instrumento,
    );
    messenger.showSnackBar(const SnackBar(content: Text('Datos guardados.')));
    return true;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('No se pudieron guardar los datos. Inténtalo de nuevo.')));
    return false;
  }
}

Future<void> restablecerPassword(BuildContext context, Usuario usuario) async {
  final email = usuario.email ?? '';
  final enviar = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nueva contraseña'),
      content: Text(
          'Se enviará a $email un enlace para que ${usuario.nombre} elija una contraseña nueva.\n\n'
          'Si no lo ve en unos minutos, que revise la carpeta de correo no deseado.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enviar enlace')),
      ],
    ),
  );
  if (enviar != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await AuthService().enviarEmailDeRecuperacion(email);
    messenger.showSnackBar(SnackBar(content: Text('Enlace enviado a $email.')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('No se pudo enviar el enlace. Comprueba que el email es correcto.')));
  }
}

/// Devuelve true si se dio de baja.
Future<bool> darDeBajaDelCentro(BuildContext context, Usuario usuario, {required bool esAlumno}) async {
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Dar de baja del centro'),
      content: Text(esAlumno
          ? '${usuario.nombre} dejará de poder entrar en la app y se le dará de baja de todas sus asignaturas.\n\n'
              'Sus notas, asistencias y horas de estudio se conservan. Podrás reactivarlo más adelante desde la lista de alumnos.'
          : '${usuario.nombre} dejará de poder entrar en la app y de aparecer en las listas de profesorado.\n\n'
              'Sus fichajes y las notas que puso se conservan. Podrás reactivarlo más adelante desde la lista de profesorado.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Dar de baja'),
        ),
      ],
    ),
  );
  if (confirmar != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await DbService().darDeBajaUsuario(usuario.uid);
    messenger.showSnackBar(SnackBar(content: Text('${usuario.nombre} ha sido dado de baja.')));
    return true;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('No se pudo dar de baja. Inténtalo de nuevo.')));
    return false;
  }
}

/// Sección plegable "Dados de baja (N)" al final de un listado, con
/// botón para reactivar a cada uno.
class SeccionDadosDeBaja extends StatelessWidget {
  final Stream<List<Usuario>> stream;

  const SeccionDadosDeBaja({super.key, required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Usuario>>(
      stream: stream,
      builder: (context, snapshot) {
        final bajas = snapshot.data ?? const <Usuario>[];
        if (bajas.isEmpty) return const SizedBox.shrink();
        return ExpansionTile(
          leading: const Icon(Icons.person_off_outlined),
          title: Text('Dados de baja (${bajas.length})'),
          children: bajas
              .map((u) => ListTile(
                    title: Text((u.apellidos?.isNotEmpty ?? false) ? '${u.apellidos}, ${u.nombre}' : u.nombre),
                    subtitle: Text(u.email ?? 'Sin acceso a la app'),
                    trailing: TextButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await DbService().reactivarUsuario(u.uid);
                          messenger.showSnackBar(SnackBar(
                              content: Text('${u.nombre} reactivado. Recuerda volver a matricularlo si hace falta.')));
                        } catch (_) {
                          messenger.showSnackBar(const SnackBar(content: Text('No se pudo reactivar.')));
                        }
                      },
                      child: const Text('Reactivar'),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}
