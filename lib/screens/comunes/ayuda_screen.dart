import 'package:flutter/material.dart';
import '../../models/usuario.dart';

/// Guía rápida "¿Cómo hago...?" por perfil, en lenguaje llano: pensada
/// sobre todo para dirección (personas poco habituadas a apps de
/// gestión). Solo se muestran las secciones de los permisos que tiene
/// la cuenta. Cada paso nombra los textos EXACTOS de menús y botones,
/// así que si se renombra algo en la app, actualizar también aquí.
class AyudaScreen extends StatelessWidget {
  final Usuario perfil;

  const AyudaScreen({super.key, required this.perfil});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Toca cada pregunta para ver los pasos. El menú se abre con el botón ☰ de arriba a la izquierda. '
              'Si algo no funciona, usa «Informar de un problema o sugerencia» en el menú.',
            ),
          ),
          if (perfil.esDireccion) ..._seccion(context, 'Dirección', _direccion),
          if (perfil.esProfesor) ..._seccion(context, 'Profesorado', _profesor),
          if (perfil.esProfesor || perfil.esDireccion) ..._seccion(context, 'Fichar', _fichar),
          if (perfil.esAlumno) ..._seccion(context, 'Alumnos', _alumno),
        ],
      ),
    );
  }

  List<Widget> _seccion(BuildContext context, String titulo, List<(String, List<String>)> preguntas) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(titulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ),
      for (final (pregunta, pasos) in preguntas)
        ExpansionTile(
          leading: const Icon(Icons.help_outline),
          title: Text(pregunta),
          childrenPadding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < pasos.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 24, child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.bold))),
                    Expanded(child: Text(pasos[i])),
                  ],
                ),
              ),
          ],
        ),
    ];
  }
}

const _direccion = <(String, List<String>)>[
  (
    'Empezar desde cero: ¿en qué orden lo preparo todo?',
    [
      'Menú → Configuración del centro → Gestionar cursos: crea los cursos (p. ej. «2º Elemental»).',
      'Menú → Asignaturas → «Nueva asignatura»: crea cada asignatura dentro de su curso. Ahí mismo pones las horas de estudio que se piden y, si es de grupo, sus horarios.',
      'Menú → Profesorado → «Nuevo profesor».',
      'Menú → Alumnos → «Nuevo alumno». Al terminar te ofrece matricularlo.',
      'Si ya tienes los datos en hojas de cálculo: Menú → Configuración del centro → Importar datos desde Excel.',
    ]
  ),
  (
    'Dar de alta a un alumno y matricularlo',
    [
      'Menú → Alumnos → «Nuevo alumno».',
      'Escribe nombre y apellidos. Si el alumno no va a usar la app (por ejemplo, es muy pequeño), desactiva el interruptor del email.',
      'Pulsa «Crear alumno». Si tiene email, apunta la contraseña temporal que aparece y dásela a la familia.',
      'Pulsa «Matricular ahora» → «Matricular en una asignatura» → elige la asignatura → días y hora (o su grupo) → «Guardar».',
    ]
  ),
  (
    'Un alumno deja una asignatura o se va del centro',
    [
      'Solo deja una asignatura: Menú → Asignaturas → la asignatura → el curso → en su fila, botón ⋮ → «Dar de baja de esta asignatura».',
      'Se va del centro: Menú → Alumnos → toca su nombre → botón ⋮ arriba a la derecha → «Dar de baja del centro».',
      'No se borra nada: sus notas y asistencias se guardan. Puedes reactivarlo al final de la lista de alumnos, en «Dados de baja».',
    ]
  ),
  (
    'Corregir el nombre de un alumno o enviarle una contraseña nueva',
    [
      'Menú → Alumnos → toca su nombre → botón ⋮ arriba a la derecha.',
      '«Editar datos» para nombre, apellidos e instrumento. «Enviar enlace para nueva contraseña» le manda un email para elegir otra.',
      'En la misma ficha, «Contacto de la familia» guarda el teléfono del tutor (solo dirección lo ve).',
    ]
  ),
  (
    'Cambiar el horario de una clase',
    [
      'Menú → Horario general.',
      'Mantén pulsada la clase y arrástrala a la nueva casilla. Si te equivocas, pulsa «Deshacer» en el aviso de abajo.',
      'También: en la ficha de la asignatura, botón ⋮ de la fila del alumno → «Cambiar horario, grupo o profesor».',
    ]
  ),
  (
    'Un profesor está de baja: poner un sustituto',
    [
      'Menú → Profesorado → toca al profesor de baja → botón «Sustituir» arriba.',
      'Elige quién le sustituye, los días en el calendario y las asignaturas → «Guardar sustitución».',
      'Esos días, el sustituto verá esas clases en su Inicio y podrá pasar lista y poner notas.',
    ]
  ),
  (
    'Revisar lo pendiente (notas, asistencia, fichajes)',
    [
      'La pantalla de Inicio muestra cuántas cosas tienes pendientes. Toca cada aviso para ir directamente.',
      'Notas: aparecen cuando el profesor ha puesto nota en todos los criterios. Revisa y pulsa «Validar nota final».',
    ]
  ),
  (
    'Sacar el boletín de notas de un alumno',
    [
      'Menú → Alumnos → toca su nombre → «Generar boletín de notas».',
      'Elige las asignaturas → «Generar». Se abre para imprimir o guardar en PDF.',
    ]
  ),
  (
    'Empezar un curso escolar nuevo (septiembre)',
    [
      'Menú → Configuración del centro → Curso escolar → «Crear/activar un curso escolar nuevo».',
      'El curso anterior no se borra: se puede consultar desde cada asignatura.',
    ]
  ),
];

