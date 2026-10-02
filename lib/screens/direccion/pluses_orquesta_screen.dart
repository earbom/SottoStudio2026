import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/curso.dart';
import '../../models/plus_orquesta.dart';
import '../../services/auth_service.dart';
import '../../widgets/error_carga.dart';
import '../../services/db_service.dart';

/// Catálogo de pluses de horas por orquesta, gestionado por dirección
/// (pedido en el piloto): p.ej. "Orquesta de guitarras" suma minutos/
/// semana fijos a la asignatura "Guitarra" — se elige uno al matricular
/// a un alumno en la asignatura de orquesta (ver
/// `_configurarMatricula` en `asignatura_detalle_screen.dart` y
/// `Matricula.plusOrquestaId`). El plus en sí no está atado a NINGUNA
/// asignatura de origen — cualquier matrícula puede llevarlo, es
/// dirección quien decide en qué matrícula tiene sentido aplicarlo.
///
/// `PlusOrquesta.minutosSemana` (antes horas): el tiempo que aporta un
/// plus suele ser más corto que una hora completa (15-20 min de
/// ensayo), así que se introduce en minutos — ver CLAUDE.md.
///
/// El desplegable de asignatura destino muestra el CURSO junto al
/// nombre (p. ej. "Armonía · 2º Elemental"): varias asignaturas
/// distintas pueden compartir el mismo nombre en cursos diferentes
/// (p. ej. 4 "Armonía"), y mostrar solo el nombre no permitía
/// distinguirlas — reportado tras probar la app.
class PlusesOrquestaScreen extends StatelessWidget {
  const PlusesOrquestaScreen({super.key});

  String _etiquetaAsignatura(Asignatura a, Map<String, Curso> cursoPorId) {
    final curso = cursoPorId[a.cursoId];
    return curso == null ? a.nombre : '${a.nombre} · ${curso.nombre}';
  }

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      appBar: AppBar(title: const Text('Pluses de orquesta')),
      body: StreamBuilder<List<Curso>>(
        stream: db.cursos(),
        builder: (context, snapCursos) {
          if (snapCursos.hasError) {
            return const ErrorCarga();
          }
          if (!snapCursos.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cursoPorId = {for (final c in snapCursos.data!) c.id!: c};
          return StreamBuilder<List<Asignatura>>(
            stream: db.todasLasAsignaturas(),
            builder: (context, snapAsignaturas) {
              if (snapAsignaturas.hasError) {
                return const ErrorCarga();
              }
              if (!snapAsignaturas.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final asignaturaPorId = {for (final a in snapAsignaturas.data!) a.id!: a};
              return StreamBuilder<List<PlusOrquesta>>(
                stream: db.plusesOrquesta(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const ErrorCarga();
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final pluses = [...snapshot.data!]..sort((a, b) => a.nombre.compareTo(b.nombre));
                  if (pluses.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Aún no hay pluses de orquesta configurados.'),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: pluses.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final plus = pluses[i];
                      final destino = asignaturaPorId[plus.asignaturaDestinoId];
                      final etiquetaDestino =
                          destino == null ? '(asignatura eliminada)' : _etiquetaAsignatura(destino, cursoPorId);
                      return ListTile(
                        leading: const Icon(Icons.add_circle_outline),
                        title: Text(plus.nombre),
                        subtitle: Text('Suma +${plus.minutosSemana} min/semana a $etiquetaDestino'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _crearOEditar(
                                  context, snapAsignaturas.data!, cursoPorId,
                                  existente: plus),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _eliminar(context, plus),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: StreamBuilder<List<Curso>>(
        stream: db.cursos(),
        builder: (context, snapCursos) {
          return StreamBuilder<List<Asignatura>>(
            stream: db.todasLasAsignaturas(),
            builder: (context, snap) {
              final listo = snapCursos.hasData && snap.hasData;
              return FloatingActionButton(
                onPressed: listo
                    ? () => _crearOEditar(
                        context, snap.data!, {for (final c in snapCursos.data!) c.id!: c})
                    : null,
                child: const Icon(Icons.add),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _crearOEditar(BuildContext context, List<Asignatura> asignaturas,
      Map<String, Curso> cursoPorId, {PlusOrquesta? existente}) async {
    final db = DbService();
    final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
    final minutosCtrl =
        TextEditingController(text: existente != null ? existente.minutosSemana.toString() : '');
    String? asignaturaDestinoId = existente?.asignaturaDestinoId;

    final asignaturasOrdenadas = [...asignaturas]
      ..sort((a, b) => _etiquetaAsignatura(a, cursoPorId).compareTo(_etiquetaAsignatura(b, cursoPorId)));

    final guardar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(existente == null ? 'Nuevo plus de orquesta' : 'Editar plus de orquesta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre (ej. Orquesta de guitarras)'),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: asignaturaDestinoId,
                  decoration: const InputDecoration(labelText: 'Asignatura a la que suma minutos'),
                  items: asignaturasOrdenadas
                      .map((a) => DropdownMenuItem(
                          value: a.id, child: Text(_etiquetaAsignatura(a, cursoPorId))))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => asignaturaDestinoId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minutosCtrl,
                  decoration: const InputDecoration(labelText: 'Minutos que suma por semana'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );

    if (guardar != true) return;
    if (nombreCtrl.text.trim().isEmpty || asignaturaDestinoId == null) return;
    final minutos = int.tryParse(minutosCtrl.text.trim()) ?? 0;

    if (existente == null) {
      final uid = AuthService().usuarioActual?.uid ?? '';
      await db.crearPlusOrquesta(PlusOrquesta(
        nombre: nombreCtrl.text.trim(),
        asignaturaDestinoId: asignaturaDestinoId!,
        minutosSemana: minutos,
        createdAt: DateTime.now(),
        createdBy: uid,
      ));
    } else {
      await db.actualizarPlusOrquesta(existente.id!, {
        'nombre': nombreCtrl.text.trim(),
        'asignaturaDestinoId': asignaturaDestinoId,
        'minutosSemana': minutos,
      });
    }
  }

  Future<void> _eliminar(BuildContext context, PlusOrquesta plus) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar plus de orquesta'),
        content: Text(
            '¿Eliminar "${plus.nombre}"? Las matrículas que ya lo llevan aplicado dejarán de sumar esos minutos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmar == true) {
      await DbService().eliminarPlusOrquesta(plus.id!);
    }
  }
}
