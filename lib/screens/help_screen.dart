import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      appBar: AppBar(
        title: const Text(
          'Help & Docs',
          style: TextStyle(color: Colors.white, fontFamily: 'monospace'),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome to Termode!',
              style: TextStyle(
                color: Color(0xFF5AF78E),
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Termode is a local terminal environment running in Flutter. Version 0.1 supports in-memory command execution, navigation keys, and history.',
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            const Text(
              'Available Commands:',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            const Divider(color: Color(0xFF2D2D2D), height: 20),
            _buildCommandDoc('help', 'Display this documentation screen (also available via terminal output).'),
            _buildCommandDoc('clear', 'Clears the screen logs of the terminal.'),
            _buildCommandDoc('echo [arguments]', 'Prints the arguments string back to the terminal output.'),
            _buildCommandDoc('pwd', 'Prints the current directory (default /home).'),
            _buildCommandDoc('whoami', 'Prints the current active user name.'),
            _buildCommandDoc('date', 'Prints the current date and time on the machine.'),
            const SizedBox(height: 24),
            const Text(
              'Tips & Shortcuts:',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            const Divider(color: Color(0xFF2D2D2D), height: 20),
            _buildTip('History navigation', 'Use the ▲ and ▼ buttons on the extra keyboard row to cycle through command history.'),
            _buildTip('Command completion', 'Type a prefix (e.g. "he") and tap TAB to automatically complete the command.'),
            _buildTip('Cursor movement', 'Use ◀ and ▶ on the keyboard row to navigate inside your active input line.'),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandDoc(String command, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            command,
            style: const TextStyle(
              color: Color(0xFF5AF78E),
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildTip(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          children: [
            TextSpan(
              text: '$title: ',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            TextSpan(text: desc),
          ],
        ),
      ),
    );
  }
}
