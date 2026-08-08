import 'package:flutter/material.dart';

/// Marca "oh" del centro (ver CLAUDE.md: icono del logo de Haro,
/// distinto del wordmark completo `cropped-Haro-...png` que ya se usa
/// en `InicioScreen`). A diferencia de aquel, aquí no hace falta
/// `ColorFiltered` para adaptar a tema oscuro: el asset ya viene en
/// dos variantes de fondo sólido (blanco/letras negras y
/// negro/letras blancas) — basta con elegir el archivo correcto según
/// si el fondo detrás del logo es claro u oscuro.
class LogoOh extends StatelessWidget {
  final double size;
  final bool sobreFondoOscuro;
  final BorderRadius? borderRadius;

  const LogoOh({
    super.key,
    required this.size,
    this.sobreFondoOscuro = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final imagen = Image.asset(
      sobreFondoOscuro
          ? 'assets/images/logo_oh_fondo_negro.png'
          : 'assets/images/logo_oh_fondo_blanco.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(size * 0.22),
      child: imagen,
    );
  }
}
