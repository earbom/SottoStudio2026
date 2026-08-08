import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/asignatura.dart';
import '../../models/curso.dart';
import '../../models/usuario.dart';
import '../../services/ajustes_service.dart';
import '../../services/auth_service.dart';
import '../../services/db_service.dart';
import '../../utils/iconos_asignatura.dart';
import 'curso_detalle_screen.dart';

class CursosScreen extends StatefulWidget {
  final Usuario perfil;

  const CursosScreen({super.key, required this.perfil});

  @override
  State<CursosScreen> createState() => _CursosScreenState();
}

class _CursosScreenState extends State<CursosScreen> {
  final DbService _db = DbService();
  final AuthService _auth = AuthService();

  String _nombreSugerido(NivelCurso nivel, int? numeroCurso) {
    if (nivel == NivelCurso.libre) return 'Estudios libres';
    if (numeroCurso == null) return nivel.etiqueta;
    return '$numeroCursoº ${nivel.etiqueta}';
  }

  // Un curso se considera "el mismo" que otro ya existente si comparte
  // nivel+número (p. ej. dos "2º Elemental" no tienen sentido — para
  // "libre", que no tiene número, se compara por nombre) o si el
  // nombre coincide literalmente (por si se ha editado a mano). Evita
  // duplicar el mismo curso por error, reportado tras probar la app.
  bool _esCursoDuplicado(
    NivelCurso nivel,
    int? numeroCurso,
    String nombre,
    List<Curso> existentes,
    String? idExcluido,
  ) {
    final nombreNormalizado = nombre.trim().toLowerCase();
    for (final c in existentes) {
      if (c.id == idExcluido) continue;
      if (nivel != NivelCurso.libre && c.nivel == nivel && c.numeroCurso == numeroCurso) {
        return true;
      }
      if (c.nombre.trim().toLowerCase() == nombreNormalizado) return true;
    }
    return false;
  }

