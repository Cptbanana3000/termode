import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/settings_service.dart';
import '../services/terminal_session_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showImportDialog(BuildContext context, SettingsService settings) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Import Backup',
            style: TextStyle(color: Colors.white, fontFamily: 'monospace'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Paste the backup JSON string below to restore Termode state:',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 5,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  fillColor: Color(0xFF121212),
                  filled: true,
                  border: OutlineInputBorder(),
                  hintText: '{"settings": ...}',
                  hintStyle: TextStyle(color: Colors.white24),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                final jsonString = controller.text.trim();
                if (jsonString.isEmpty) return;

                final success = await TerminalSessionService().importState(jsonString);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? 'State restored successfully!'
                            : 'Failed to restore state: Invalid JSON format',
                      ),
                      backgroundColor: success ? settings.primaryColor : Colors.redAccent,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Text('Restore', style: TextStyle(color: settings.primaryColor)),
            ),
          ],
        );
      },
    );
  }

  void _showSafeResetConfirmation(
    BuildContext context,
    SettingsService settings,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(
            'Safe Reset',
            style: TextStyle(
              color: settings.primaryColor,
              fontFamily: 'monospace',
            ),
          ),
          content: const Text(
            'Restore theme, font, cursor, scrollback, and paste settings to '
            'defaults?\n\nSessions, history, packages, workspaces, repo config, '
            'and files are kept. "Start in real shell" is preserved.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                settings.resetVisualSettings();
                await TerminalSessionService().saveState();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Visual settings restored to defaults'),
                      backgroundColor: settings.primaryColor,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Text('Reset', style: TextStyle(color: settings.primaryColor)),
            ),
          ],
        );
      },
    );
  }

  void _showResetConfirmation(BuildContext context, SettingsService settings) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Reset Termode',
            style: TextStyle(color: Colors.redAccent, fontFamily: 'monospace'),
          ),
          content: const Text(
            'Are you sure you want to restore factory default settings? This will delete all local files, directories, sessions, and histories permanently.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                await TerminalSessionService().resetState();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Termode state reset successfully'),
                      backgroundColor: settings.primaryColor,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('Reset', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontFamily: 'monospace'),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              const Text(
                'Terminal Preferences',
                style: TextStyle(
                  color: Color(0xFF5AF78E),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const Divider(color: Color(0xFF2D2D2D), height: 30),
              
              ListTile(
                title: const Text('Font Size', style: TextStyle(color: Colors.white)),
                subtitle: Text('${settings.fontSize.toInt()} px', style: const TextStyle(color: Colors.white60)),
                trailing: SizedBox(
                  width: 150,
                  child: Slider(
                    value: settings.fontSize,
                    min: 10.0,
                    max: 24.0,
                    divisions: 7,
                    activeColor: settings.primaryColor,
                    inactiveColor: const Color(0xFF2D2D2D),
                    onChanged: (value) {
                      settings.setFontSize(value);
                    },
                  ),
                ),
              ),
              
              ListTile(
                title: const Text('Color Scheme', style: TextStyle(color: Colors.white)),
                subtitle: Text(settings.themeColor, style: const TextStyle(color: Colors.white60)),
                trailing: DropdownButton<String>(
                  value: settings.themeColor,
                  dropdownColor: const Color(0xFF1E1E1E),
                  style: const TextStyle(color: Colors.white),
                  underline: Container(
                    height: 2,
                    color: settings.primaryColor,
                  ),
                  items: <String>['Green', 'Amber', 'White'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      settings.setThemeColor(value);
                    }
                  },
                ),
              ),

              const SizedBox(height: 10),
              SwitchListTile(
                title: const Text('Show Welcome Message', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Display welcome text on new session tabs', style: TextStyle(color: Colors.white60)),
                value: settings.showWelcomeBanner,
                activeThumbColor: settings.primaryColor,
                onChanged: (value) {
                  settings.setShowWelcomeBanner(value);
                },
              ),
              
              if (settings.showWelcomeBanner)
                SwitchListTile(
                  title: const Text('Large ASCII Banner', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Display giant retro ASCII logo', style: TextStyle(color: Colors.white60)),
                  value: settings.showLargeAsciiBanner,
                  activeThumbColor: settings.primaryColor,
                  onChanged: (value) {
                    settings.setShowLargeAsciiBanner(value);
                  },
                ),

              SwitchListTile(
                title: const Text('Immersive Mode', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Hide title and tab bars in terminal canvas', style: TextStyle(color: Colors.white60)),
                value: settings.immersiveMode,
                activeThumbColor: settings.primaryColor,
                onChanged: (value) {
                  settings.setImmersiveMode(value);
                },
              ),

              SwitchListTile(
                title: const Text('Show Control Characters as Hex', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Display non-printable codes as [0xXX] for debugging', style: TextStyle(color: Colors.white60)),
                value: settings.showControlCharsHex,
                activeThumbColor: settings.primaryColor,
                onChanged: (value) {
                  settings.setShowControlCharsHex(value);
                },
              ),

              SwitchListTile(
                title: const Text('Enable ANSI Renderer', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Render ANSI color codes and control sequences', style: TextStyle(color: Colors.white60)),
                value: settings.enableAnsiRenderer,
                activeThumbColor: settings.primaryColor,
                onChanged: (value) {
                  settings.setEnableAnsiRenderer(value);
                },
              ),

              ListTile(
                title: const Text('Cursor Style', style: TextStyle(color: Colors.white)),
                subtitle: Text(settings.cursorStyle, style: const TextStyle(color: Colors.white60)),
                trailing: DropdownButton<String>(
                  value: settings.cursorStyle,
                  dropdownColor: const Color(0xFF1E1E1E),
                  style: const TextStyle(color: Colors.white),
                  underline: Container(
                    height: 2,
                    color: settings.primaryColor,
                  ),
                  items: <String>['block', 'bar', 'underline'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      settings.setCursorStyle(value);
                    }
                  },
                ),
              ),

              SwitchListTile(
                title: const Text('Blinking Cursor', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Animate cursor blinking', style: TextStyle(color: Colors.white60)),
                value: settings.blinkingCursor,
                activeThumbColor: settings.primaryColor,
                onChanged: (value) {
                  settings.setBlinkingCursor(value);
                },
              ),

              SwitchListTile(
                title: const Text('Start in Real Shell', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Automatically open native shell on new sessions', style: TextStyle(color: Colors.white60)),
                value: settings.startInRealShell,
                activeThumbColor: settings.primaryColor,
                onChanged: (value) {
                  settings.setStartInRealShell(value);
                },
              ),

              ListTile(
                title: const Text('Line Height', style: TextStyle(color: Colors.white)),
                subtitle: Text(settings.lineHeight.toStringAsFixed(2), style: const TextStyle(color: Colors.white60)),
                trailing: SizedBox(
                  width: 150,
                  child: Slider(
                    value: settings.lineHeight,
                    min: 1.0,
                    max: 2.0,
                    divisions: 10,
                    activeColor: settings.primaryColor,
                    inactiveColor: const Color(0xFF2D2D2D),
                    onChanged: (value) {
                      settings.setLineHeight(value);
                    },
                  ),
                ),
              ),

              ListTile(
                title: const Text('Scrollback Lines', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Lines kept per session', style: TextStyle(color: Colors.white60)),
                trailing: DropdownButton<int>(
                  value: settings.maxScrollbackLines,
                  dropdownColor: const Color(0xFF1E1E1E),
                  style: const TextStyle(color: Colors.white),
                  underline: Container(height: 2, color: settings.primaryColor),
                  items: const <int>[500, 1000, 2000, 5000, 10000].map((int value) {
                    return DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      settings.setMaxScrollbackLines(value);
                    }
                  },
                ),
              ),

              SwitchListTile(
                title: const Text('ANSI Debug Mode', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Show raw control codes for debugging (verbose)', style: TextStyle(color: Colors.white60)),
                value: settings.ansiDebugMode,
                activeThumbColor: settings.primaryColor,
                onChanged: (value) {
                  settings.setAnsiDebugMode(value);
                },
              ),

              SwitchListTile(
                title: const Text('Keep Screen On', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Preference to discourage auto-sleep while in the terminal', style: TextStyle(color: Colors.white60)),
                value: settings.keepScreenOn,
                activeThumbColor: settings.primaryColor,
                onChanged: (value) {
                  settings.setKeepScreenOn(value);
                },
              ),

              const SizedBox(height: 30),
              const Text(
                'Backup & Restore',
                style: TextStyle(
                  color: Color(0xFF5AF78E),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const Divider(color: Color(0xFF2D2D2D), height: 30),
              ListTile(
                title: const Text('Export Backup', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Copy configuration and files state to clipboard', style: TextStyle(color: Colors.white60)),
                trailing: Icon(Icons.copy, color: settings.primaryColor),
                onTap: () {
                  final stateStr = TerminalSessionService().exportState();
                  Clipboard.setData(ClipboardData(text: stateStr));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Backup JSON copied to clipboard!'),
                      backgroundColor: settings.primaryColor,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              ListTile(
                title: const Text('Import Backup', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Restore sessions and folders from backup string', style: TextStyle(color: Colors.white60)),
                trailing: Icon(Icons.paste, color: settings.primaryColor),
                onTap: () {
                  _showImportDialog(context, settings);
                },
              ),

              const SizedBox(height: 30),
              const Text(
                'System Settings',
                style: TextStyle(
                  color: Color(0xFF5AF78E),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const Divider(color: Color(0xFF2D2D2D), height: 30),
              ListTile(
                title: const Text('Safe Reset (Visual Only)', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Restore theme and terminal display defaults. Keeps sessions, packages, workspaces, and files', style: TextStyle(color: Colors.white60)),
                trailing: Icon(Icons.restart_alt, color: settings.primaryColor),
                onTap: () {
                  _showSafeResetConfirmation(context, settings);
                },
              ),
              ListTile(
                title: const Text('Reset Termode', style: TextStyle(color: Colors.redAccent)),
                subtitle: const Text('Wipe all sessions, folders, and settings permanently', style: TextStyle(color: Colors.white60)),
                trailing: const Icon(Icons.delete_forever, color: Colors.redAccent),
                onTap: () {
                  _showResetConfirmation(context, settings);
                },
              ),

              const SizedBox(height: 30),
              const Text(
                'About',
                style: TextStyle(
                  color: Color(0xFF5AF78E),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const Divider(color: Color(0xFF2D2D2D), height: 30),
              const ListTile(
                title: Text('App Version', style: TextStyle(color: Colors.white)),
                trailing: Text('v0.41 (Release Candidate Cleanup)', style: TextStyle(color: Colors.white60)),
              ),
              const ListTile(
                title: Text('Developer', style: TextStyle(color: Colors.white)),
                trailing: Text('Termode Team', style: TextStyle(color: Colors.white60)),
              ),
            ],
          );
        },
      ),
    );
  }
}
