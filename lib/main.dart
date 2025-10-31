import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await Hive.initFlutter();
  await Hive.openBox('tasks_box');
  runApp(const GujuApp());
}

class GujuApp extends StatelessWidget {
  const GujuApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guju Calendar',
      theme: ThemeData(primarySwatch: Colors.deepOrange),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasData) return const HomeScreen();
        return const LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  String? _verificationId;
  bool _codeSent = false;
  final _auth = FirebaseAuth.instance;
  bool _loading = false;

  void _sendOtp() async {
    setState(() { _loading = true; });
    await _auth.verifyPhoneNumber(
      phoneNumber: '+91' + _phone.text.trim(),
      verificationCompleted: (cred) async {
        await _auth.signInWithCredential(cred);
      },
      verificationFailed: (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Error')));
        setState((){ _loading=false; });
      },
      codeSent: (id, token) {
        setState(()=>{ _verificationId = id; _codeSent = true; _loading=false; });
      },
      codeAutoRetrievalTimeout: (id) {},
    );
  }

  void _verifyOtp() async {
    if (_verificationId==null) return;
    setState(()=> _loading=true);
    try {
      final cred = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: _otp.text.trim());
      await _auth.signInWithCredential(cred);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid OTP')));
    } finally { setState(()=> _loading=false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login - Guju Calendar')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Mobile number (+91...)')),
          if (_codeSent) TextField(controller: _otp, decoration: const InputDecoration(labelText: 'OTP')),
          const SizedBox(height:12),
          if (_loading) const CircularProgressIndicator(),
          ElevatedButton(
            onPressed: _loading ? null : (_codeSent ? _verifyOtp : _sendOtp),
            child: Text(_codeSent ? 'Verify OTP' : 'Send OTP'),
          ),
        ]),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _focused = DateTime.now();
  DateTime? _selected;
  final box = Hive.box('tasks_box');
  final _controller = TextEditingController();

  List tasksFor(DateTime date) {
    final key = DateUtils.dateOnly(date).toIso8601String();
    final list = List<String>.from(box.get(key) ?? <String>[]);
    return list;
  }

  void _addTask(DateTime date, String title){
    final key = DateUtils.dateOnly(date).toIso8601String();
    final list = List<String>.from(box.get(key) ?? <String>[]);
    list.add(title);
    box.put(key, list);
    setState(()=>{});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guju Calendar'), actions: [
        IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())
      ]),
      body: Column(children: [
        TableCalendar(
          firstDay: DateTime(2000),
          lastDay: DateTime(2100),
          focusedDay: _focused,
          selectedDayPredicate: (d) => isSameDay(d, _selected),
          onDaySelected: (s,f){
            setState(()=>{ _selected = s; _focused = f; });
          },
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(children: [
            Expanded(child: TextField(controller: _controller, decoration: const InputDecoration(hintText: 'Add task for selected date'))),
            ElevatedButton(onPressed: (){
              if (_selected!=null && _controller.text.trim().isNotEmpty){
                _addTask(_selected!, _controller.text.trim());
                _controller.clear();
              }
            }, child: const Text('Add'))
          ]),
        ),
        Expanded(
          child: Builder(builder: (context){
            final list = _selected==null ? <String>[] : tasksFor(_selected!);
            return ListView.builder(itemCount: list.length, itemBuilder: (_,i){
              return ListTile(title: Text(list[i]));
            });
          }),
        )
      ]),
    );
  }
}
