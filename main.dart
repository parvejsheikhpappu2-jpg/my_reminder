import 'package:flutter/material.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// সময় হলে এই ফাংশন ব্যাকগ্রাউন্ডে চলবে এবং কথা বলবে
@pragma('vm:entry-point')
Future<void> speakCallback(int id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final text = prefs.getString('task_$id') ?? '';
  final lang = prefs.getString('lang_$id') ?? 'bn-BD';
  final tts = FlutterTts();
  await tts.setSpeechRate(0.45);
  await tts.awaitSpeakCompletion(true);
  await tts.setLanguage(lang);
  if (lang.startsWith('en')) {
    await tts.speak("It's time to $text");
  } else if (lang.startsWith('bn')) {
    await tts.speak('এখন $text করার সময়');
  } else {
    // অন্য ভাষায় ইউজার যা লিখেছে সেটাই বলবে
    await tts.speak(text);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AndroidAlarmManager.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'আমার রিমাইন্ডার',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  TimeOfDay _time = TimeOfDay.now();
  String _lang = 'bn-BD';
  List<String> _languages = ['bn-BD', 'en-US'];
  List<String> _tasks = []; // format: id|HH:mm|lang|text

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final langs = await FlutterTts().getLanguages;
      final list = List<String>.from(langs.map((e) => e.toString()))..sort();
      if (list.isNotEmpty) {
        _languages = list;
        if (!list.contains(_lang)) _lang = list.first;
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    setState(() => _tasks = prefs.getStringList('tasks') ?? []);
  }

  Future<void> _add() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final id = DateTime.now().millisecondsSinceEpoch % 100000000;

    var when = DateTime.now();
    when = DateTime(when.year, when.month, when.day, _time.hour, _time.minute);
    if (when.isBefore(DateTime.now())) when = when.add(const Duration(days: 1));

    await prefs.setString('task_$id', text);
    await prefs.setString('lang_$id', _lang);
    await AndroidAlarmManager.periodic(
      const Duration(days: 1), // প্রতিদিন একই সময়ে
      id,
      speakCallback,
      startAt: when,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );

    final hh = _time.hour.toString().padLeft(2, '0');
    final mm = _time.minute.toString().padLeft(2, '0');
    _tasks.add('$id|$hh:$mm|$_lang|$text');
    await prefs.setStringList('tasks', _tasks);
    _controller.clear();
    setState(() {});
  }

  Future<void> _remove(int index) async {
    final id = int.parse(_tasks[index].split('|')[0]);
    await AndroidAlarmManager.cancel(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('task_$id');
    await prefs.remove('lang_$id');
    _tasks.removeAt(index);
    await prefs.setStringList('tasks', _tasks);
    setState(() {});
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('আমার রিমাইন্ডার')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'কী কাজ? (যেমন: পড়তে বসা)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _languages.contains(_lang) ? _lang : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'ভয়েসের ভাষা',
                border: OutlineInputBorder(),
              ),
              items: _languages
                  .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                  .toList(),
              onChanged: (v) => setState(() => _lang = v ?? _lang),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time),
                  label: Text(_time.format(context)),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: const Text('যোগ করো'),
                ),
              ],
            ),
            const Divider(height: 32),
            Expanded(
              child: ListView.builder(
                itemCount: _tasks.length,
                itemBuilder: (_, i) {
                  final p = _tasks[i].split('|');
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.alarm),
                      title: Text(p.sublist(3).join('|')),
                      subtitle: Text(
                          'প্রতিদিন ${p[1]} এ • ${p[2]}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(i),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
