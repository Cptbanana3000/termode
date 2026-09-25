/// The Termode Developer Environment & Embedded Runtime Engine library.
///
/// Provides in-process, headless runtime execution ([TermodeEngine])
/// and embeddable Flutter terminal widgets ([TermodeEmbeddableTerminal])
/// for external applications and IDEs such as Calypso IDE.
library;

// Headless Engine & Integration Bridge
export 'termode_bridge.dart';

// Embeddable Flutter Widgets & Controllers
export 'widgets/extra_keyboard_row.dart';
export 'widgets/terminal_view.dart';
export 'widgets/termode_embeddable_terminal.dart';

// Terminal Models
export 'models/terminal_line.dart';
export 'models/terminal_session.dart';

// Core Services
export 'services/command_service.dart' show CommandResult;
export 'services/dev_server_service.dart';
export 'services/dev_stack_service.dart';
export 'services/localhost_service.dart';
export 'services/native_command_service.dart';
export 'services/npm_package_service.dart';
export 'services/osint_service.dart';
export 'services/pip_package_service.dart';
export 'services/python_environment_service.dart';
export 'services/runtime_binary_package_service.dart';
export 'services/runtime_bootstrap_service.dart';
export 'services/settings_service.dart';
export 'services/terminal_session_service.dart';
export 'services/virtual_filesystem.dart';
export 'services/workspace_service.dart';

// File Explorer & In-App Editor
export 'services/file_explorer_service.dart';
export 'widgets/file_explorer_drawer.dart';
export 'widgets/syntax_highlighting_controller.dart';
export 'screens/quick_editor_screen.dart';