  Future<
      ({
        String nombre,
        String? descripcion,
        NivelCurso nivel,
        int? numeroCurso,
        String iconoId,
        double horasObjetivoMensual,
      })?> _mostrarFormularioCurso({
    required List<Curso> cursosExistentes,
    String? idExcluido,
    String nombreInicial = '',
    String? descripcionInicial,
    NivelCurso nivelInicial = NivelCurso.sensibilizacion,
    int? numeroCursoInicial,
    String iconoIdInicial = '',
    double horasObjetivoMensualInicial = 0,
  }) async {
    final controladorNombre = TextEditingController(text: nombreInicial);
    final controladorDescripcion =
        TextEditingController(text: descripcionInicial ?? '');
    final controladorObjetivo = TextEditingController(
        text: horasObjetivoMensualInicial == 0
            ? ''
            : horasObjetivoMensualInicial.toString());
    var nivel = nivelInicial;
    var numeroCurso = numeroCursoInicial;
    var iconoId =
        iconoIdInicial.isEmpty ? iconosAsignaturaDisponibles.first.id : iconoIdInicial;
    var nombreAutomatico = nombreInicial.isEmpty;
    var actualizandoProgramaticamente = false;
    String? errorTexto;

    return showDialog<
        ({
          String nombre,
          String? descripcion,
          NivelCurso nivel,
          int? numeroCurso,
          String iconoId,
          double horasObjetivoMensual,
        })>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          void actualizarNombreSugerido() {
            if (!nombreAutomatico) return;
            actualizandoProgramaticamente = true;
            controladorNombre.text = _nombreSugerido(nivel, numeroCurso);
            actualizandoProgramaticamente = false;
          }

          return AlertDialog(
            title:
                Text(nombreInicial.isEmpty ? 'Nuevo curso' : 'Editar curso'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<NivelCurso>(
                    initialValue: nivel,
                    decoration: const InputDecoration(labelText: 'Nivel'),
                    items: NivelCurso.values
                        .map((n) => DropdownMenuItem(
                            value: n, child: Text(n.etiqueta)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setStateDialog(() {
                        nivel = v;
                        if (!nivel.numerosValidos.contains(numeroCurso)) {
                          numeroCurso = nivel.numerosValidos.isEmpty
                              ? null
                              : nivel.numerosValidos.first;
                        }
                        actualizarNombreSugerido();
                      });
                    },
                  ),
                  if (nivel.numerosValidos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: numeroCurso,
                      decoration:
                          const InputDecoration(labelText: 'Nº de curso'),
                      items: nivel.numerosValidos
                          .map((n) => DropdownMenuItem(
                              value: n, child: Text('$nº')))
                          .toList(),
                      onChanged: (v) => setStateDialog(() {
                        numeroCurso = v;
                        actualizarNombreSugerido();
                      }),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: controladorNombre,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    onChanged: (_) {
                      if (actualizandoProgramaticamente) return;
                      nombreAutomatico = false;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controladorDescripcion,
                    decoration: const InputDecoration(
                        labelText: 'Descripción (opcional)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controladorObjetivo,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText:
                            'Objetivo de horas efectivas al mes (0 = sin objetivo)'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Icono'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: iconosAsignaturaDisponibles.map((icono) {
                      final seleccionado = icono.id == iconoId;
                      return Tooltip(
                        message: icono.etiqueta,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () =>
                              setStateDialog(() => iconoId = icono.id),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: seleccionado
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                              border: seleccionado
                                  ? Border.all(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      width: 2)
                                  : null,
                            ),
                            child: Center(
                              child: FaIcon(
                                icono.icono,
                                size: 20,
                                color: seleccionado
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (errorTexto != null) ...[
                    const SizedBox(height: 12),
                    Text(errorTexto!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar')),
              FilledButton(
                onPressed: () {
                  final nombreFinal = controladorNombre.text.trim();
                  if (_esCursoDuplicado(
                      nivel, numeroCurso, nombreFinal, cursosExistentes, idExcluido)) {
                    setStateDialog(() => errorTexto =
                        'Ya existe un curso con ese nivel y número, o con ese nombre.');
                    return;
                  }
                  Navigator.pop(
                    context,
                    (
                      nombre: nombreFinal,
                      descripcion: controladorDescripcion.text.trim().isEmpty
                          ? null
                          : controladorDescripcion.text.trim(),
                      nivel: nivel,
                      numeroCurso: numeroCurso,
                      iconoId: iconoId,
                      horasObjetivoMensual: double.tryParse(controladorObjetivo
                              .text
                              .replaceAll(',', '.')
                              .trim()) ??
                          0,
                    ),
                  );
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _crearCurso() async {
    final cursosExistentes = await _db.cursos().first;
    if (!mounted) return;
    final resultado =
        await _mostrarFormularioCurso(cursosExistentes: cursosExistentes);
    if (resultado == null || resultado.nombre.isEmpty) return;

    final uid = _auth.usuarioActual?.uid ?? '';
    await _db.crearCurso(Curso(
      nombre: resultado.nombre,
      descripcion: resultado.descripcion,
      nivel: resultado.nivel,
      numeroCurso: resultado.numeroCurso,
      iconoId: resultado.iconoId,
      horasObjetivoMensual: resultado.horasObjetivoMensual,
      createdAt: DateTime.now(),
      createdBy: uid,
    ));
  }

  Future<void> _editarCurso(Curso curso, List<Curso> cursosExistentes) async {
    final resultado = await _mostrarFormularioCurso(
      cursosExistentes: cursosExistentes,
      idExcluido: curso.id,
      nombreInicial: curso.nombre,
      descripcionInicial: curso.descripcion,
      nivelInicial: curso.nivel,
      numeroCursoInicial: curso.numeroCurso,
      iconoIdInicial: curso.iconoId,
      horasObjetivoMensualInicial: curso.horasObjetivoMensual,
    );
    if (resultado == null || resultado.nombre.isEmpty) return;

    await _db.actualizarCurso(curso.id!, {
      'nombre': resultado.nombre,
      'descripcion': resultado.descripcion,
      'nivel': resultado.nivel.name,
      'numeroCurso': resultado.numeroCurso,
      'iconoId': resultado.iconoId,
      'horasObjetivoMensual': resultado.horasObjetivoMensual,
    });
  }

  Future<void> _eliminarCurso(Curso curso) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar curso'),
        content:
            Text('¿Eliminar "${curso.nombre}"? Solo es posible si no tiene asignaturas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _db.eliminarCurso(curso.id!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Curso>>(
        stream: _db.cursos(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cursos = snapshot.data!;
          if (cursos.isEmpty) {
            return const Center(child: Text('Aún no hay cursos creados.'));
          }
          final escalaIconos = context.watch<AjustesService>().escalaIconos;
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: cursos.length,
            itemBuilder: (context, i) {
              final curso = cursos[i];
              final icono = iconoAsignaturaPorId(curso.iconoId);
              return StreamBuilder<List<Asignatura>>(
                stream: _db.asignaturasDeCurso(curso.id!),
                builder: (context, snapAsignaturas) {
                  final nAsignaturas = snapAsignaturas.data?.length ?? 0;
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CursoDetalleScreen(
                            curso: curso, perfil: widget.perfil),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64 * escalaIconos,
                              height: 64 * escalaIconos,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                              ),
                              child: Center(
                                child: FaIcon(
                                  icono.icono,
                                  size: 28 * escalaIconos,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              curso.nombre,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '$nAsignaturas asignatura(s)',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.outline),
                            ),
                          ],
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 18),
                            tooltip: 'Opciones',
                            onSelected: (v) {
                              if (v == 'editar') _editarCurso(curso, cursos);
                              if (v == 'eliminar') _eliminarCurso(curso);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                  value: 'editar', child: Text('Editar')),
                              PopupMenuItem(
                                  value: 'eliminar', child: Text('Eliminar')),
                            ],
                          ),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _crearCurso,
        child: const Icon(Icons.add),
      ),
    );
  }
}
