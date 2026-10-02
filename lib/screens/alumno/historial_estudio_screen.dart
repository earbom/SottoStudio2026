import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/sesion_estudio.dart';
import '../../models/asignatura.dart';
import '../../widgets/error_carga.dart';
import '../../services/db_service.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy HH:mm');

class HistorialEstudioScreen extends StatelessWidget {
  final String alumnoId;

  const HistorialEstudioScreen({super.key, required this.alumnoId});

  String _formatoDuracion(int ms) {
    final totalSegundos = (ms / 1000).round();
    final minutos = totalSegundos ~/ 60;
    final segundos = totalSegundos % 60;
    return '${minutos}m ${segundos.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de estudio')),
      body: StreamBuilder<List<SesionEstudio>>(
        stream: db.historialAlumno(alumnoId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorCarga();
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sesiones = snapshot.data!;
          if (sesiones.isEmpty) {
            return const Center(child: Text('Aún no hay sesiones de estudio registradas.'));
          }

          final horasTotalesEfectivas =
              sesiones.fold<int>(0, (acc, s) => acc + s.duracionEfectivaMs) / 3600000;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Total histórico: ${horasTotalesEfectivas.toStringAsFixed(1)} h efectivas en ${sesiones.length} sesión(es)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: sesiones.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final sesion = sesiones[i];
                    return FutureBuilder<Asignatura?>(
                      future: sesion.asignaturaId == null ? Future.value(null) : db.asignatura(sesion.asignaturaId!),
                      builder: (context, snapAsignatura) {
                        final nombreAsignatura = sesion.asignaturaId == null
                            ? 'Práctica libre'
                            : (snapAsignatura.data?.nombre ?? '…');
                        return ListTile(
                          leading: Icon(
                            sesion.tipo == TipoSesion.teorico ? Icons.menu_book_outlined : Icons.music_note_outlined,
                          ),
                          title: Text(nombreAsignatura),
                          subtitle: Text(_formatoFecha.format(sesion.fechaInicio)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_formatoDuracion(sesion.duracionEfectivaMs),
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('de ${_formatoDuracion(sesion.duracionTotalMs)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
