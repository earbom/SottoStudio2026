import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/criterio_evaluacion.dart';
import '../../models/nota.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';

/// Dirección valida la NOTA FINAL de un alumno en una asignatura, solo
/// cuando ya tiene nota en TODOS los criterios configurados (ver
/// `DbService.notasFinalesPorValidar`, compartido con el panel de
/// avisos de Inicio). Los incompletos no se listan, pero se dice
/// cuántos hay para que no parezca que "faltan" notas sin motivo.
class NotasPendientesScreen extends StatefulWidget {
  const NotasPendientesScreen({super.key});

  @override
  State<NotasPendientesScreen> createState() => _NotasPendientesScreenState();
}

class _NotasPendientesScreenState extends State<NotasPendientesScreen> {
  final _db = DbService();
  late Future<({List<({String alumnoId, String asignaturaId, List<String> notaIds, double notaFinal})> listas, int incompletas})>
      _futuro = _db.notasFinalesPorValidar();

  void _refrescar() => setState(() => _futuro = _db.notasFinalesPorValidar());

  Future<void> _marcar(List<String> ids, EstadoNota estado, String quien) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _db.actualizarEstadoNotas(ids, estado);
      messenger.showSnackBar(SnackBar(content: Text('Nota final de $quien validada.')));
      _refrescar();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo guardar. Inténtalo de nuevo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder(
        future: _futuro,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('No se pudieron cargar las notas pendientes.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final listas = snapshot.data!.listas;
          final incompletas = snapshot.data!.incompletas;
          return RefreshIndicator(
            onRefresh: () async => _refrescar(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (listas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No hay notas finales pendientes de validar.')),
                  ),
                for (final g in listas)
                  _TarjetaNotaFinal(
                    key: ValueKey('${g.alumnoId}_${g.asignaturaId}'),
                    db: _db,
                    alumnoId: g.alumnoId,
                    asignaturaId: g.asignaturaId,
                    notaFinal: g.notaFinal,
                    onMarcar: (estado, quien) => _marcar(g.notaIds, estado, quien),
                  ),
                if (incompletas > 0)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$incompletas alumno(s) tienen notas pendientes pero aún les falta nota en algún '
                            'criterio de evaluación. Aparecerán aquí en cuanto el profesor complete todos los criterios.',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TarjetaNotaFinal extends StatelessWidget {
  final DbService db;
  final String alumnoId;
  final String asignaturaId;
  final double notaFinal;
  final void Function(EstadoNota estado, String quien) onMarcar;

  const _TarjetaNotaFinal({
    super.key,
    required this.db,
    required this.alumnoId,
    required this.asignaturaId,
    required this.notaFinal,
    required this.onMarcar,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Usuario?, Asignatura?, List<CriterioEvaluacion>, List<Nota>)>(
      future: Future.wait([
        db.obtenerUsuario(alumnoId),
        db.asignatura(asignaturaId),
        db.criteriosDeAsignatura(asignaturaId).first,
        db.notasDeAlumno(alumnoId).first,
      ]).then((r) => (
            r[0] as Usuario?,
            r[1] as Asignatura?,
            r[2] as List<CriterioEvaluacion>,
            (r[3] as List<Nota>).where((n) => n.asignaturaId == asignaturaId).toList(),
          )),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Card(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(title: Text('Cargando…')),
          );
        }
        final (alumno, asignatura, criterios, notas) = snap.data!;
        final nombreAlumno = alumno == null
            ? 'Alumno'
            : ((alumno.apellidos?.isNotEmpty ?? false) ? '${alumno.nombre} ${alumno.apellidos}' : alumno.nombre);
        Nota? ultima(String criterioId) {
          final delCriterio = notas.where((n) => n.criterioId == criterioId).toList()
            ..sort((a, b) => b.fecha.compareTo(a.fecha));
          return delCriterio.isEmpty ? null : delCriterio.first;
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$nombreAlumno · ${asignatura?.nombre ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Nota final: ${notaFinal.toStringAsFixed(2).replaceAll('.', ',')}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final c in criterios)
                  Text('• ${c.nombre} (${c.peso.toStringAsFixed(0)}%): '
                      '${ultima(c.id!)?.valor.toStringAsFixed(1).replaceAll('.', ',') ?? '—'}'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => onMarcar(EstadoNota.supervisada, nombreAlumno),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Validar nota final'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
