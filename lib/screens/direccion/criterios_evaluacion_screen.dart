import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/criterio_evaluacion.dart';
import '../../services/auth_service.dart';
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
  late final TextEditingController _objetivoSemanalCtrl;
  late final TextEditingController _objetivoMensualCtrl;
  bool _guardandoObjetivo = false;

  @override
  void initState() {
    super.initState();
    _objetivoSemanalCtrl = TextEditingController(
        text: widget.asignatura.horasObjetivoSemanal > 0
            ? widget.asignatura.horasObjetivoSemanal.toStringAsFixed(1)
            : '');
    _objetivoMensualCtrl = TextEditingController(
        text: widget.asignatura.horasObjetivoMensual > 0
            ? widget.asignatura.horasObjetivoMensual.toStringAsFixed(1)
            : '');
  }

  @override
  void dispose() {
    _objetivoSemanalCtrl.dispose();
    _objetivoMensualCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardarObjetivoHoras() async {
    setState(() => _guardandoObjetivo = true);
    try {
      await _db.actualizarAsignatura(widget.asignatura.id!, {
        'horasObjetivoSemanal':
            double.tryParse(_objetivoSemanalCtrl.text.replaceAll(',', '.')) ?? 0,
        'horasObjetivoMensual':
            double.tryParse(_objetivoMensualCtrl.text.replaceAll(',', '.')) ?? 0,
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Objetivo de horas guardado.')));
      }
    } finally {
      if (mounted) setState(() => _guardandoObjetivo = false);
    }
  }

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
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final criterios = snapshot.data!;
          final pesoTotal = criterios.fold<double>(0, (acc, c) => acc + c.peso);

          return Column(
            children: [
              // Objetivo de horas de estudio de la asignatura (ver
              // CLAUDE.md): NO cuenta para la nota, es independiente de
              // los criterios de abajo — se guarda directamente en
              // Asignatura, no como un CriterioEvaluacion más.
              Card(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Objetivo de horas de estudio (no afecta a la nota)',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _objetivoSemanalCtrl,
                              decoration:
                                  const InputDecoration(labelText: 'Objetivo semanal (h)'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _objetivoMensualCtrl,
                              decoration:
                                  const InputDecoration(labelText: 'Objetivo mensual (h)'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.tonal(
                            onPressed: _guardandoObjetivo ? null : _guardarObjetivoHoras,
                            child: _guardandoObjetivo
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Guardar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
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
