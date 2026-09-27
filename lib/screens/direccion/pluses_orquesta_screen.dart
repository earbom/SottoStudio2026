import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/plus_orquesta.dart';
import '../../services/auth_service.dart';
import '../../services/db_service.dart';

/// Catálogo de pluses de horas por orquesta, gestionado por dirección
/// (pedido en el piloto): p.ej. "Orquesta de guitarras" suma horas/
/// semana fijas a la asignatura "Guitarra" — se elige uno al matricular
/// a un alumno en la asignatura de orquesta (ver
/// `_configurarMatricula` en `asignatura_detalle_screen.dart` y
/// `Matricula.plusOrquestaId`). El plus en sí no está atado a NINGUNA
/// asignatura de origen — cualquier matrícula puede llevarlo, es
/// dirección quien decide en qué matrícula tiene sentido aplicarlo.
class PlusesOrquestaScreen extends StatelessWidget {
  const PlusesOrquestaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      appBar: AppBar(title: const Text('Pluses de orquesta')),
      body: StreamBuilder<List<Asignatura>>(
        stream: db.todasLasAsignaturas(),
        builder: (context, snapAsignaturas) {
          if (!snapAsignaturas.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final asignaturaPorId = {for (final a in snapAsignaturas.data!) a.id!: a};
          return StreamBuilder<List<PlusOrquesta>>(
            stream: db.plusesOrquesta(),
            builder: (context, snapshot) {
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
                  return ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text(plus.nombre),
                    subtitle: Text(
                        'Suma +${plus.horasSemana.toStringAsFixed(1)} h/semana a ${destino?.nombre ?? "(asignatura eliminada)"}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _crearOEditar(context, snapAsignaturas.data!, existente: plus),
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
      ),
      floatingActionButton: StreamBuilder<List<Asignatura>>(
        stream: db.todasLasAsignaturas(),
        builder: (context, snap) {
          return FloatingActionButton(
            onPressed: snap.hasData ? () => _crearOEditar(context, snap.data!) : null,
            child: const Icon(Icons.add),
          );
        },
      ),
    );
  }

  Future<void> _crearOEditar(BuildContext context, List<Asignatura> asignaturas,
      {PlusOrquesta? existente}) async {
    final db = DbService();
    final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
    final horasCtrl =
        TextEditingController(text: existente != null ? existente.horasSemana.toStringAsFixed(1) : '');
    String? asignaturaDestinoId = existente?.asignaturaDestinoId;

    final asignaturasOrdenadas = [...asignaturas]..sort((a, b) => a.nombre.compareTo(b.nombre));

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
                  decoration: const InputDecoration(labelText: 'Asignatura a la que suma horas'),
                  items: asignaturasOrdenadas
                      .map((a) => DropdownMenuItem(value: a.id, child: Text(a.nombre)))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => asignaturaDestinoId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: horasCtrl,
                  decoration: const InputDecoration(labelText: 'Horas que suma por semana'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
    final horas = double.tryParse(horasCtrl.text.replaceAll(',', '.')) ?? 0;

    if (existente == null) {
      final uid = AuthService().usuarioActual?.uid ?? '';
      await db.crearPlusOrquesta(PlusOrquesta(
        nombre: nombreCtrl.text.trim(),
        asignaturaDestinoId: asignaturaDestinoId!,
        horasSemana: horas,
        createdAt: DateTime.now(),
        createdBy: uid,
      ));
    } else {
      await db.actualizarPlusOrquesta(existente.id!, {
        'nombre': nombreCtrl.text.trim(),
        'asignaturaDestinoId': asignaturaDestinoId,
        'horasSemana': horas,
      });
    }
  }

  Future<void> _eliminar(BuildContext context, PlusOrquesta plus) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar plus de orquesta'),
        content: Text(
            '¿Eliminar "${plus.nombre}"? Las matrículas que ya lo llevan aplicado dejarán de sumar esas horas.'),
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
