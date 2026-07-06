import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart'; // generado por `flutterfire configure`
import 'services/auth_service.dart';
import 'models/usuario.dart';
import 'screens/comunes/login_screen.dart';
import 'screens/alumno/dashboard_alumno_screen.dart';
import 'screens/profesor/dashboard_profesor_screen.dart';
import 'screens/direccion/informe_direccion_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SottoStudioApp());
}

class SottoStudioApp extends StatelessWidget {
  const SottoStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sotto Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFE07A2C), // naranja acento
        scaffoldBackgroundColor: const Color(0xFFF5F1E8), // crema
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

        return FutureBuilder<Usuario?>(
          future: authService.obtenerPerfil(user.uid),
          builder: (context, snapshotPerfil) {
            if (!snapshotPerfil.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final perfil = snapshotPerfil.data!;
            switch (perfil.rol) {
              case Rol.profesor:
                return const DashboardProfesorScreen();
              case Rol.direccion:
                return InformeDireccionScreen();
              case Rol.alumno:
                return const DashboardAlumnoScreen();
            }
          },
        );
      },
    );
  }
}
