import 'package:flutter/material.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import 'crear_profesor_screen.dart';
import 'profesor_asignaturas_screen.dart';
import '../../widgets/error_carga.dart';
import '../../widgets/acciones_usuario.dart';

class ProfesoradoScreen extends StatelessWidget {
  const ProfesoradoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      body: StreamBuilder<List<Usuario>>(
        stream: db.profesoresDelCentro(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorCarga();
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profesores = snapshot.data!;
          return ListView(
            children: [
              if (profesores.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Aún no hay profesores. Pulsa «Nuevo profesor» para dar de alta el primero.')),
                ),
              for (final profesor in profesores) ...[
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text((profesor.apellidos?.isNotEmpty ?? false)
                      ? '${profesor.nombre} ${profesor.apellidos}'
                      : profesor.nombre),
                  subtitle: Text(profesor.email ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ProfesorAsignaturasScreen(profesor: profesor)),
                  ),
                ),
                const Divider(height: 1),
              ],
              SeccionDadosDeBaja(stream: db.profesoresDadosDeBaja()),
              const SizedBox(height: 88),
            ],
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
