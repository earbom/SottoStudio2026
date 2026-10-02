import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/asignatura.dart';
import '../../models/curso.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../services/ajustes_service.dart';
import '../../services/db_service.dart';
import '../../utils/iconos_asignatura.dart';
import 'asignatura_detalle_screen.dart';
import '../../widgets/error_carga.dart';
import 'secciones_asignatura_screen.dart';

/// Cursos que ofrecen una asignatura con el nombre elegido en
/// `AsignaturasPorNombreScreen` — cada elemento es un documento
/// `Asignatura` distinto (mismo nombre, distinto curso). Orden fijo
/// Asignatura → Curso → Menú (ver CLAUDE.md): elegir un curso aquí es
/// SIEMPRE el segundo paso para cualquier rol, antes de decidir qué
/// hacer con él — dirección va directa a `AsignaturaDetalleScreen`
/// (como siempre); profesor puro pasa por el menú de secciones de
/// `SeccionesAsignaturaScreen` (Asistencias/Notas/Horas/Vista global).
class AsignaturaNombreCursosScreen extends StatelessWidget {
  final String nombreGrupo;
  final List<Asignatura> asignaturas;
  final Usuario perfil;

  const AsignaturaNombreCursosScreen({
    super.key,
    required this.nombreGrupo,
    required this.asignaturas,
    required this.perfil,
  });

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    final esProfesorPuro = perfil.esProfesor && !perfil.esDireccion;
    return Scaffold(
      appBar: AppBar(title: Text(nombreGrupo)),
      body: StreamBuilder<String>(
        stream: db.cursoEscolarActivo(),
        builder: (context, snapActivo) {
          if (snapActivo.hasError) {
            return const ErrorCarga();
          }
          if (!snapActivo.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cursoEscolar = snapActivo.data!;
          void abrir(Asignatura asignatura) => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => esProfesorPuro
                      ? SeccionesAsignaturaScreen(
                          asignatura: asignatura, perfil: perfil, cursoEscolar: cursoEscolar)
                      : AsignaturaDetalleScreen(asignatura: asignatura, perfil: perfil),
                ),
              );

          // Profesor puro: cuadrícula de iconos, como ya usa dirección
          // en CursosScreen/CursoDetalleScreen — pedido explícitamente
          // por dirección. Dirección conserva la lista.
          if (esProfesorPuro) {
            final escalaIconos = context.watch<AjustesService>().escalaIconos;
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 140,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.85,
              ),
              itemCount: asignaturas.length,
              itemBuilder: (context, i) {
                final asignatura = asignaturas[i];
                return FutureBuilder<Curso?>(
                  future: db.curso(asignatura.cursoId),
                  builder: (context, snapCurso) {
                    final curso = snapCurso.data;
                    final icono = iconoAsignaturaPorId(curso?.iconoId ?? '');
                    return StreamBuilder<List<Matricula>>(
                      stream: db.matriculasDeAsignatura(asignatura.id!, cursoEscolar: cursoEscolar),
                      builder: (context, snapMatriculas) {
                        final nMatriculados = snapMatriculas.data?.length ?? 0;
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => abrir(asignatura),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 64 * escalaIconos,
                                height: 64 * escalaIconos,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                ),
                                child: Center(
                                  child: FaIcon(
                                    icono.icono,
                                    size: 28 * escalaIconos,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                curso?.nombre ?? 'Cargando…',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '$nMatriculados ${nMatriculados == 1 ? 'alumno' : 'alumnos'}',
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
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
          }

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
                        subtitle: Text('$nMatriculados ${nMatriculados == 1 ? 'alumno' : 'alumnos'}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => abrir(asignatura),
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
