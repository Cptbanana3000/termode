import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/dev_server_service.dart';
import '../services/port_monitor_service.dart';
import '../services/preview_service.dart';

/// Responsive device preset options for in-app preview testing.
enum ViewportPreset {
  responsive('Responsive', null, Icons.crop_free),
  mobile('Mobile', 390, Icons.phone_android),
  tablet('Tablet', 768, Icons.tablet_android),
  desktop('Desktop', 1024, Icons.laptop);

  final String label;
  final double? width;
  final IconData icon;
  const ViewportPreset(this.label, this.width, this.icon);
}

/// A captured console log line.
class DevConsoleEntry {
  final String level; // LOG, WARN, ERROR
  final String message;
  final DateTime timestamp;

  const DevConsoleEntry({
    required this.level,
    required this.message,
    required this.timestamp,
  });
}

/// Floating In-App Live Web Preview & Web Inspector for local dev servers.
///
/// Features:
/// - Real interactive WebView on Android for `http://127.0.0.1:<port>`.
/// - URL address bar with navigation controls (Back, Forward, Refresh, External Open).
/// - Responsive Viewport presets (Responsive / Mobile 390px / Tablet 768px / Desktop 1024px).
/// - Network & HTTP Headers Inspector.
/// - Console Log Inspector (capturing JS logs and server stdout/stderr).
class DevPreviewSheet extends StatefulWidget {
  final int initialPort;
  final String initialPath;
  final bool forceFallbackForTesting;

  const DevPreviewSheet({
    super.key,
    required this.initialPort,
    this.initialPath = '/',
    this.forceFallbackForTesting = false,
  });

  /// Displays the DevPreviewSheet in an adaptive bottom sheet or modal dialog.
  static Future<void> show(
    BuildContext context, {
    required int port,
    String path = '/',
    bool forceFallbackForTesting = false,
  }) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    if (isWide) {
      return showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 1100,
              height: 800,
              child: DevPreviewSheet(
                initialPort: port,
                initialPath: path,
                forceFallbackForTesting: forceFallbackForTesting,
              ),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.92,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: DevPreviewSheet(
            initialPort: port,
            initialPath: path,
            forceFallbackForTesting: forceFallbackForTesting,
          ),
        ),
      ),
    );
  }

  @override
  State<DevPreviewSheet> createState() => _DevPreviewSheetState();
}

