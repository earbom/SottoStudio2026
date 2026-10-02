import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'l10n/app_localizations.dart';

import 'firebase_options.dart'; // generado por `flutterfire configure`
import 'services/auth_service.dart';
import 'services/tema_service.dart';
import 'services/ajustes_service.dart';
import 'services/navegacion_observer.dart';
import 'services/vista_prueba_service.dart';
import 'screens/comunes/login_screen.dart';
import 'screens/comunes/home_shell.dart';
import 'tema.dart';

final _navigatorKey = GlobalKey<NavigatorState>();
final _profundidadNavegacion = ValueNotifier<int>(0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Nombres de meses/días en español y catalán (calendarios, fechas).
  await initializeDateFormatting();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TemaService()),
        ChangeNotifierProvider(create: (_) => AjustesService()),
        ChangeNotifierProvider(create: (_) => VistaPruebaService()),
      ],
      child: const SottoStudioApp(),
    ),
  );
}

class SottoStudioApp extends StatelessWidget {
  const SottoStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tema = context.watch<TemaService>();
    final ajustes = context.watch<AjustesService>();
    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [NavegacionObserver(_profundidadNavegacion)],
      title: 'Sotto Studio',
      debugShowCheckedModeBanner: false,
      locale: ajustes.idioma,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: temaClaro,
      darkTheme: temaOscuro,
      themeMode: tema.modo,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(ajustes.escalaFuente),
        ),
        child: Stack(
          children: [
            child!,
            ValueListenableBuilder<int>(
              valueListenable: _profundidadNavegacion,
              builder: (context, profundidad, _) {
                if (profundidad <= 0) return const SizedBox.shrink();
                return Positioned(
                  left: 16,
                  bottom: 16,
                  child: SafeArea(
                    // Sin `tooltip:`: este botón vive en el Stack del
                    // `builder:` de MaterialApp, fuera del Overlay que
                    // crea el Navigator interno — un Tooltip aquí
                    // lanza "No Overlay widget found" al no encontrar
                    // un ancestro Overlay.
                    child: FloatingActionButton.small(
                      heroTag: 'volverAlMenu',
                      onPressed: () =>
                          _navigatorKey.currentState?.popUntil((r) => r.isFirst),
                      child: const Icon(Icons.home_outlined),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      home: const _RaizAutenticacion(),
    );
  }
}

/// Escucha el estado de autenticación y, si hay usuario, resuelve su
/// rol para enrutar al dashboard correcto.
class _RaizAutenticacion extends StatelessWidget {
  const _RaizAutenticacion();

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder<User?>(
      stream: authService.cambiosDeUsuario,
      builder: (context, snapshotAuth) {
        if (snapshotAuth.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshotAuth.data;
        if (user == null) {
          return const LoginScreen();
        }

        return FutureBuilder(
          future: authService.obtenerPerfil(user.uid),
          builder: (context, snapshotPerfil) {
            if (!snapshotPerfil.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final real = snapshotPerfil.data!;
            if (!real.activo) return const _CuentaDadaDeBaja();
            // Modo desarrollador (ver CLAUDE.md): si la cuenta REAL
            // tiene el permiso `desarrollador` y hay una vista
            // simulada elegida, se construye una copia de `perfil` con
            // los permisos reducidos a ese único rol — el documento
            // real en Firestore conserva TODOS sus permisos para que
            // las reglas de seguridad sigan concediendo todo lo que
            // ese rol necesitaría de verdad. `perfilReal` se pasa
            // aparte para que HomeShell pueda mostrar el propio
            // selector de vista y el panel de incidencias pase lo que
            // pase esté simulando.
            final vistaSimulada = context.watch<VistaPruebaService>().vistaSimulada;
            final perfilMostrado = (real.esDesarrollador && vistaSimulada != null)
                ? real.copiarConPermisos({vistaSimulada})
                : real;
            // HomeShell es un StatefulWidget que cachea en su State la
            // pantalla actual (_cuerpo) y el título, asignados solo en
            // initState — sin una key que cambie con el rol simulado,
            // Flutter reutiliza el mismo State al cambiar de vista (modo
            // desarrollador) y esos campos quedan congelados con el
            // perfil viejo, aunque el resto del build sí se refresca (de
            // ahí que el body/Inicio no cambiara al simular otro rol).
            // Una key distinta por combinación de permisos fuerza un
            // State — y por tanto un initState — nuevo en cada cambio.
            final claveVista =
                (perfilMostrado.permisos.map((p) => p.name).toList()..sort()).join(',');
            return HomeShell(
              key: ValueKey(claveVista),
              perfil: perfilMostrado,
              perfilReal: real,
            );
          },
        );
      },
    );
  }
}

/// Pantalla para una cuenta que dirección ha dado de baja del centro
/// (`Usuario.activo == false`): no entra a la app; las reglas de
/// Firestore ya le retiran cualquier permiso igualmente.
class _CuentaDadaDeBaja extends StatelessWidget {
  const _CuentaDadaDeBaja();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_off_outlined, size: 56),
              const SizedBox(height: 16),
              const Text(
                'Esta cuenta está dada de baja del centro.\nSi crees que es un error, habla con dirección.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => AuthService().cerrarSesion(),
                child: const Text('Volver al inicio de sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
