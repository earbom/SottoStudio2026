import 'package:flutter/material.dart';

/// TODO: sustituir por el dashboard real (horas efectivas, botón
/// "grabar estudio", historial, ejercicios asignados, ranking, perfil).
class DashboardAlumnoScreen extends StatelessWidget {
  const DashboardAlumnoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi estudio')),
      body: const Center(child: Text('Dashboard alumno — por implementar')),
    );
  }
}
