import 'package:flutter/material.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import 'crear_profesor_screen.dart';
import 'profesor_asignaturas_screen.dart';

class ProfesoradoScreen extends StatelessWidget {
  const ProfesoradoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      body: StreamBuilder<List<Usuario>>(
        stream: db.profesoresDelCentro(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profesores = snapshot.data!;
          if (profesores.isEmpty) {
            return const Center(child: Text('Aún no hay profesores dados de alta.'));
          }
          return ListView.separated(
            itemCount: profesores.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final profesor = profesores[i];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(profesor.nombre),
                subtitle: Text(profesor.email),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ProfesorAsignaturasScreen(profesor: profesor)),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CrearProfesorScreen()),
        ),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo profesor'),
      ),
    );
  }
}
