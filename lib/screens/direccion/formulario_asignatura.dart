import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../models/asignatura.dart';
import '../../services/auth_service.dart';
import '../../services/db_service.dart';
import '../../utils/iconos_asignatura.dart';
import '../comunes/asignatura_detalle_screen.dart' show nombresDiasSemana;

/// Formulario de crear/editar asignatura, compartido entre
/// `CursoDetalleScreen` (crear dentro de un curso) y
/// `AsignaturaDetalleScreen` (editar desde la propia ficha). Incluye el
/// objetivo de horas de estudio — vive en la asignatura, no en el
/// curso ni en Criterios de evaluación (ver CLAUDE.md).
typedef _DatosAsignatura = ({
  String nombre,
  List<String> profesorIds,
  String iconoId,
  bool permiteGrabarEstudio,
  List<FranjaHoraria> franjasHorario,
  double horasObjetivoSemanal,
  double horasObjetivoMensual,
});

Future<FranjaHoraria?> _mostrarFormularioFranja(BuildContext context, {FranjaHoraria? existente}) {
  final seleccionados = (existente?.diasSemana ?? const []).toSet();
  var horaInicio = existente?.horaInicio ?? '';
  var horaFin = existente?.horaFin ?? '';

  Future<void> elegirHora(BuildContext context, void Function(String) onElegida, String actual) async {
    final partes = actual.split(':');
    final inicial = partes.length == 2
        ? TimeOfDay(hour: int.tryParse(partes[0]) ?? 9, minute: int.tryParse(partes[1]) ?? 0)
        : const TimeOfDay(hour: 9, minute: 0);
    final elegida = await showTimePicker(context: context, initialTime: inicial);
    if (elegida == null) return;
    onElegida('${elegida.hour.toString().padLeft(2, '0')}:${elegida.minute.toString().padLeft(2, '0')}');
  }

  return showDialog<FranjaHoraria>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setStateDialog) => AlertDialog(
        title: Text(existente == null ? 'Nuevo grupo horario' : 'Editar grupo horario'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Días de clase'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: List.generate(7, (i) {
                final dia = i + 1;
                return FilterChip(
                  label: Text(nombresDiasSemana[i]),
                  selected: seleccionados.contains(dia),
                  onSelected: (v) => setStateDialog(() {
                    v ? seleccionados.add(dia) : seleccionados.remove(dia);
                  }),
                );
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => elegirHora(context, (h) => setStateDialog(() => horaInicio = h), horaInicio),
                    child: Text(horaInicio.isEmpty ? 'Hora de inicio' : horaInicio),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => elegirHora(context, (h) => setStateDialog(() => horaFin = h), horaFin),
                    child: Text(horaFin.isEmpty ? 'Hora de fin' : horaFin),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: seleccionados.isEmpty || horaInicio.isEmpty || horaFin.isEmpty
                ? null
                : () => Navigator.pop(
                      context,
                      FranjaHoraria(
                        id: existente?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                        diasSemana: seleccionados.toList()..sort(),
                        horaInicio: horaInicio,
                        horaFin: horaFin,
                      ),
                    ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

String _textoHoras(double h) => h > 0 ? h.toStringAsFixed(1).replaceAll('.0', '') : '';

double _parsearHoras(String texto) {
  final v = double.tryParse(texto.trim().replaceAll(',', '.')) ?? 0;
  return v < 0 ? 0 : v;
}

Future<_DatosAsignatura?> _mostrarFormulario(BuildContext context, {Asignatura? existente}) async {
  final controladorNombre = TextEditingController(text: existente?.nombre ?? '');
  final controladorSemanal = TextEditingController(text: _textoHoras(existente?.horasObjetivoSemanal ?? 0));
  final controladorMensual = TextEditingController(text: _textoHoras(existente?.horasObjetivoMensual ?? 0));
  final profesoresSeleccionados = (existente?.profesorIds ?? const <String>[]).toSet();
  String iconoId = (existente?.iconoId.isNotEmpty ?? false) ? existente!.iconoId : iconosAsignaturaDisponibles.first.id;
  var permiteGrabarEstudio = existente?.permiteGrabarEstudio ?? false;
  final franjas = [...?existente?.franjasHorario];
  String? errorNombre;
  final profesores = await DbService().profesoresDelCentro().first;
  if (!context.mounted) return null;

  return showDialog<_DatosAsignatura>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setStateDialog) {
        final titulo = Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);
        return AlertDialog(
          title: Text(existente == null ? 'Nueva asignatura' : 'Editar asignatura'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controladorNombre,
                  decoration: InputDecoration(
                    labelText: 'Nombre (ej. Violín, Lenguaje musical...)',
                    errorText: errorNombre,
                  ),
                  autofocus: existente == null,
                ),
                const SizedBox(height: 20),
                Text('Horas de estudio en casa que se piden al alumno', style: titulo),
                const SizedBox(height: 4),
                const Text('Déjalo vacío si esta asignatura no tiene objetivo de horas.',
                    style: TextStyle(fontSize: 13)),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controladorSemanal,
                        decoration: const InputDecoration(labelText: 'Horas por semana'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: controladorMensual,
                        decoration: const InputDecoration(labelText: 'Horas por mes'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Es una asignatura de instrumento'),
                  subtitle: const Text(
                      'El alumno podrá grabar con el micrófono sus horas de práctica, y cada alumno tiene su propio horario de clase.'),
                  value: permiteGrabarEstudio,
                  onChanged: (v) => setStateDialog(() {
                    permiteGrabarEstudio = v;
                    // Instrumento y grupos horarios son excluyentes por
                    // diseño (ver CLAUDE.md punto 69).
                    if (v) franjas.clear();
                  }),
                ),
                if (!permiteGrabarEstudio) ...[
                  const SizedBox(height: 8),
                  Text('Grupos y horario de clase', style: titulo),
                  const SizedBox(height: 4),
                  const Text(
                      'Si la asignatura se da en grupo, añade aquí cada grupo con sus días y horas. Después, al matricular, solo tendrás que elegir el grupo.',
                      style: TextStyle(fontSize: 13)),
                  if (franjas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Ningún grupo todavía.', style: TextStyle(fontStyle: FontStyle.italic)),
                    ),
                  ...franjas.map((f) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule_outlined),
                        title: Text(
                            '${f.diasSemana.map((d) => nombresDiasSemana[d - 1]).join(', ')} · ${f.horaInicio} - ${f.horaFin}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Editar grupo',
                              onPressed: () async {
                                final editada = await _mostrarFormularioFranja(context, existente: f);
                                if (editada == null) return;
                                setStateDialog(() {
                                  final i = franjas.indexWhere((x) => x.id == f.id);
                                  franjas[i] = editada;
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Quitar grupo',
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Quitar grupo'),
                                    content: const Text(
                                        'Los alumnos de este grupo se quedarán sin horario hasta que les asignes otro.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Cancelar')),
                                      FilledButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('Quitar')),
                                    ],
                                  ),
                                );
                                if (ok == true) setStateDialog(() => franjas.removeWhere((x) => x.id == f.id));
                              },
                            ),
                          ],
                        ),
                      )),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final nueva = await _mostrarFormularioFranja(context);
                        if (nueva == null) return;
                        setStateDialog(() => franjas.add(nueva));
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Añadir grupo'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text('Icono', style: titulo),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: iconosAsignaturaDisponibles.map((icono) {
                    final seleccionado = icono.id == iconoId;
                    final esquema = Theme.of(context).colorScheme;
                    return Tooltip(
                      message: icono.etiqueta,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => setStateDialog(() => iconoId = icono.id),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: seleccionado ? esquema.primaryContainer : esquema.surfaceContainerHighest,
                            border: seleccionado ? Border.all(color: esquema.primary, width: 2) : null,
                          ),
                          child: Center(
                            child: FaIcon(
                              icono.icono,
                              size: 20,
                              color: seleccionado ? esquema.onPrimaryContainer : esquema.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text('Profesorado', style: titulo),
                if (profesores.isEmpty)
                  const Text('No hay profesores dados de alta todavía.',
                      style: TextStyle(fontStyle: FontStyle.italic)),
                ...profesores.map((p) => CheckboxListTile(
                      dense: true,
                      title: Text(p.nombre),
                      value: profesoresSeleccionados.contains(p.uid),
                      onChanged: (v) => setStateDialog(() {
                        v == true ? profesoresSeleccionados.add(p.uid) : profesoresSeleccionados.remove(p.uid);
                      }),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (controladorNombre.text.trim().isEmpty) {
                  setStateDialog(() => errorNombre = 'Escribe el nombre de la asignatura.');
                  return;
                }
                Navigator.pop(
                  context,
                  (
                    nombre: controladorNombre.text.trim(),
                    profesorIds: profesoresSeleccionados.toList(),
                    iconoId: iconoId,
                    permiteGrabarEstudio: permiteGrabarEstudio,
                    franjasHorario: permiteGrabarEstudio ? const <FranjaHoraria>[] : franjas,
                    horasObjetivoSemanal: _parsearHoras(controladorSemanal.text),
                    horasObjetivoMensual: _parsearHoras(controladorMensual.text),
                  ),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    ),
  );
}

/// Crea una asignatura nueva dentro del curso indicado.
Future<void> crearAsignaturaEnCurso(BuildContext context, String cursoId) async {
  final datos = await _mostrarFormulario(context);
  if (datos == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await DbService().crearAsignatura(Asignatura(
      cursoId: cursoId,
      nombre: datos.nombre,
      profesorIds: datos.profesorIds,
      createdAt: DateTime.now(),
      createdBy: AuthService().usuarioActual?.uid ?? '',
      iconoId: datos.iconoId,
      permiteGrabarEstudio: datos.permiteGrabarEstudio,
      franjasHorario: datos.franjasHorario,
      horasObjetivoSemanal: datos.horasObjetivoSemanal,
      horasObjetivoMensual: datos.horasObjetivoMensual,
    ));
    messenger.showSnackBar(SnackBar(content: Text('Asignatura "${datos.nombre}" creada.')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('No se pudo crear la asignatura. Inténtalo de nuevo.')));
  }
}

/// Edita una asignatura existente. Devuelve true si se guardó.
Future<bool> editarAsignatura(BuildContext context, Asignatura asignatura) async {
  final datos = await _mostrarFormulario(context, existente: asignatura);
  if (datos == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  final db = DbService();
  try {
    await db.actualizarAsignatura(asignatura.id!, {
      'nombre': datos.nombre,
      'profesorIds': datos.profesorIds,
      'iconoId': datos.iconoId,
      'permiteGrabarEstudio': datos.permiteGrabarEstudio,
      'franjasHorario': datos.franjasHorario.map((f) => f.toMap()).toList(),
      'horasObjetivoSemanal': datos.horasObjetivoSemanal,
      'horasObjetivoMensual': datos.horasObjetivoMensual,
    });

    // Re-sincroniza matrículas que ya tenían asignado un grupo EDITADO
    // (mismo id, días/hora distintos) y limpia las que apuntaban a uno
    // BORRADO — para que los alumnos ya matriculados también vean el
    // cambio, no solo los que se matriculen a partir de ahora.
    final cursoEscolar = await db.cursoEscolarActivo().first;
    final nuevasPorId = {for (final f in datos.franjasHorario) f.id: f};
    for (final anterior in asignatura.franjasHorario) {
      final nueva = nuevasPorId[anterior.id];
      if (nueva == null) {
        await db.limpiarFranjaDeMatriculas(
            asignaturaId: asignatura.id!, cursoEscolar: cursoEscolar, franjaId: anterior.id);
      } else if (nueva.diasSemana.join(',') != anterior.diasSemana.join(',') ||
          nueva.horaInicio != anterior.horaInicio ||
          nueva.horaFin != anterior.horaFin) {
        await db.sincronizarFranjaHoraria(asignaturaId: asignatura.id!, cursoEscolar: cursoEscolar, franja: nueva);
      }
    }
    messenger.showSnackBar(const SnackBar(content: Text('Cambios guardados.')));
    return true;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('No se pudieron guardar los cambios. Inténtalo de nuevo.')));
    return false;
  }
}
