import 'package:flutter/material.dart';
import '../services/gmail_service.dart';
import '../services/password_storage_service.dart';
import 'email_detail_screen.dart';
import 'batch_process_screen.dart';
import 'login_screen.dart';

class SendersListScreen extends StatefulWidget {
  final GmailService gmailService;
  final PasswordStorageService passwordStorage;

  const SendersListScreen({
    super.key,
    required this.gmailService,
    required this.passwordStorage,
  });

  @override
  State<SendersListScreen> createState() => _SendersListScreenState();
}

class _SendersListScreenState extends State<SendersListScreen> 
    with SingleTickerProviderStateMixin {
  List<SenderInfo> _senders = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isSelectionMode = false;
  final Set<String> _selectedSenders = {};
  Map<String, ExtractionRecord> _extractionHistory = {};
  
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load senders and extraction history in parallel
      final senders = await widget.gmailService.getSendersWithStatementPdf();
      final history = await widget.passwordStorage.getExtractionHistory();
      
      final historyMap = <String, ExtractionRecord>{};
      for (final record in history) {
        historyMap[record.senderEmail.toLowerCase()] = record;
      }
      
      setState(() {
        _senders = senders;
        _extractionHistory = historyMap;
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load senders: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    await widget.gmailService.disconnect();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedSenders.clear();
      }
    });
  }

  void _toggleSenderSelection(String email) {
    setState(() {
      if (_selectedSenders.contains(email)) {
        _selectedSenders.remove(email);
      } else {
        _selectedSenders.add(email);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedSenders.length == _senders.length) {
        _selectedSenders.clear();
      } else {
        _selectedSenders.addAll(_senders.map((s) => s.email));
      }
    });
  }

  void _startBatchProcessing({bool isRerun = false}) {
    if (_selectedSenders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF1A1A2E),
          behavior: SnackBarBehavior.floating,
          content: Text('Please select at least one sender'),
        ),
      );
      return;
    }

    final selectedSendersList = _senders
        .where((s) => _selectedSenders.contains(s.email))
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BatchProcessScreen(
          gmailService: widget.gmailService,
          selectedSenders: selectedSendersList,
          passwordStorage: widget.passwordStorage,
          isRerun: isRerun,
        ),
      ),
    ).then((_) {
      // Reload data when coming back
      _loadData();
      setState(() {
        _isSelectionMode = false;
        _selectedSenders.clear();
      });
    });
  }

  ExtractionRecord? _getExtractionRecord(String email) {
    return _extractionHistory[email.toLowerCase()];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F0F23),
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              
              if (_isSelectionMode && _senders.isNotEmpty)
                _buildSelectionBar(),
              
              Expanded(
                child: _buildContent(),
              ),
              
              if (_isSelectionMode && _selectedSenders.isNotEmpty)
                _buildBottomActionBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isSelectionMode ? Icons.checklist_rounded : Icons.people_outline_rounded,
              color: const Color(0xFF6366F1),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isSelectionMode ? 'Select Senders' : 'Statement Senders',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _isSelectionMode
                      ? '${_selectedSenders.length} of ${_senders.length} selected'
                      : '${_senders.length} sender${_senders.length != 1 ? 's' : ''} with PDF statements',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (!_isLoading && _senders.isNotEmpty) ...[
            IconButton(
              icon: Icon(
                _isSelectionMode ? Icons.close_rounded : Icons.checklist_rounded,
                color: _isSelectionMode ? Colors.white : Colors.white70,
              ),
              onPressed: _toggleSelectionMode,
              tooltip: _isSelectionMode ? 'Cancel' : 'Multi-select',
            ),
          ],
          if (!_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              onPressed: _isLoading ? null : _loadData,
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.white70),
              onPressed: _logout,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectionBar() {
    // Check if any selected sender has extraction history (for re-run button)
    final hasHistorySelected = _selectedSenders.any(
      (email) => _extractionHistory.containsKey(email.toLowerCase())
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3D3D5C).withOpacity(0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _selectAll,
            child: Row(
              children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: _selectedSenders.length == _senders.length
                        ? const Color(0xFF6366F1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _selectedSenders.length == _senders.length
                          ? const Color(0xFF6366F1)
                          : Colors.grey[600]!,
                      width: 2,
                    ),
                  ),
                  child: _selectedSenders.length == _senders.length
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  _selectedSenders.length == _senders.length ? 'Deselect All' : 'Select All',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (hasHistorySelected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.history, color: Color(0xFF10B981), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Has history',
                    style: TextStyle(color: Colors.green[400], fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    // Check if selected senders have history (for re-run option)
    final hasHistorySelected = _selectedSenders.any(
      (email) => _extractionHistory.containsKey(email.toLowerCase())
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        border: Border(
          top: BorderSide(color: const Color(0xFF3D3D5C).withOpacity(0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _startBatchProcessing(isRerun: false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.play_arrow_rounded),
                    const SizedBox(width: 8),
                    Text(
                      'Extract ${_selectedSenders.length} Sender${_selectedSenders.length > 1 ? 's' : ''} (Full)',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            if (hasHistorySelected) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _startBatchProcessing(isRerun: true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6366F1),
                    side: const BorderSide(color: Color(0xFF6366F1)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded, size: 20),
                      SizedBox(width: 8),
                      Text('Re-run (New Emails Only)', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Searching for statement emails...', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('This may take a moment', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
              ),
              const SizedBox(height: 20),
              Text('Something went wrong', style: TextStyle(color: Colors.grey[300], fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              const SizedBox(height: 24),
              ElevatedButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded), label: const Text('Try Again')),
            ],
          ),
        ),
      );
    }

    if (_senders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(20)),
                child: Icon(Icons.inbox_rounded, color: Colors.grey[600], size: 64),
              ),
              const SizedBox(height: 24),
              Text('No Statements Found', style: TextStyle(color: Colors.grey[300], fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('No emails with "statement" in the subject\nand PDF attachments were found.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 14)),
              const SizedBox(height: 24),
              ElevatedButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded), label: const Text('Refresh')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF6366F1),
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, _isSelectionMode ? 12 : 8, 16, _isSelectionMode && _selectedSenders.isNotEmpty ? 160 : 8),
        itemCount: _senders.length,
        itemBuilder: (context, index) {
          final sender = _senders[index];
          final isSelected = _selectedSenders.contains(sender.email);
          final extractionRecord = _getExtractionRecord(sender.email);
          
          return _SenderCard(
            sender: sender,
            index: index,
            isSelectionMode: _isSelectionMode,
            isSelected: isSelected,
            extractionRecord: extractionRecord,
            onTap: () {
              if (_isSelectionMode) {
                _toggleSenderSelection(sender.email);
              } else {
                _navigateToEmailDetail(sender);
              }
            },
            onLongPress: () {
              if (!_isSelectionMode) {
                _toggleSelectionMode();
                _toggleSenderSelection(sender.email);
              }
            },
          );
        },
      ),
    );
  }

  void _navigateToEmailDetail(SenderInfo sender) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            EmailDetailScreen(gmailService: widget.gmailService, sender: sender),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }
}

