import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
  } catch (e) {
    // Se não achar o fuso horário, usa o padrão
  }

  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initSettings =
      InitializationSettings(android: androidInit);

  await notificationsPlugin.initialize(initSettings,
      onDidReceiveNotificationResponse: (payload) {
    // Ação ao tocar na notificação
  });

  runApp(const MyApp());
}

class Medication {
  String name;
  String dose;
  TimeOfDay time;
  Medication({required this.name, required this.dose, required this.time});

  Map<String, dynamic> toJson() => {
        'name': name,
        'dose': dose,
        'hour': time.hour,
        'minute': time.minute,
      };

  static Medication fromJson(Map<String, dynamic> j) {
    return Medication(
      name: j['name'] ?? '',
      dose: j['dose'] ?? '',
      time: TimeOfDay(hour: j['hour'] ?? 8, minute: j['minute'] ?? 0),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  List<Medication> meds = [];
  late SharedPreferences prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    prefs = await SharedPreferences.getInstance();
    final List<String>? stored = prefs.getStringList('meds');
    if (stored != null) {
      meds = stored.map((s) {
        final parts = s.split('|');
        return Medication(
          name: parts[0],
          dose: parts[1],
          time: TimeOfDay(
            hour: int.parse(parts[2]),
            minute: int.parse(parts[3]),
          ),
        );
      }).toList();
      setState(() {});
    }
  }

  Future<void> _save() async {
    final data = meds
        .map((m) =>
            '${m.name}|${m.dose}|${m.time.hour}|${m.time.minute}')
        .toList();
    await prefs.setStringList('meds', data);
  }

  Future<void> _scheduleNotification(int id, Medication med) async {
    final now = tz.TZDateTime.now(tz.local);
    final scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, med.time.hour, med.time.minute);
    final when =
        scheduled.isBefore(now) ? scheduled.add(const Duration(days: 1)) : scheduled;

    await notificationsPlugin.zonedSchedule(
      id,
      'Hora do remédio',
      '${med.name} — ${med.dose}',
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'remedio_channel',
          'Lembretes de Remédio',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
      ),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> _cancelNotification(int id) async {
    await notificationsPlugin.cancel(id);
  }

  void _addOrEdit({Medication? edit, int? index}) async {
    final nameController = TextEditingController(text: edit?.name ?? '');
    final doseController = TextEditingController(text: edit?.dose ?? '');
    TimeOfDay selected = edit?.time ?? const TimeOfDay(hour: 8, minute: 0);

    final res = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(edit == null ? 'Adicionar medicamento' : 'Editar medicamento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            TextField(
              controller: doseController,
              decoration: const InputDecoration(labelText: 'Dosagem'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                final t = await showTimePicker(
                    context: context, initialTime: selected);
                if (t != null) {
                  selected = t;
                  setState(() {});
                }
              },
              child: Text('Hora: ${selected.format(context)}'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final m = Medication(
                name: nameController.text,
                dose: doseController.text,
                time: selected,
              );
              if (edit != null && index != null) {
                meds[index] = m;
              } else {
                meds.add(m);
              }
              _save();
              for (int i = 0; i < meds.length; i++) {
                _scheduleNotification(i, meds[i]);
              }
              Navigator.of(c).pop(true);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (res == true) setState(() {});
  }

  void _delete(int idx) async {
    await _cancelNotification(idx);
    meds.removeAt(idx);
    for (int i = 0; i < meds.length; i++) {
      await _cancelNotification(i);
      await _scheduleNotification(i, meds[i]);
    }
    _save();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lembrete de Medicamentos',
      home: Scaffold(
        appBar: AppBar(title: const Text('Lembretes de Medicamentos')),
        body: meds.isEmpty
            ? const Center(
                child: Text(
                    'Nenhum medicamento adicionado.\nToque no + para adicionar.'),
              )
            : ListView.builder(
                itemCount: meds.length,
                itemBuilder: (context, index) {
                  final m = meds[index];
                  final timeStr = m.time.format(context);
                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      title: Text(m.name,
                          style: const TextStyle(fontSize: 18)),
                      subtitle: Text('${m.dose} — $timeStr'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () =>
                                  _addOrEdit(edit: m, index: index)),
                          IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _delete(index)),
                        ],
                      ),
                    ),
                  );
                },
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _addOrEdit(),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
