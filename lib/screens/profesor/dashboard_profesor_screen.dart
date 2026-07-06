import 'package:flutter/material.dart';

/// TODO: listado de alumnos, gestión de módulos/ejercicios,
/// introducción de notas.
class DashboardProfesorScreen extends StatelessWidget {
  const DashboardProfesorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Panel de profesor')),
      body: const Center(child: Text('Dashboard profesor — por implementar')),
    );
  }
}
