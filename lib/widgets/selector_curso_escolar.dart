import 'package:flutter/material.dart';

/// Botón compacto para el AppBar que muestra el curso escolar que se
/// está consultando y permite cambiarlo (ver CLAUDE.md, discriminación
/// por curso escolar). Widget propio (no `ActionChip`) con colores
/// fijados explícitamente: `ChipThemeData` global de la app no da
/// suficiente contraste sobre el fondo burdeos del AppBar.
class SelectorCursoEscolar extends StatelessWidget {
  final String cursoMostrado;
  final bool esActivo;
  final VoidCallback onPressed;

  const SelectorCursoEscolar({
    super.key,
    required this.cursoMostrado,
    required this.esActivo,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: onPrimary.withValues(alpha: 0.7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(esActivo ? Icons.event_available : Icons.history,
                  size: 16, color: onPrimary),
              const SizedBox(width: 6),
              Text(
                esActivo
                    ? 'Curso $cursoMostrado'
                    : 'Consultando $cursoMostrado (solo lectura)',
                style: TextStyle(
                    color: onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