class _DevPreviewSheetState extends State<DevPreviewSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _urlController;
  late int _currentPort;
  late String _currentUrl;
  ViewportPreset _viewportPreset = ViewportPreset.responsive;

  WebViewController? _webViewController;
  int _loadingProgress = 0;
  bool _isLoading = false;
  bool _canGoBack = false;
  bool _canGoForward = false;

  PortInspectionResult? _inspectionResult;
  bool _isInspecting = false;

  final List<DevConsoleEntry> _consoleLogs = [];
  String _consoleFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _currentPort = widget.initialPort;
    final cleanPath = widget.initialPath.startsWith('/')
        ? widget.initialPath
        : '/${widget.initialPath}';
    _currentUrl = 'http://127.0.0.1:$_currentPort$cleanPath';
    _urlController = TextEditingController(text: _currentUrl);

    _initWebView();
    _loadInspection();
    _fetchServerLogs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _initWebView() {
    if (widget.forceFallbackForTesting || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }

    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF18181B))
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _loadingProgress = progress;
                  _isLoading = progress < 100;
                });
              }
            },
            onPageStarted: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _currentUrl = url;
                  _urlController.text = url;
                });
              }
            },
            onPageFinished: (url) async {
              if (mounted) {
                final back = await _webViewController?.canGoBack() ?? false;
                final forward =
                    await _webViewController?.canGoForward() ?? false;
                setState(() {
                  _isLoading = false;
                  _loadingProgress = 100;
                  _canGoBack = back;
                  _canGoForward = forward;
                });
              }
            },
            onWebResourceError: (error) {
              _addConsoleLog(
                'ERROR',
                'Resource error (${error.errorCode}): ${error.description}',
              );
            },
          ),
        )
        ..setOnConsoleMessage((message) {
          _addConsoleLog(
            message.level.name.toUpperCase(),
            message.message,
          );
        });

      controller.loadRequest(Uri.parse(_currentUrl));
      _webViewController = controller;
    } catch (e) {
      _addConsoleLog('ERROR', 'WebView initialization failed: $e');
    }
  }

  void _addConsoleLog(String level, String message) {
    if (!mounted) return;
    setState(() {
      _consoleLogs.add(
        DevConsoleEntry(
          level: level,
          message: message,
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  Future<void> _loadInspection() async {
    setState(() => _isInspecting = true);
    try {
      final uri = Uri.tryParse(_currentUrl);
      final path = uri != null && uri.path.isNotEmpty ? uri.path : '/';
      final res = await PortMonitorService().inspectPort(_currentPort, path: path);
      if (mounted) {
        setState(() {
          _inspectionResult = res;
          _isInspecting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isInspecting = false);
      }
    }
  }

  Future<void> _fetchServerLogs() async {
    try {
      final logs = await DevServerService().getServerLogs(port: _currentPort);
      if (logs != null && logs.trim().isNotEmpty) {
        final lines = logs.trim().split('\n');
        for (final line in lines) {
          final isErr = line.startsWith('[STDERR]') || line.contains('Error:');
          _addConsoleLog(isErr ? 'ERROR' : 'LOG', line);
        }
      }
    } catch (_) {}
  }

  void _navigateToUrl(String input) {
    var target = input.trim();
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      if (target.startsWith('/')) {
        target = 'http://127.0.0.1:$_currentPort$target';
      } else {
        target = 'http://$target';
      }
    }

    final uri = Uri.tryParse(target);
    if (uri != null && uri.hasPort) {
      _currentPort = uri.port;
    }

    setState(() {
      _currentUrl = target;
      _urlController.text = target;
    });

    if (_webViewController != null) {
      _webViewController!.loadRequest(Uri.parse(target));
    }
    _loadInspection();
  }

  void _reload() {
    if (_webViewController != null) {
      _webViewController!.reload();
    }
    _loadInspection();
    _fetchServerLogs();
  }

  void _openExternally() {
    PreviewService().openExternally(_currentUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF18181B), // Zinc-900 neutral dark
        border: Border(
          top: BorderSide(color: Color(0xFF27272A), width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildAddressBar(),
          if (_isLoading)
            LinearProgressIndicator(
              value: _loadingProgress > 0 ? _loadingProgress / 100 : null,
              backgroundColor: const Color(0xFF27272A),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5AF78E)),
              minHeight: 2,
            ),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBrowserViewport(),
                _buildNetworkInspector(),
                _buildConsoleInspector(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressBar() {
    final isOnline = _inspectionResult?.isReachable ?? true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E22),
        border: Border(bottom: BorderSide(color: Color(0xFF27272A))),
      ),
      child: Row(
        children: [
          // Live status dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline ? const Color(0xFF5AF78E) : const Color(0xFFFF5555),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          // Port badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF27272A),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              ':$_currentPort',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Nav buttons
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new,
              size: 14,
              color: _canGoBack ? Colors.white70 : Colors.white24,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: _canGoBack
                ? () async {
                    if (await (_webViewController?.canGoBack() ?? false)) {
                      _webViewController?.goBack();
                    }
                  }
                : null,
            tooltip: 'Back',
          ),
          IconButton(
            icon: Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: _canGoForward ? Colors.white70 : Colors.white24,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: _canGoForward
                ? () async {
                    if (await (_webViewController?.canGoForward() ?? false)) {
                      _webViewController?.goForward();
                    }
                  }
                : null,
            tooltip: 'Forward',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: _reload,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
          // URL text input
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF121214),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3F3F46)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 12, color: Colors.white38),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                      ),
                      onSubmitted: _navigateToUrl,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Viewport Preset Selector
          PopupMenuButton<ViewportPreset>(
            icon: Icon(_viewportPreset.icon, size: 18, color: Colors.white70),
            tooltip: 'Viewport preset (${_viewportPreset.label})',
            color: const Color(0xFF27272A),
            onSelected: (preset) {
              setState(() => _viewportPreset = preset);
            },
            itemBuilder: (ctx) => ViewportPreset.values
                .map(
                  (p) => PopupMenuItem(
                    value: p,
                    child: Row(
                      children: [
                        Icon(
                          p.icon,
                          size: 16,
                          color: _viewportPreset == p
                              ? const Color(0xFF5AF78E)
                              : Colors.white70,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          p.label,
                          style: TextStyle(
                            color: _viewportPreset == p
                                ? const Color(0xFF5AF78E)
                                : Colors.white,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 16, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: _openExternally,
            tooltip: 'Open in system browser',
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close Preview',
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF1E1E22),
      height: 36,
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFF5AF78E),
        indicatorWeight: 2,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        labelStyle: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
        tabs: [
          const Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.web, size: 14),
                SizedBox(width: 6),
                Text('PREVIEW'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.compare_arrows, size: 14),
                const SizedBox(width: 6),
                const Text('NETWORK'),
                if (_inspectionResult?.statusCode != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: _inspectionResult!.isHttpSuccess
                          ? const Color(0xFF5AF78E).withValues(alpha: 0.2)
                          : const Color(0xFFFF5555).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${_inspectionResult!.statusCode}',
                      style: TextStyle(
                        color: _inspectionResult!.isHttpSuccess
                            ? const Color(0xFF5AF78E)
                            : const Color(0xFFFF5555),
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.terminal, size: 14),
                const SizedBox(width: 6),
                const Text('CONSOLE'),
                if (_consoleLogs.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_consoleLogs.length}',
                      style: const TextStyle(fontSize: 9, color: Colors.white70),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowserViewport() {
    Widget content;

    if (_webViewController != null && !widget.forceFallbackForTesting) {
      content = WebViewWidget(controller: _webViewController!);
    } else {
      content = _buildFallbackPreview();
    }

    if (_viewportPreset.width == null) {
      return Container(
        color: const Color(0xFF121214),
        child: content,
      );
    }

    // Centered fixed-width device frame simulation
    return Container(
      color: const Color(0xFF0D0D0E),
      alignment: Alignment.center,
      child: Container(
        width: _viewportPreset.width,
        decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          border: Border.all(color: const Color(0xFF3F3F46), width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }

  Widget _buildFallbackPreview() {
    final res = _inspectionResult;
    return Container(
      padding: const EdgeInsets.all(24),
      color: const Color(0xFF18181B),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              res?.isReachable == true
                  ? Icons.language
                  : Icons.cloud_off_outlined,
              size: 48,
              color: res?.isReachable == true
                  ? const Color(0xFF5AF78E)
                  : Colors.white38,
            ),
            const SizedBox(height: 16),
            Text(
              res?.isReachable == true
                  ? 'Dev Server Live at :$_currentPort'
                  : 'Server Offline on :$_currentPort',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _currentUrl,
              style: const TextStyle(
                color: Colors.white54,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            if (res?.statusCode != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: res!.isHttpSuccess
                      ? const Color(0xFF5AF78E).withValues(alpha: 0.15)
                      : const Color(0xFFFF5555).withValues(alpha: 0.15),
                  border: Border.all(
                    color: res.isHttpSuccess
                        ? const Color(0xFF5AF78E)
                        : const Color(0xFFFF5555),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'HTTP ${res.statusCode} ${res.statusReason ?? ''}',
                  style: TextStyle(
                    color: res.isHttpSuccess
                        ? const Color(0xFF5AF78E)
                        : const Color(0xFFFF5555),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _openExternally,
              icon: const Icon(Icons.open_in_browser, size: 16),
              label: const Text('Open in External Chrome'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF5AF78E),
                side: const BorderSide(color: Color(0xFF5AF78E)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkInspector() {
    final res = _inspectionResult;

    if (_isInspecting && res == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF5AF78E)),
      );
    }

    if (res == null || !res.isReachable) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white38, size: 40),
            const SizedBox(height: 12),
            Text(
              'No response from $_currentUrl',
              style: const TextStyle(color: Colors.white70, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadInspection,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF27272A),
              ),
              child: const Text('Retry Probe', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary metrics row
        Row(
          children: [
            _buildMetricCard(
              'STATUS',
              '${res.statusCode ?? '-'}',
              subtitle: res.statusReason ?? 'OK',
              color: res.isHttpSuccess
                  ? const Color(0xFF5AF78E)
                  : const Color(0xFFFF5555),
            ),
            const SizedBox(width: 12),
            _buildMetricCard(
              'LATENCY',
              '${res.latencyMs}ms',
              subtitle: 'Roundtrip',
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            _buildMetricCard(
              'SIZE',
              res.contentLength != null ? '${res.contentLength} B' : 'Chunked',
              subtitle: 'Payload',
              color: Colors.white,
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'RESPONSE HEADERS',
          style: TextStyle(
            color: Colors.white54,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF121214),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF27272A)),
          ),
          child: Column(
            children: [
              for (final entry in res.headers.entries)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFF27272A))),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            color: Color(0xFF5AF78E),
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: entry.value));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Copied: ${entry.key}'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        child: const Icon(
                          Icons.copy,
                          size: 14,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String label,
    String value, {
    required String subtitle,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF121214),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF27272A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsoleInspector() {
    final filtered = _consoleLogs.where((log) {
      if (_consoleFilter == 'ERRORS') return log.level == 'ERROR';
      if (_consoleFilter == 'WARNS') return log.level == 'WARN';
      return true;
    }).toList();

    return Column(
      children: [
        // Filter toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: const BoxDecoration(
            color: Color(0xFF121214),
            border: Border(bottom: BorderSide(color: Color(0xFF27272A))),
          ),
          child: Row(
            children: [
              _buildFilterChip('ALL', 'All (${_consoleLogs.length})'),
              const SizedBox(width: 8),
              _buildFilterChip(
                'ERRORS',
                'Errors (${_consoleLogs.where((l) => l.level == 'ERROR').length})',
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white54),
                tooltip: 'Clear Console',
                onPressed: () {
                  setState(() => _consoleLogs.clear());
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'No console output recorded.',
                    style: TextStyle(color: Colors.white38, fontFamily: 'monospace'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, idx) {
                    final log = filtered[idx];
                    final isErr = log.level == 'ERROR';
                    final isWarn = log.level == 'WARN';
                    final color = isErr
                        ? const Color(0xFFFF5555)
                        : (isWarn ? const Color(0xFFFFB000) : Colors.white70);
                    final icon = isErr
                        ? Icons.error_outline
                        : (isWarn ? Icons.warning_amber : Icons.chevron_right);

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isErr
                            ? const Color(0xFFFF5555).withValues(alpha: 0.08)
                            : Colors.transparent,
                        border: const Border(
                          bottom: BorderSide(color: Color(0xFF202024)),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, size: 14, color: color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              log.message,
                              style: TextStyle(
                                color: color,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Text(
                            '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: Colors.white24,
                              fontFamily: 'monospace',
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _consoleFilter == key;
    return InkWell(
      onTap: () => setState(() => _consoleFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF5AF78E).withValues(alpha: 0.15)
              : const Color(0xFF27272A),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? const Color(0xFF5AF78E) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF5AF78E) : Colors.white70,
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
