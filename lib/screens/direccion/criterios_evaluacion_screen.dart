import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/criterio_evaluacion.dart';
import '../../services/auth_service.dart';
import '../../widgets/error_carga.dart';
import '../../services/db_service.dart';

/// Dirección define aquí, por asignatura, qué actividades/controles
/// puntúan y qué peso (%) tiene cada uno en la nota final. El profesor
/// solo elige uno de estos criterios al poner una nota (ver
/// alumno_en_asignatura_screen.dart), no re-introduce el peso.
class CriteriosEvaluacionScreen extends StatefulWidget {
  final Asignatura asignatura;

  const CriteriosEvaluacionScreen({super.key, required this.asignatura});

  @override
  State<CriteriosEvaluacionScreen> createState() => _CriteriosEvaluacionScreenState();
}

class _CriteriosEvaluacionScreenState extends State<CriteriosEvaluacionScreen> {
  final DbService _db = DbService();
  final AuthService _auth = AuthService();
  Future<void> _crearOEditarCriterio({CriterioEvaluacion? existente}) async {
    final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
    final pesoCtrl = TextEditingController(text: existente?.peso.toStringAsFixed(0) ?? '');

    final guardar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existente == null ? 'Nuevo criterio' : 'Editar criterio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre (ej. Control 1r trimestre)'),
              autofocus: true,
            ),
            TextField(
              controller: pesoCtrl,
              decoration: const InputDecoration(labelText: 'Peso en la nota final (%)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (guardar != true || nombreCtrl.text.trim().isEmpty) return;
    final peso = double.tryParse(pesoCtrl.text.replaceAll(',', '.')) ?? 0;

    if (existente == null) {
      final uid = _auth.usuarioActual?.uid ?? '';
      await _db.crearCriterio(CriterioEvaluacion(
        asignaturaId: widget.asignatura.id!,
        nombre: nombreCtrl.text.trim(),
        peso: peso,
        createdAt: DateTime.now(),
        createdBy: uid,
      ));
    } else {
      await _db.actualizarCriterio(existente.id!, {
        'nombre': nombreCtrl.text.trim(),
        'peso': peso,
      });
    }
  }

  Future<void> _eliminar(CriterioEvaluacion criterio) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar criterio'),
        content: Text('¿Eliminar "${criterio.nombre}"? Las notas ya puestas con este criterio quedarán sin peso asociado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmar == true) {
      await _db.eliminarCriterio(criterio.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Criterios de evaluación · ${widget.asignatura.nombre}')),
      body: StreamBuilder<List<CriterioEvaluacion>>(
        stream: _db.criteriosDeAsignatura(widget.asignatura.id!),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorCarga();
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final criterios = snapshot.data!;
          final pesoTotal = criterios.fold<double>(0, (acc, c) => acc + c.peso);

          return Column(
            children: [
              Container(
                width: double.infinity,
                color: (pesoTotal - 100).abs() < 0.01
                    ? Colors.green.withValues(alpha: 0.15)
                    : Colors.orange.withValues(alpha: 0.15),
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Peso total asignado: ${pesoTotal.toStringAsFixed(0)}%'
                  '${(pesoTotal - 100).abs() < 0.01 ? '' : ' (debería sumar 100%)'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: criterios.isEmpty
                    ? const Center(child: Text('Aún no hay criterios de evaluación definidos.'))
                    : ListView.separated(
                        itemCount: criterios.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final criterio = criterios[i];
                          return ListTile(
                            title: Text(criterio.nombre),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${criterio.peso.toStringAsFixed(0)}%',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _crearOEditarCriterio(existente: criterio),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _eliminar(criterio),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _crearOEditarCriterio(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
