import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/git_credential_service.dart';
import '../services/git_ssh_service.dart';

/// Modal dialog for managing Git HTTPS Personal Access Tokens (PAT)
/// and RFC 8032 Ed25519 SSH Keypairs.
///
/// Complies with Termode Anti-Slop UI guidelines: 90% Zinc/Slate neutral,
/// 10% emerald/cyan spot accent, crisp borders, and zero AI gradient blobs.
class GitCredentialsDialog extends StatefulWidget {
  const GitCredentialsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const GitCredentialsDialog(),
    );
  }

  @override
  State<GitCredentialsDialog> createState() => _GitCredentialsDialogState();
}

class _GitCredentialsDialogState extends State<GitCredentialsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GitCredentialService _credService = GitCredentialService();
  final GitSshService _sshService = GitSshService();

  // State
  List<GitCredential> _credentials = [];
  bool _loadingCreds = true;

  bool _hasSshKey = false;
  String? _sshPublicKey;
  String? _sshFingerprint;
  bool _loadingSsh = true;

  // New Credential Form
  bool _showAddForm = false;
  final _hostController = TextEditingController(text: 'https://github.com');
  final _userController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _obscureToken = true;

  // SSH Form
  final _commentController = TextEditingController(text: 'termode@android');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hostController.dispose();
    _userController.dispose();
    _tokenController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadCredentials(),
      _loadSshStatus(),
    ]);
  }

  Future<void> _loadCredentials() async {
    setState(() => _loadingCreds = true);
    final creds = await _credService.listCredentials();
    if (mounted) {
      setState(() {
        _credentials = creds;
        _loadingCreds = false;
      });
    }
  }

  Future<void> _loadSshStatus() async {
    setState(() => _loadingSsh = true);
    final hasKey = await _sshService.hasKeyPair();
    String? pub;
    String? fp;
    if (hasKey) {
      pub = await _sshService.getPublicKey();
      fp = await _sshService.getFingerprint();
    }
    if (mounted) {
      setState(() {
        _hasSshKey = hasKey;
        _sshPublicKey = pub;
        _sshFingerprint = fp;
        _loadingSsh = false;
      });
    }
  }

  Future<void> _saveCredential() async {
    final host = _hostController.text.trim();
    final user = _userController.text.trim();
    final token = _tokenController.text.trim();

    if (host.isEmpty || user.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    await _credService.store(host: host, username: user, token: token);
    _userController.clear();
    _tokenController.clear();
    setState(() => _showAddForm = false);
    await _loadCredentials();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Credential stored for $host')),
      );
    }
  }

  Future<void> _deleteCredential(String host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        title: const Text('Delete Credential', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          'Remove credentials for $host from ~/.git-credentials?',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _credService.erase(host: host);
      await _loadCredentials();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed credential for $host')),
        );
      }
    }
  }

  Future<void> _generateSshKey() async {
    setState(() => _loadingSsh = true);
    final comment = _commentController.text.trim().isEmpty
        ? 'termode@android'
        : _commentController.text.trim();
    await _sshService.generateKeyPair(comment: comment, overwrite: true);
    await _loadSshStatus();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generated authentic Ed25519 SSH keypair')),
      );
    }
  }

  Future<void> _deleteSshKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        title: const Text('Delete SSH Keypair', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'Delete ~/.ssh/id_ed25519 and ~/.ssh/id_ed25519.pub? This cannot be undone.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _sshService.deleteKeyPair();
      await _loadSshStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deleted SSH keypair')),
        );
      }
    }
  }

  void _copyPublicKey() {
    if (_sshPublicKey != null) {
      Clipboard.setData(ClipboardData(text: _sshPublicKey!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Public key copied to clipboard (ready for GitHub/GitLab)'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF18181B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF27272A)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 680,
          maxHeight: 640,
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.security, color: Color(0xFF38BDF8), size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Git Credentials & SSH Keys',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Tab Bar
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF27272A)),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF38BDF8),
                indicatorWeight: 2,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(icon: Icon(Icons.lock_outline, size: 18), text: 'HTTPS Credentials'),
                  Tab(icon: Icon(Icons.vpn_key_outlined, size: 18), text: 'SSH Keys (Ed25519)'),
                ],
              ),
            ),
            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildHttpsTab(),
                  _buildSshTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHttpsTab() {
    if (_loadingCreds) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'STORED CREDENTIALS (~/.git-credentials)',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              if (!_showAddForm)
                ElevatedButton.icon(
                  onPressed: () => setState(() => _showAddForm = true),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Credential', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF27272A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_showAddForm) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF09090B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Add Git Personal Access Token (PAT)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54, size: 16),
                        onPressed: () => setState(() => _showAddForm = false),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _hostController,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      labelText: 'Host / URL',
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
                      isDense: true,
                      border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF27272A))),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF27272A))),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _userController,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
                      isDense: true,
                      border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF27272A))),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF27272A))),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tokenController,
                    obscureText: _obscureToken,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: 'Token / PAT (e.g. ghp_...)',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                      isDense: true,
                      border: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF27272A))),
                      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF27272A))),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureToken ? Icons.visibility : Icons.visibility_off,
                          color: Colors.white54,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _obscureToken = !_obscureToken),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _showAddForm = false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _saveCredential,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF38BDF8),
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Save Credential', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_credentials.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF09090B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.vpn_lock_outlined, color: Colors.white24, size: 36),
                  SizedBox(height: 12),
                  Text(
                    'No Credentials Stored',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Add a Personal Access Token to clone, pull, and push private repositories without prompting.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ] else ...[
            for (final cred in _credentials) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF09090B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF27272A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.dns, color: Color(0xFF38BDF8), size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cred.host,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'User: ${cred.username} • Token: ${cred.maskedToken}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                      tooltip: 'Delete credential',
                      onPressed: () => _deleteCredential(cred.host),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSshTab() {
    if (_loadingSsh) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'RFC 8032 ED25519 KEYPAIR (~/.ssh/id_ed25519)',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _hasSshKey ? const Color(0xFF00FF66).withValues(alpha: 0.15) : Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _hasSshKey ? const Color(0xFF00FF66).withValues(alpha: 0.3) : Colors.white24,
                  ),
                ),
                child: Text(
                  _hasSshKey ? 'ACTIVE' : 'NOT FOUND',
                  style: TextStyle(
                    color: _hasSshKey ? const Color(0xFF00FF66) : Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_hasSshKey) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF09090B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No SSH Key Found',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Generate an Ed25519 keypair to authenticate with GitHub, GitLab, and Bitbucket over SSH.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _commentController,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      labelText: 'Key Comment / Email',
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
                      isDense: true,
                      border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF27272A))),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF27272A))),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _generateSshKey,
                    icon: const Icon(Icons.key, size: 16),
                    label: const Text('Generate Ed25519 Keypair', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF09090B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fingerprint (SHA256)',
                    style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _sshFingerprint ?? 'calculating...',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text(
                        'Public Key (~/.ssh/id_ed25519.pub)',
                        style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _copyPublicKey,
                        icon: const Icon(Icons.copy, size: 14),
                        label: const Text('Copy Key', style: TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF38BDF8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF27272A)),
                    ),
                    child: SelectableText(
                      _sshPublicKey ?? '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _generateSshKey,
                        icon: const Icon(Icons.refresh, size: 14),
                        label: const Text('Regenerate Keypair', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Color(0xFF27272A)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _deleteSshKey,
                        icon: const Icon(Icons.delete_outline, size: 14),
                        label: const Text('Delete Keypair', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Color(0xFF27272A)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
