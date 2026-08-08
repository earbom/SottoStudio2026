import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../utils/excel_marcajes.dart';
import 'ajustes_service.dart';
import 'db_service.dart';

final _formatoMes = DateFormat('yyyy-MM');

/// Genera automáticamente, al abrir la app, el Excel de fichajes del
/// mes recién cerrado en la carpeta que dirección elija en Ajustes —
/// para tener siempre una copia local sin depender de acordarse de
/// exportar a mano. La fuente de verdad sigue siendo `marcajes` en
/// Firestore (nunca se puede borrar, ver CLAUDE.md punto 15); esto es
/// solo una copia de conveniencia/archivo.
///
/// Solo tiene sentido en escritorio: usa `dart:io` para escribir el
/// archivo directamente en una ruta elegida por el usuario, algo que
/// no existe como concepto en web (no hay sistema de archivos propio
/// al que la app pueda escribir en silencio).
class ExportacionAutomaticaMarcajesService {
  final DbService db;
  final AjustesService ajustes;

  ExportacionAutomaticaMarcajesService(this.db, this.ajustes);

  /// [forzar] ignora el "ya se exportó este mes" — usado por el botón
  /// manual "Exportar mes anterior ahora" en Ajustes.
  Future<void> comprobarYExportarSiToca({bool forzar = false}) async {
    if (kIsWeb) return;
    final carpeta = ajustes.carpetaExportacionMarcajes;
    if (carpeta.isEmpty) return;

    final ahora = DateTime.now();
    final mesAnterior = DateTime(ahora.year, ahora.month - 1, 1);
    final claveMes = _formatoMes.format(mesAnterior);
    if (!forzar && ajustes.ultimaExportacionMarcajesMes == claveMes) return;

    final desde = mesAnterior;
    final hasta = DateTime(mesAnterior.year, mesAnterior.month + 1, 1).subtract(const Duration(days: 1));
    final marcajes = await db.marcajesEnRango(desde: desde, hasta: hasta).first;

    if (marcajes.isEmpty) {
      // Nada que exportar ese mes; se marca igualmente como hecho para
      // no repetir la comprobación en cada apertura de la app.
      await ajustes.registrarExportacionMarcajesRealizada(claveMes);
      return;
    }

    final trabajadores = await db.trabajadoresDelCentro().first;
    final nombres = {for (final t in trabajadores) t.uid: t.nombre};
    final bytes = generarExcelMarcajes(marcajes, nombres);

    final archivo = File('$carpeta${Platform.pathSeparator}registro_horario_$claveMes.xlsx');
    await archivo.writeAsBytes(bytes);
    await ajustes.registrarExportacionMarcajesRealizada(claveMes);
  }
}
