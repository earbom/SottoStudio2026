import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:intl/intl.dart';
import '../models/marcaje.dart';

final _formatoHora = DateFormat('HH:mm:ss');

/// Construye el libro Excel de un conjunto de fichajes — compartido
/// entre la exportación manual (`RegistroHorarioScreen`) y la
/// automática mensual (`ExportacionAutomaticaMarcajesService`) para no
/// duplicar el formato de columnas.
Uint8List generarExcelMarcajes(List<Marcaje> marcajes, Map<String, String> nombres) {
  final libro = xls.Excel.createExcel();
  final hoja = libro.getDefaultSheet()!;
  libro.appendRow(hoja, [
    xls.TextCellValue('Trabajador'),
    xls.TextCellValue('Fecha'),
    xls.TextCellValue('Hora entrada'),
    xls.TextCellValue('Hora salida'),
    xls.TextCellValue('Corregido por'),
  ]);
  for (final m in marcajes) {
    libro.appendRow(hoja, [
      xls.TextCellValue(nombres[m.empleadoId] ?? m.empleadoId),
      xls.TextCellValue(m.fecha),
      xls.TextCellValue(m.horaEntrada != null ? _formatoHora.format(m.horaEntrada!) : ''),
      xls.TextCellValue(m.horaSalida != null ? _formatoHora.format(m.horaSalida!) : ''),
      xls.TextCellValue(m.corregidoPor ?? ''),
    ]);
  }
  return Uint8List.fromList(libro.save()!);
}
