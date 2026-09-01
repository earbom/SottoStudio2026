import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/curso.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import 'asignatura_detalle_screen.dart';
import 'asistencias_asignatura_screen.dart';
import 'horas_asignatura_screen.dart';
import 'notas_asignatura_grid_screen.dart';
import 'secciones_asignatura_screen.dart';

/// Lista de cursos que ofrecen una asignatura con el nombre elegido en
/// `AsignaturasPorNombreScreen` — cada fila es un documento
/// `Asignatura` distinto (mismo nombre, distinto curso).
///
/// `seccion` (no nula solo en el flujo de profesor puro, ver
/// `SeccionesAsignaturaScreen` y CLAUDE.md): cuando viene fijada,
/// elegir un curso lleva DIRECTO a la pantalla de esa sección para
/// ese curso+asignatura, sin pasar por `AsignaturaDetalleScreen`. Con
/// `seccion == null` (flujo de dirección, sin cambios) el
/// comportamiento es idéntico al de siempre.
class AsignaturaNombreCursosScreen extends StatelessWidget {
  final String nombreGrupo;
  final List<Asignatura> asignaturas;
  final Usuario perfil;
  final SeccionAsignatura? seccion;

  const AsignaturaNombreCursosScreen({
    super.key,
    required this.nombreGrupo,
    required this.asignaturas,
    required this.perfil,
    this.seccion,
  });

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      appBar: AppBar(title: Text(nombreGrupo)),
      body: StreamBuilder<String>(
        stream: db.cursoEscolarActivo(),
        builder: (context, snapActivo) {
          if (!snapActivo.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cursoEscolar = snapActivo.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: asignaturas.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final asignatura = asignaturas[i];
              return FutureBuilder<Curso?>(
                future: db.curso(asignatura.cursoId),
                builder: (context, snapCurso) {
                  final curso = snapCurso.data;
                  return StreamBuilder<List<Matricula>>(
                    stream: db.matriculasDeAsignatura(asignatura.id!, cursoEscolar: cursoEscolar),
                    builder: (context, snapMatriculas) {
                      final nMatriculados = snapMatriculas.data?.length ?? 0;
                      return ListTile(
                        leading: const Icon(Icons.school_outlined),
                        title: Text(curso?.nombre ?? 'Cargando…'),
                        subtitle: Text('$nMatriculados alumno(s)'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) {
                              if (seccion == null) {
                                return AsignaturaDetalleScreen(asignatura: asignatura, perfil: perfil);
                              }
                              switch (seccion!) {
                                case SeccionAsignatura.asistencias:
                                  return AsistenciasAsignaturaScreen(
                                      asignatura: asignatura, perfil: perfil, cursoEscolar: cursoEscolar);
                                case SeccionAsignatura.notas:
                                  return NotasAsignaturaGridScreen(
                                      asignatura: asignatura, perfil: perfil, cursoEscolar: cursoEscolar);
                                case SeccionAsignatura.horas:
                                  return HorasAsignaturaScreen(asignatura: asignatura, perfil: perfil);
                              }
                            },
                          ),
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
