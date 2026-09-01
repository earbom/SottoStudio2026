import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../models/asignatura.dart';
import '../../models/criterio_evaluacion.dart';
import '../../models/matricula.dart';
import '../../models/nota.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../utils/boletin_pdf.dart';

/// Ficha de un alumno para dirección: sus asignaturas matriculadas en
/// el curso escolar activo, con la opción de generar un boletín de
/// notas en PDF eligiendo cuáles incluir.
class AlumnoPerfilScreen extends StatefulWidget {
  final Usuario alumno;

  const AlumnoPerfilScreen({super.key, required this.alumno});

  @override
  State<AlumnoPerfilScreen> createState() => _AlumnoPerfilScreenState();
}

class _AlumnoPerfilScreenState extends State<AlumnoPerfilScreen> {
  final DbService _db = DbService();
  bool _generando = false;

  Future<void> _generarBoletin(String cursoEscolar, List<Asignatura> todas) async {
    final seleccionadas = await showDialog<List<Asignatura>>(
      context: context,
      builder: (context) => _DialogoSeleccionAsignaturas(asignaturas: todas),
    );
    if (seleccionadas == null || seleccionadas.isEmpty) return;

    setState(() => _generando = true);
    try {
      final criteriosPorAsignatura = <String, List<CriterioEvaluacion>>{};
      final notasPorAsignatura = <String, List<Nota>>{};
      final todasLasNotas = await _db.notasDeAlumno(widget.alumno.uid).first;
      for (final asignatura in seleccionadas) {
        criteriosPorAsignatura[asignatura.id!] = await _db.criteriosDeAsignatura(asignatura.id!).first;
        notasPorAsignatura[asignatura.id!] =
            todasLasNotas.where((n) => n.asignaturaId == asignatura.id).toList();
      }

      final doc = await generarBoletinPdf(
        alumno: widget.alumno,
        cursoEscolar: cursoEscolar,
        asignaturas: seleccionadas,
        criteriosPorAsignatura: criteriosPorAsignatura,
        notasPorAsignatura: notasPorAsignatura,
      );

      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) => doc.save(),
        name: 'Boletin_${widget.alumno.nombre}_$cursoEscolar',
      );
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.alumno.nombre)),
      body: StreamBuilder<String>(
        stream: _db.cursoEscolarActivo(),
        builder: (context, snapActivo) {
          if (!snapActivo.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cursoEscolar = snapActivo.data!;
          return StreamBuilder<List<Matricula>>(
            stream: _db.matriculasDeAlumno(widget.alumno.uid, cursoEscolar: cursoEscolar),
            builder: (context, snapMatriculas) {
              if (!snapMatriculas.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final matriculas = snapMatriculas.data!;
              if (matriculas.isEmpty) {
                return Center(
                  child: Text('No tiene matrículas en el curso escolar $cursoEscolar.'),
                );
              }
              return FutureBuilder<List<Asignatura>>(
                future: Future.wait(matriculas.map((m) => _db.asignatura(m.asignaturaId)))
                    .then((lista) => lista.whereType<Asignatura>().toList()),
                builder: (context, snapAsignaturas) {
                  if (!snapAsignaturas.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final asignaturas = snapAsignaturas.data!;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Curso escolar: $cursoEscolar', style: const TextStyle(color: Colors.grey)),
                            if (!widget.alumno.tieneCuenta) ...[
                              const SizedBox(height: 4),
                              const Text('Sin acceso a la app',
                                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                            ],
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: asignaturas.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) => ListTile(
                            leading: const Icon(Icons.menu_book_outlined),
                            title: Text(asignaturas[i].nombre),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: FilledButton.icon(
                          onPressed:
                              _generando || asignaturas.isEmpty ? null : () => _generarBoletin(cursoEscolar, asignaturas),
                          icon: _generando
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Generar boletín de notas'),
                        ),
                      ),
                    ],
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

class _DialogoSeleccionAsignaturas extends StatefulWidget {
  final List<Asignatura> asignaturas;

  const _DialogoSeleccionAsignaturas({required this.asignaturas});

  @override
  State<_DialogoSeleccionAsignaturas> createState() => _DialogoSeleccionAsignaturasState();
}

class _DialogoSeleccionAsignaturasState extends State<_DialogoSeleccionAsignaturas> {
  final Set<String> _seleccionadas = {};

  @override
  void initState() {
    super.initState();
    _seleccionadas.addAll(widget.asignaturas.map((a) => a.id!));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Asignaturas a incluir'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: widget.asignaturas
              .map((a) => CheckboxListTile(
                    title: Text(a.nombre),
                    value: _seleccionadas.contains(a.id),
                    onChanged: (v) => setState(() {
                      v == true ? _seleccionadas.add(a.id!) : _seleccionadas.remove(a.id);
                    }),
                  ))
              .toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            widget.asignaturas.where((a) => _seleccionadas.contains(a.id)).toList(),
          ),
          child: const Text('Generar'),
        ),
      ],
    );
  }
}
