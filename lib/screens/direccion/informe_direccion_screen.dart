import 'package:flutter/material.dart';
import '../../services/db_service.dart';

/// Vista clave de dirección: horas efectivas de todos los alumnos,
/// ordenadas de mayor a menor.
class InformeDireccionScreen extends StatelessWidget {
  final DbService _db = DbService();

  InformeDireccionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informe de horas efectivas')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db.informeDireccion(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final filas = snapshot.data!;
          return ListView.separated(
            itemCount: filas.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final fila = filas[i];
              final horas = ((fila['horasEfectivasTotales'] ?? 0) as num).toStringAsFixed(1);
              return ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(fila['alumnoId']), // TODO: resolver nombre real vía join con usuarios
                trailing: Text('$horas h'),
              );
            },
          );
        },
      ),
    );
  }
}
