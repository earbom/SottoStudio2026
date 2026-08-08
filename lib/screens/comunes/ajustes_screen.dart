import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/usuario.dart';
import '../../services/ajustes_service.dart';
import '../../services/db_service.dart';
import '../../services/exportacion_automatica_marcajes_service.dart';
import '../../utils/iconos_asignatura.dart';

class AjustesScreen extends StatefulWidget {
  final Usuario perfil;

  const AjustesScreen({super.key, required this.perfil});

  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  bool _exportando = false;

  Future<void> _elegirCarpetaExportacion(AjustesService ajustes) async {
    final ruta = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Carpeta para el Excel mensual de fichajes',
    );
    if (ruta == null) return;
    await ajustes.cambiarCarpetaExportacionMarcajes(ruta);
  }

  Future<void> _exportarAhora(AjustesService ajustes) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _exportando = true);
    try {
      await ExportacionAutomaticaMarcajesService(DbService(), ajustes)
          .comprobarYExportarSiToca(forzar: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.ajustesExportacionExito)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.ajustesExportacionError('$e'))),
      );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ajustes = context.watch<AjustesService>();
    // La exportación automática escribe con dart:io en una carpeta
    // local, algo que no existe como concepto en web — y solo tiene
    // sentido para dirección, que es quien gestiona el registro
    // horario del centro.
    final mostrarExportacion = !kIsWeb && widget.perfil.esDireccion;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.ajustesTitulo)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.ajustesIdioma, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'es', label: Text(l10n.ajustesIdiomaCastellano)),
              ButtonSegment(value: 'ca', label: Text(l10n.ajustesIdiomaCatalan)),
            ],
            selected: {ajustes.idioma.languageCode},
            onSelectionChanged: (s) => ajustes.cambiarIdioma(Locale(s.first)),
          ),
          const Divider(height: 40),
          Text(l10n.ajustesTamanoLetra, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            l10n.ajustesTextoEjemplo,
            style: TextStyle(fontSize: 16 * ajustes.escalaFuente),
          ),
          Slider(
            min: AjustesService.escalaFuenteMinima,
            max: AjustesService.escalaFuenteMaxima,
            divisions: 9,
            value: ajustes.escalaFuente,
            label: '${(ajustes.escalaFuente * 100).round()}%',
            onChanged: (v) => ajustes.cambiarEscalaFuente(v),
          ),
          const SizedBox(height: 24),
          Text(l10n.ajustesTamanoIconos, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(l10n.ajustesTamanoIconosDescripcion,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 64 * ajustes.escalaIconos,
              height: 64 * ajustes.escalaIconos,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Center(
                child: FaIcon(
                  iconosAsignaturaDisponibles.first.icono,
                  size: 28 * ajustes.escalaIconos,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          Slider(
            min: AjustesService.escalaIconosMinima,
            max: AjustesService.escalaIconosMaxima,
            divisions: 6,
            value: ajustes.escalaIconos,
            label: '${(ajustes.escalaIconos * 100).round()}%',
            onChanged: (v) => ajustes.cambiarEscalaIconos(v),
          ),
          const Divider(height: 40),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.ajustesConfirmarCierreSesion),
            subtitle: Text(l10n.ajustesConfirmarCierreSesionDescripcion),
            value: ajustes.confirmarCierreSesion,
            onChanged: (v) => ajustes.cambiarConfirmarCierreSesion(v),
          ),
          if (mostrarExportacion) ...[
            const Divider(height: 40),
            Text(l10n.ajustesExportacionTitulo, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              l10n.ajustesExportacionDescripcion,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined),
              title: Text(
                ajustes.carpetaExportacionMarcajes.isEmpty
                    ? l10n.ajustesSinConfigurar
                    : ajustes.carpetaExportacionMarcajes,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: TextButton(
                onPressed: () => _elegirCarpetaExportacion(ajustes),
                child: Text(l10n.ajustesElegirCarpeta),
              ),
            ),
            if (ajustes.carpetaExportacionMarcajes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Center(
                child: OutlinedButton.icon(
                  icon: _exportando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.file_download_outlined),
                  label: Text(l10n.ajustesExportarAhora),
                  onPressed: _exportando ? null : () => _exportarAhora(ajustes),
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
          Center(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt),
              label: Text(l10n.ajustesRestablecer),
              onPressed: () => ajustes.restablecer(),
            ),
          ),
        ],
      ),
    );
  }
}
