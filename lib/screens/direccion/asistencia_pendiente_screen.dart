import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../models/asignatura.dart';
import '../../services/auth_service.dart';
import '../../widgets/error_carga.dart';
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
    final pendientes = await _db.asistenciasSinMarcar(diasAtras: AsistenciaPendienteScreen.diasAtras);
    return pendientes.map((p) => _AsistenciaPendiente(p.matricula, p.fecha)).toList();
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
          if (snapshot.hasError) {
            return const ErrorCarga();
          }
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
                  final nombreAlumno = snapAlumno.data?.nombre ?? '…';
                  return FutureBuilder<Asignatura?>(
                    future: _db.asignatura(pendiente.matricula.asignaturaId),
                    builder: (context, snapAsignatura) {
                      final nombreAsignatura = snapAsignatura.data?.nombre ?? '…';
                      final profesorId = pendiente.matricula.profesorId;
                      return ListTile(
                        title: Text('$nombreAlumno · $nombreAsignatura'),
                        subtitle: FutureBuilder<Usuario?>(
                          future: profesorId.isEmpty ? Future.value(null) : _db.obtenerUsuario(profesorId),
                          builder: (context, snapProfesor) => Text(
                            '${_formatearFechaConDia(pendiente.fecha)} · '
                            'Profesor: ${profesorId.isEmpty ? 'sin asignar' : (snapProfesor.data?.nombre ?? '…')}',
                          ),
                        ),
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