class _SenderCard extends StatelessWidget {
  final SenderInfo sender;
  final int index;
  final bool isSelectionMode;
  final bool isSelected;
  final ExtractionRecord? extractionRecord;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SenderCard({
    required this.sender,
    required this.index,
    required this.isSelectionMode,
    required this.isSelected,
    required this.extractionRecord,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorIndex = sender.email.hashCode % _gradientColors.length;
    final gradientColors = _gradientColors[colorIndex];
    final hasExtracted = extractionRecord != null;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 200 + (index * 50)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected 
                    ? const Color(0xFF6366F1).withOpacity(0.15)
                    : const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected 
                      ? const Color(0xFF6366F1)
                      : hasExtracted
                          ? const Color(0xFF10B981).withOpacity(0.3)
                          : const Color(0xFF3D3D5C).withOpacity(0.5),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isSelectionMode) ...[
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 26, height: 26,
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF6366F1) : Colors.grey[600]!,
                              width: 2,
                            ),
                          ),
                          child: isSelected 
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                              : null,
                        ),
                        const SizedBox(width: 12),
                      ],
                      
                      Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            _getInitials(sender.displayName),
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sender.displayName,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sender.email,
                              style: TextStyle(color: Colors.grey[400], fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.mail_outline_rounded, color: Color(0xFF6366F1), size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${sender.messageCount}',
                              style: const TextStyle(color: Color(0xFF6366F1), fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      
                      if (!isSelectionMode) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                      ],
                    ],
                  ),
                  
                  // Extraction history indicator
                  if (hasExtracted) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            '${extractionRecord!.totalPdfsExtracted} PDFs extracted',
                            style: TextStyle(color: Colors.green[400], fontSize: 11),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '• Last: ${_formatDate(extractionRecord!.lastExtractionDate)}',
                            style: TextStyle(color: Colors.grey[500], fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.split(RegExp(r'[\s@]'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    return '?';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  static const List<List<Color>> _gradientColors = [
    [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    [Color(0xFF10B981), Color(0xFF34D399)],
    [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    [Color(0xFFEF4444), Color(0xFFF87171)],
    [Color(0xFF3B82F6), Color(0xFF60A5FA)],
    [Color(0xFFEC4899), Color(0xFFF472B6)],
    [Color(0xFF14B8A6), Color(0xFF2DD4BF)],
    [Color(0xFFF97316), Color(0xFFFB923C)],
  ];
}
