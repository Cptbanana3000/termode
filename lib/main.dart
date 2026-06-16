import 'package:flutter/material.dart';
import 'screens/terminal_screen.dart';
import 'services/terminal_session_service.dart';
import 'services/settings_service.dart';
import 'services/runtime_bootstrap_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Asynchronously load the persisted terminal sessions, folders, and settings
  await TerminalSessionService().loadPersistedState();

  // Bootstrap the runtime folders inside the sandbox
  await RuntimeBootstrapService().init();
  
  runApp(const TermodeApp());
}

class TermodeApp extends StatelessWidget {
  const TermodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Termode',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: settings.backgroundColor,
            colorScheme: ColorScheme.dark(
              primary: settings.primaryColor,
              surface: const Color(0xFF1E1E1E),
            ),
            useMaterial3: true,
          ),
          home: const TerminalScreen(),
        );
      },
    );
  }
}