const _profesor = <(String, List<String>)>[
  (
    'Pasar lista',
    [
      'En Inicio, «Mis clases de hoy» muestra a los alumnos que tienen clase hoy.',
      'Pulsa «Asistió», «Retraso» o «Faltó» en cada uno. Se guarda al momento.',
      'Otro camino: Menú → Mis asignaturas → asignatura → curso → Asistencias.',
    ]
  ),
  (
    'Poner o corregir una nota',
    [
      'Menú → Mis asignaturas → asignatura → curso → Notas.',
      'Toca la casilla del alumno y del criterio, escribe la nota (de 0 a 10) y pulsa «Guardar».',
      'Para corregirla o borrarla: en esa misma cuadrícula, toca el nombre del alumno → lápiz junto a la nota. Solo se puede mientras dirección no la haya validado.',
    ]
  ),
  (
    'Anotar horas de estudio de teoría',
    [
      'Menú → Mis asignaturas → asignatura → curso → Horas de estudio.',
      'Toca la casilla del alumno y del mes, y escribe las horas.',
    ]
  ),
];

const _fichar = <(String, List<String>)>[
  (
    'Fichar la entrada y la salida',
    [
      'Menú → Fichar entrada/salida → «Fichar entrada» al llegar y «Fichar salida» al irte.',
      'Una vez fichado no se puede cambiar. Si te olvidaste un día: «¿Olvidaste fichar otro día?» y dirección lo revisará.',
    ]
  ),
];

const _alumno = <(String, List<String>)>[
  (
    'Grabar mi estudio en casa',
    [
      'Menú → Mi estudio → «Empezar estudio».',
      'Elige la asignatura y pulsa el micrófono. Toca tu instrumento con el móvil cerca.',
      'Cuando termines, pulsa el botón rojo. Verás «¡Sesión guardada!». No se guarda nada de audio.',
    ]
  ),
  (
    'Ver mis notas y mis medallas',
    [
      'Menú → Mi estudio → «Mis notas».',
      'Menú → Medallas y roscos: el rosco se llena con las horas de la semana; si llegas al objetivo, ganas la medalla.',
    ]
  ),
];
