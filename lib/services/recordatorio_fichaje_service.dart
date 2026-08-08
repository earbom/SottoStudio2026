import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../models/horario_laboral.dart';

/// Recordatorio de fichaje "X minutos antes de tu turno": una
/// notificación LOCAL programada por el propio dispositivo, no una
/// notificación push del servidor (eso requeriría una Cloud Function
/// con Cloud Scheduler, bloqueado por el plan Blaze — ver CLAUDE.md).
/// Como el trabajador conoce su propio horario de antemano, basta con
/// programar notificaciones locales recurrentes semanales.
///
/// Fiabilidad: sólida en Android/iOS (notificaciones nativas del SO,
/// funcionan con la app cerrada). En la versión web es "best effort":
/// depende de que el navegador soporte notificaciones en segundo
/// plano y de que la pestaña/PWA siga registrada.
class RecordatorioFichajeService {
  static const _canalId = 'fichajes';
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inicializado = false;

  Future<void> inicializar({required void Function(String? payload) onNotificacionTocada}) async {
    if (_inicializado) return;
    tzdata.initializeTimeZones();
    // El centro está en España (piloto de un solo centro, ver
    // CLAUDE.md) — sin necesidad de detectar la zona horaria del
    // dispositivo.
    tz.setLocalLocation(tz.getLocation('Europe/Madrid'));

    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initIOS = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: initAndroid, iOS: initIOS, macOS: initIOS);

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (respuesta) => onNotificacionTocada(respuesta.payload),
    );
    _inicializado = true;
  }

  Future<void> solicitarPermiso() async {
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Recalcula todos los recordatorios de fichaje según el horario
  /// laboral actual (un id de notificación fijo por día de la
  /// semana, se repite automáticamente cada semana).
  Future<void> reprogramar(HorarioLaboral horario) async {
    await _plugin.cancelAll();
    for (final turno in horario.turnos) {
      final proxima = _proximaOcurrencia(turno.diaSemana, turno.horaEntrada, horario.minutosAvisoAntes);
      await _plugin.zonedSchedule(
        id: turno.diaSemana,
        scheduledDate: proxima,
        title: 'Hora de fichar',
        body: 'Tu turno empieza en ${horario.minutosAvisoAntes} minutos.',
        payload: 'fichajes',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _canalId,
            'Recordatorios de fichaje',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  Future<void> cancelarTodos() => _plugin.cancelAll();

  tz.TZDateTime _proximaOcurrencia(int diaSemana, String horaEntrada, int minutosAntes) {
    final ahora = tz.TZDateTime.now(tz.local);
    final partes = horaEntrada.split(':');
    final horas = int.parse(partes[0]);
    final minutos = int.parse(partes[1]);
    var candidato = tz.TZDateTime(tz.local, ahora.year, ahora.month, ahora.day, horas, minutos)
        .subtract(Duration(minutes: minutosAntes));
    while (candidato.weekday != diaSemana || candidato.isBefore(ahora)) {
      candidato = candidato.add(const Duration(days: 1));
    }
    return candidato;
  }
}
