import 'package:flutter/material.dart';
import '../models/usuario.dart';

/// Caja de búsqueda simple para listados largos (alumnos, matricular...).
class CampoBusqueda extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  const CampoBusqueda({super.key, required this.hint, required this.onChanged, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        autofocus: autofocus,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

String _sinAcentos(String t) {
  const con = 'áàäâéèëêíìïîóòöôúùüûñç';
  const sin = 'aaaaeeeeiiiioooouuuunc';
  final b = StringBuffer();
  for (final c in t.toLowerCase().split('')) {
    final i = con.indexOf(c);
    b.write(i >= 0 ? sin[i] : c);
  }
  return b.toString();
}

/// Filtra por nombre, apellidos o email, sin distinguir mayúsculas ni
/// acentos ("jose" encuentra "José").
List<Usuario> filtrarUsuarios(List<Usuario> usuarios, String busqueda) {
  final q = _sinAcentos(busqueda.trim());
  if (q.isEmpty) return usuarios;
  return usuarios
      .where((u) => _sinAcentos('${u.nombre} ${u.apellidos ?? ''} ${u.email ?? ''}').contains(q))
      .toList();
}
