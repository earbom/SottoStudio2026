import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/grabador_estudio_widget.dart';

/// Pantalla central de la app: el alumno graba su sesión de estudio
/// y ve en vivo el tiempo efectivo vs. el tiempo total. Siempre ligada
/// a una asignatura de instrumento concreta (`asignaturaId` no es
/// opcional): ya no existe la práctica libre sin asignatura — las
/// horas registradas deben corresponder estrictamente a una
/// asignatura con `permiteGrabarEstudio == true` (ver CLAUDE.md).
///
/// Envoltorio fino de `GrabadorEstudioWidget` (extraído para poder
/// reutilizarlo también desde `EmpezarEstudioScreen`, que añade un
/// desplegable de asignatura por encima).
class GrabarEstudioScreen extends StatelessWidget {
  final String alumnoId;
  final String? instrumento;
  final String asignaturaId;

  const GrabarEstudioScreen({
    super.key,
    required this.alumnoId,
    this.instrumento,
    required this.asignaturaId,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.grabarEstudioTitulo)),
      body: Center(
        child: GrabadorEstudioWidget(
          alumnoId: alumnoId,
          instrumento: instrumento,
          asignaturaId: asignaturaId,
        ),
      ),
    );
  }
}
