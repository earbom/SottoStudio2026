import 'dart:convert';
import 'package:http/http.dart' as http;

/// Un mensaje del historial de la conversación con el asistente —
/// vive solo en memoria (se pierde al cerrar el panel/la app), no se
/// guarda en Firestore ni en local.
class MensajeAsistente {
  final String texto;
  final bool esUsuario;

  MensajeAsistente({required this.texto, required this.esUsuario});
}

/// Cliente HTTP hacia el backend PROPIO del asistente (ver CLAUDE.md):
/// esta clase NUNCA habla con la API de Anthropic directamente — la
/// clave de esa API vive solo en el servidor propio del centro (la
/// Orange Pi de la que se habló), nunca en la app. Aquí solo se envía
/// el mensaje del usuario y el historial reciente, y se muestra la
/// respuesta de texto que devuelva ese servidor.
///
/// **Contrato HTTP esperado del backend** (a definir/ajustar cuando el
/// servidor exista de verdad — esto es el lado de la app "dejado
/// preparado", ver CLAUDE.md):
/// - `POST <asistenteUrl>` con cuerpo JSON
///   `{"mensaje": "...", "historial": [{"rol": "usuario"|"asistente", "texto": "..."}, ...]}`.
/// - Respuesta 200 con cuerpo JSON `{"respuesta": "..."}`.
/// - Cualquier ejecución real de acciones sobre Firestore (matricular,
///   mover horario, etc.) queda pendiente de diseñar junto con ese
///   backend — hoy esta clase solo muestra texto, no ejecuta nada por
///   su cuenta contra `DbService`.
/// - En la versión web de la app, el navegador exige que ESE servidor
///   responda con cabeceras CORS (`Access-Control-Allow-Origin`) que
///   permitan el origen desde el que se sirve Sotto Studio — si no,
///   la petición fallará solo en web, aunque funcione en
///   Android/macOS. Tenerlo en cuenta al montar el backend.
class AsistenteService {
  Future<String> enviarMensaje({
    required String url,
    required String mensaje,
    required List<MensajeAsistente> historial,
  }) async {
    if (url.isEmpty) {
      return 'Todavía no hay ningún servidor del asistente configurado. '
          'Dirección puede añadir la URL en Ajustes cuando esté listo.';
    }
    try {
      final respuesta = await http
          .post(
            Uri.parse(url),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mensaje': mensaje,
              'historial': historial
                  .map((m) => {'rol': m.esUsuario ? 'usuario' : 'asistente', 'texto': m.texto})
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (respuesta.statusCode != 200) {
        return 'El asistente respondió con un error (${respuesta.statusCode}).';
      }
      final data = jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>;
      return data['respuesta'] as String? ?? 'El asistente no devolvió ninguna respuesta.';
    } catch (e) {
      return 'No se pudo contactar con el asistente: $e';
    }
  }
}
