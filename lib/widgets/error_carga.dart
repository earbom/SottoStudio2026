import 'package:flutter/material.dart';

/// Lo que se muestra cuando una lista no se puede cargar (sin conexión,
/// permisos...), en vez de dejar la rueda de carga girando para siempre.
class ErrorCarga extends StatelessWidget {
  const ErrorCarga({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40),
            SizedBox(height: 12),
            Text(
              'No se pudieron cargar los datos.\nComprueba la conexión a internet y vuelve a entrar.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
