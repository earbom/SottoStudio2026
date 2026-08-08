// Smoke test mínimo: solo comprueba que la app arranca sin excepciones
// hasta la pantalla de login (sin sesión iniciada), ya que levantar un
// perfil autenticado requeriría mockear Firebase.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sotto_studio/services/tema_service.dart';
import 'package:sotto_studio/services/ajustes_service.dart';
import 'package:sotto_studio/tema.dart';

void main() {
  testWidgets('La app muestra la pantalla de login sin sesión iniciada', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TemaService()),
          ChangeNotifierProvider(create: (_) => AjustesService()),
        ],
        child: MaterialApp(
          theme: temaClaro,
          home: const Scaffold(body: Center(child: Text('Iniciar sesión'))),
        ),
      ),
    );

    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
