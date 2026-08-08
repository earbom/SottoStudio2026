import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../models/asignatura.dart';
import '../../services/auth_service.dart';
import '../../services/db_service.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
const _nombresDiasSemana = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

String _formatearFechaConDia(DateTime fecha) =>
    '${_nombresDiasSemana[fecha.weekday - 1]} ${_formatoFecha.format(fecha)}';

class _AsistenciaPendiente {
  final Matricula matricula;
  final DateTime fecha;
  _AsistenciaPendiente(this.matricula, this.fecha);
}

/// Detecta, para cada alumno matriculado con días de clase asignados,
/// qué días de los últimos [diasAtras] no tienen asistencia marcada
/// (ni asistió ni faltó registrado) — para que no se quede nada suelto,
/// igual que "notas pendientes de supervisión" para las notas.
class AsistenciaPendienteScreen extends StatefulWidget {
  const AsistenciaPendienteScreen({super.key});

  static const diasAtras = 7;

  @override
  State<AsistenciaPendienteScreen> createState() => _AsistenciaPendienteScreenState();
}

class _AsistenciaPendienteScreenState extends State<AsistenciaPendienteScreen> {
  final _db = DbService();
  final _auth = AuthService();
  Future<List<_AsistenciaPendiente>>? _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _calcularPendientes();
  }

  void _refrescar() {
    setState(() => _futuro = _calcularPendientes());
  }

  Future<List<_AsistenciaPendiente>> _calcularPendientes() async {
    final cursoEscolar = await _db.cursoEscolarActivo().first;
    final matriculas = await _db.todasLasMatriculasActivas(cursoEscolar: cursoEscolar).first;
    final hoy = DateTime.now();
    final hoySoloFecha = DateTime(hoy.year, hoy.month, hoy.day);
    final pendientes = <_AsistenciaPendiente>[];

    for (final matricula in matriculas) {
      if (matricula.diasSemana.isEmpty) continue;
      final fechaAltaSoloFecha =
          DateTime(matricula.fechaAlta.year, matricula.fechaAlta.month, matricula.fechaAlta.day);

      for (var i = 0; i < AsistenciaPendienteScreen.diasAtras; i++) {
        final dia = hoySoloFecha.subtract(Duration(days: i));
        if (dia.isBefore(fechaAltaSoloFecha)) continue;
        if (!matricula.diasSemana.contains(dia.weekday)) continue;

        final asistencia = await _db.asistenciaDelDia(
          alumnoId: matricula.alumnoId,
          asignaturaId: matricula.asignaturaId,
          fecha: dia,
        );
        if (asistencia == null) {
          pendientes.add(_AsistenciaPendiente(matricula, dia));
        }
      }
    }

    pendientes.sort((a, b) => b.fecha.compareTo(a.fecha));
    return pendientes;
  }

  Future<void> _marcar(_AsistenciaPendiente pendiente, bool asistio) async {
    await _db.marcarAsistencia(
      alumnoId: pendiente.matricula.alumnoId,
      asignaturaId: pendiente.matricula.asignaturaId,
      fecha: pendiente.fecha,
      asistio: asistio,
      marcadaPor: _auth.usuarioActual?.uid ?? '',
    );
    _refrescar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<_AsistenciaPendiente>>(
        future: _futuro,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final pendientes = snapshot.data!;
          if (pendientes.isEmpty) {
            return const Center(child: Text('No hay asistencia sin marcar en los últimos días.'));
          }
          return ListView.separated(
            itemCount: pendientes.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final pendiente = pendientes[i];
              return FutureBuilder<Usuario?>(
                future: _db.obtenerUsuario(pendiente.matricula.alumnoId),
                builder: (context, snapAlumno) {
                  final nombreAlumno = snapAlumno.data?.nombre ?? pendiente.matricula.alumnoId;
                  return FutureBuilder<Asignatura?>(
                    future: _db.asignatura(pendiente.matricula.asignaturaId),
                    builder: (context, snapAsignatura) {
                      final nombreAsignatura = snapAsignatura.data?.nombre ?? '…';
                      return ListTile(
                        title: Text('$nombreAlumno · $nombreAsignatura'),
                        subtitle: Text(_formatearFechaConDia(pendiente.fecha)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              tooltip: 'Asistió',
                              onPressed: () => _marcar(pendiente, true),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              tooltip: 'Faltó',
                              onPressed: () => _marcar(pendiente, false),
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
    );
  }
}
