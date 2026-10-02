import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/asignatura.dart';
import '../../models/curso.dart';
import '../direccion/formulario_asignatura.dart';
import '../../models/usuario.dart';
import '../../services/ajustes_service.dart';
import '../../services/db_service.dart';
import '../../utils/iconos_asignatura.dart';
import '../../widgets/error_carga.dart';
import 'asignatura_nombre_cursos_screen.dart';

/// Punto de entrada principal a las asignaturas, agrupadas por
/// NOMBRE (instrumento/materia) en vez de por curso: en la práctica,
/// una misma asignatura de instrumento (p. ej. "Piano") suele darse en
/// varios cursos a la vez, y para profesor/dirección es más útil
/// encontrar primero "Piano" y elegir el curso dentro, que al revés
/// (reportado durante el piloto). `Asignatura.nombre` es texto libre
/// sin entidad normalizada — cada curso que ofrece "Piano" es un
/// documento `Asignatura` independiente que solo comparte el nombre;
/// aquí se agrupan por coincidencia EXACTA (recortada y en minúsculas,
/// sin fuzzy matching) — es una decisión deliberada, no una limitación
/// a resolver más adelante.
///
/// La gestión de cursos en sí (crear/editar/eliminar, nivel, número,
/// objetivo de horas) sigue viviendo en `CursosScreen`, accesible
/// aparte para dirección — esta pantalla no la sustituye, es la vía
/// de navegación principal para consultar/entrar en una asignatura.
class AsignaturasPorNombreScreen extends StatelessWidget {
  final Usuario perfil;

  const AsignaturasPorNombreScreen({super.key, required this.perfil});

  /// Una asignatura siempre pertenece a un curso: primero se elige el
  /// curso y luego se abre el mismo formulario que en Gestionar cursos.
  Future<void> _nuevaAsignatura(BuildContext context) async {
    final cursos = await DbService().cursos().first;
    if (!context.mounted) return;
    if (cursos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Primero crea un curso en Configuración del centro → Gestionar cursos.')));
      return;
    }
    final curso = await showDialog<Curso>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('¿En qué curso se da?'),
        children: cursos
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(c.nombre, style: const TextStyle(fontSize: 16)),
                  ),
                ))
            .toList(),
      ),
    );
    if (curso == null || !context.mounted) return;
    await crearAsignaturaEnCurso(context, curso.id!);
  }

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    // Cross-curso (ver CLAUDE.md, permiso cruzado entre cursos): un
    // profesor debe ver TODOS los cursos que ofrecen una asignatura
    // con un nombre donde él enseña, no solo el documento concreto en
    // el que dirección lo puso en profesorIds — si no, nunca
    // descubriría el curso del "otro" profesor de la misma asignatura.
    final stream =
        perfil.esDireccion ? db.todasLasAsignaturas() : db.asignaturasVisiblesParaProfesor(perfil.uid);
    // Esta pantalla se muestra embebida en el body de HomeShell (que ya
    // pone su propio AppBar con el título del menú), así que no lleva
    // AppBar propio — el botón de recalcular grupos va como FAB
    // pequeño, solo dirección, en vez de una acción de AppBar anidado.
    return Scaffold(
      floatingActionButton: perfil.esDireccion
          ? FloatingActionButton.extended(
              onPressed: () => _nuevaAsignatura(context),
              icon: const Icon(Icons.add),
              label: const Text('Nueva asignatura'),
            )
          : null,
      body: StreamBuilder<List<Asignatura>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorCarga();
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final asignaturas = snapshot.data!;
          if (asignaturas.isEmpty) {
            return Center(
              child: Text(perfil.esDireccion
                  ? 'Aún no hay asignaturas. Pulsa «Nueva asignatura» para crear la primera.'
                  : 'Todavía no tienes asignaturas asignadas.'),
            );
          }

          final grupos = <String, List<Asignatura>>{};
          for (final asignatura in asignaturas) {
            final clave = asignatura.nombre.trim().toLowerCase();
            (grupos[clave] ??= []).add(asignatura);
          }
          // El nombre/icono mostrado del grupo sale de la asignatura
          // creada primero de ese grupo, para que sean estables entre
          // reconstrucciones aunque el nombre real de cada doc tenga
          // mayúsculas/espacios ligeramente distintos.
          final entradas = grupos.values.map((lista) {
            final ordenadas = [...lista]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
            return (representante: ordenadas.first, asignaturas: lista);
          }).toList()
            ..sort((a, b) => a.representante.nombre.compareTo(b.representante.nombre));

          final escalaIconos = context.watch<AjustesService>().escalaIconos;
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: entradas.length,
            itemBuilder: (context, i) {
              final entrada = entradas[i];
              final icono = iconoAsignaturaPorId(entrada.representante.iconoId);
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                // Ambos roles pasan por el mismo paso de elegir curso
                // (orden fijo Asignatura → Curso → Menú, ver CLAUDE.md);
                // es AsignaturaNombreCursosScreen quien decide, según el
                // rol, si el siguiente paso es el menú de secciones del
                // profesor o AsignaturaDetalleScreen de dirección.
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AsignaturaNombreCursosScreen(
                      nombreGrupo: entrada.representante.nombre,
                      asignaturas: entrada.asignaturas,
                      perfil: perfil,
                    ),
                  ),
                ),
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
                      entrada.representante.nombre,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (entrada.asignaturas.length > 1)
                      Text(
                        '${entrada.asignaturas.length} cursos',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
