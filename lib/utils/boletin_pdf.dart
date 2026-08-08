import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/asignatura.dart';
import '../models/criterio_evaluacion.dart';
import '../models/nota.dart';
import '../models/usuario.dart';
import 'curso_escolar.dart';

class _SeccionAsignatura {
  final Asignatura asignatura;
  final List<Nota> notas;
  final Map<String, CriterioEvaluacion> criteriosPorId;

  _SeccionAsignatura(this.asignatura, this.notas, this.criteriosPorId);
}

/// Genera el PDF del boletín de notas de un alumno para las
/// asignaturas elegidas por dirección, dentro de un curso escolar
/// concreto. Reutiliza el mismo cálculo de "nota ponderada acumulada"
/// (Σ valor × peso/100) ya usado en la pestaña Notas del detalle del
/// alumno (`_TabNotas` en alumno_en_asignatura_screen.dart). Las notas
/// se filtran por su propia fecha dentro del rango del curso escolar
/// elegido, no por el curso escolar activo en el momento de generarlo.
Future<pw.Document> generarBoletinPdf({
  required Usuario alumno,
  required String cursoEscolar,
  required List<Asignatura> asignaturas,
  required Map<String, List<CriterioEvaluacion>> criteriosPorAsignatura,
  required Map<String, List<Nota>> notasPorAsignatura,
}) async {
  final rango = rangoDeCursoEscolar(cursoEscolar);
  final doc = pw.Document();

  final secciones = asignaturas.map((asignatura) {
    final criterios = criteriosPorAsignatura[asignatura.id] ?? [];
    final criteriosPorId = {for (final c in criterios) c.id!: c};
    final notas = (notasPorAsignatura[asignatura.id] ?? [])
        .where((n) => !n.fecha.isBefore(rango.inicio) && !n.fecha.isAfter(rango.fin))
        .toList()
      ..sort((a, b) => a.fecha.compareTo(b.fecha));
    return _SeccionAsignatura(asignatura, notas, criteriosPorId);
  }).toList();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Boletín de notas', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Alumno: ${alumno.nombre}'),
              pw.Text('Curso escolar: $cursoEscolar'),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        for (final seccion in secciones) ...[
          pw.Text(seccion.asignatura.nombre, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (seccion.notas.isEmpty)
            pw.Text('Sin notas registradas en este curso escolar.', style: const pw.TextStyle(fontSize: 11))
          else ...[
            pw.Table(
              border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _celda('Criterio', negrita: true),
                    _celda('Peso', negrita: true),
                    _celda('Valor', negrita: true),
                  ],
                ),
                for (final nota in seccion.notas)
                  pw.TableRow(children: [
                    _celda(seccion.criteriosPorId[nota.criterioId]?.nombre ?? '(criterio eliminado)'),
                    _celda(seccion.criteriosPorId[nota.criterioId] != null
                        ? '${seccion.criteriosPorId[nota.criterioId]!.peso.toStringAsFixed(0)}%'
                        : '—'),
                    _celda(nota.valor.toStringAsFixed(1)),
                  ]),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Nota ponderada acumulada: ${_notaPonderada(seccion).toStringAsFixed(2)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ],
          pw.SizedBox(height: 20),
        ],
      ],
    ),
  );

  return doc;
}

double _notaPonderada(_SeccionAsignatura seccion) {
  return seccion.notas.fold<double>(0, (acc, n) {
    final criterio = seccion.criteriosPorId[n.criterioId];
    if (criterio == null) return acc;
    return acc + n.valor * criterio.peso / 100;
  });
}

pw.Widget _celda(String texto, {bool negrita = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(texto, style: pw.TextStyle(fontSize: 10, fontWeight: negrita ? pw.FontWeight.bold : null)),
  );
}
