import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../services/gmail_service.dart';

class BatchProcessScreen extends StatefulWidget {
  final GmailService gmailService;
  final List<SenderInfo> selectedSenders;

  const BatchProcessScreen({
    super.key,
    required this.gmailService,
    required this.selectedSenders,
  });

  @override
  State<BatchProcessScreen> createState() => _BatchProcessScreenState();
}

class _BatchProcessScreenState extends State<BatchProcessScreen> {
  int _currentIndex = 0;
  EmailMessage? _currentEmail;
  Uint8List? _currentPdfData;
  bool _isLoadingEmail = true;
  bool _isValidatingPdf = false;
  String? _errorMessage;
  String? _pdfError;
  final TextEditingController _passwordController = TextEditingController();
  
  // Store extracted data for completed senders
  final Map<String, ExtractedPdfData> _extractedData = {};
  
  @override
  void initState() {
    super.initState();
    _loadCurrentSenderEmail();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  SenderInfo get _currentSender => widget.selectedSenders[_currentIndex];
  
  bool get _isLastSender => _currentIndex >= widget.selectedSenders.length - 1;

  Future<void> _loadCurrentSenderEmail() async {
    setState(() {
      _isLoadingEmail = true;
      _errorMessage = null;
      _pdfError = null;
      _currentEmail = null;
      _currentPdfData = null;
      _passwordController.clear();
    });

    try {
      final email = await widget.gmailService.getLatestEmailFromSender(
        _currentSender.email,
      );
      
      if (email != null && email.attachments.isNotEmpty) {
        // Download the first PDF attachment
        final pdfData = await widget.gmailService.downloadAttachment(
          email,
          email.attachments.first,
        );
        
        setState(() {
          _currentEmail = email;
          _currentPdfData = pdfData;
          _isLoadingEmail = false;
        });
      } else {
        setState(() {
          _currentEmail = email;
          _isLoadingEmail = false;
          _errorMessage = 'No PDF attachment found';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load email: ${e.toString()}';
        _isLoadingEmail = false;
      });
    }
  }

  Future<void> _validateAndProceed() async {
    if (_currentPdfData == null) return;

    setState(() {
      _isValidatingPdf = true;
      _pdfError = null;
    });

    try {
      final password = _passwordController.text;
      
      // Try to open the PDF with the given password
      final PdfDocument document;
      if (password.isNotEmpty) {
        document = PdfDocument(
          inputBytes: _currentPdfData!,
          password: password,
        );
      } else {
        document = PdfDocument(inputBytes: _currentPdfData!);
      }

      // Extract text to verify it works
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final StringBuffer textBuffer = StringBuffer();
      
      for (int i = 0; i < document.pages.count; i++) {
        final String pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
        textBuffer.writeln(pageText);
      }

      // Store extracted data
      _extractedData[_currentSender.email] = ExtractedPdfData(
        sender: _currentSender,
        email: _currentEmail!,
        extractedText: textBuffer.toString(),
        password: password.isEmpty ? null : password,
        pageCount: document.pages.count,
      );

      document.dispose();

      setState(() {
        _isValidatingPdf = false;
      });

      // Move to next sender or finish
      if (_isLastSender) {
        _showCompletionDialog();
      } else {
        setState(() {
          _currentIndex++;
        });
        _loadCurrentSenderEmail();
      }
    } catch (e) {
      setState(() {
        _isValidatingPdf = false;
        _pdfError = e.toString().contains('password') 
            ? 'Incorrect password. Please try again.'
            : 'Failed to open PDF: ${e.toString()}';
      });
    }
  }

  void _skipCurrentSender() {
    if (_isLastSender) {
      _showCompletionDialog();
    } else {
      setState(() {
        _currentIndex++;
      });
      _loadCurrentSenderEmail();
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: Color(0xFF10B981),
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Processing Complete',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Successfully processed ${_extractedData.length} of ${widget.selectedSenders.length} senders.',
              style: TextStyle(color: Colors.grey[300], fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF252542),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, color: Color(0xFF6366F1)),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_extractedData.length} PDFs extracted',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${widget.selectedSenders.length - _extractedData.length} skipped',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to senders list
            },
            child: Text(
              'Back to List',
              style: TextStyle(color: Colors.grey[400]),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _navigateToResults();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('View Results'),
          ),
        ],
      ),
    );
  }

  void _navigateToResults() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => BatchResultsScreen(
          extractedData: _extractedData.values.toList(),
        ),
      ),
    );
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
              _buildHeader(),
              _buildProgressIndicator(),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            onPressed: () => _showExitConfirmation(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Batch Processing',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Sender ${_currentIndex + 1} of ${widget.selectedSenders.length}',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _isLoadingEmail || _isValidatingPdf ? null : _skipCurrentSender,
            child: const Text(
              'Skip',
              style: TextStyle(color: Color(0xFFF59E0B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: List.generate(widget.selectedSenders.length, (index) {
              Color color;
              if (index < _currentIndex) {
                color = _extractedData.containsKey(widget.selectedSenders[index].email)
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B);
              } else if (index == _currentIndex) {
                color = const Color(0xFF6366F1);
              } else {
                color = const Color(0xFF3D3D5C);
              }
              
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index < widget.selectedSenders.length - 1 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Done: ${_extractedData.length}', 
                    style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                ],
              ),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3D3D5C),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Remaining: ${widget.selectedSenders.length - _currentIndex - 1}', 
                    style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoadingEmail) {
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
            Text(
              'Loading email from ${_currentSender.displayName}...',
              style: const TextStyle(color: Colors.white70),
            ),
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
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.red,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[300], fontSize: 14),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: _loadCurrentSenderEmail,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey[600]!),
                    ),
                    child: const Text('Retry'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _skipCurrentSender,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                    ),
                    child: const Text('Skip Sender'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current Sender Card
          _buildSenderCard(),
          const SizedBox(height: 16),
          
          // Email Preview
          if (_currentEmail != null) _buildEmailPreview(),
          const SizedBox(height: 16),
          
          // Password Input
          if (_currentPdfData != null) _buildPasswordSection(),
        ],
      ),
    );
  }

  Widget _buildSenderCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6366F1).withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                _getInitials(_currentSender.displayName),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentSender.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _currentSender.email,
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
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
            child: Text(
              '${_currentSender.messageCount} emails',
              style: const TextStyle(
                color: Color(0xFF6366F1),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailPreview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF3D3D5C).withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.email_outlined, color: Color(0xFF6366F1), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Latest Email',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM d, yyyy').format(_currentEmail!.date),
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _currentEmail!.subject,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          // Attachment info
          if (_currentEmail!.attachments.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF252542),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf_rounded, 
                    color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentEmail!.attachments.first.filename,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPasswordSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _pdfError != null 
              ? Colors.red.withOpacity(0.5)
              : const Color(0xFF3D3D5C).withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'PDF Password',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF252542),
              borderRadius: BorderRadius.circular(12),
              border: _pdfError != null 
                  ? Border.all(color: Colors.red.withOpacity(0.5))
                  : null,
            ),
            child: TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter password (leave empty if none)',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
                prefixIcon: Icon(Icons.key_rounded, color: Colors.grey[600]),
              ),
              onSubmitted: (_) => _validateAndProceed(),
            ),
          ),
          if (_pdfError != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _pdfError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Enter the password to unlock and extract PDF data',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isValidatingPdf ? null : _validateAndProceed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isValidatingPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline),
                        const SizedBox(width: 8),
                        Text(
                          _isLastSender ? 'Validate & Finish' : 'Validate & Next',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Exit Batch Processing?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'You have processed ${_extractedData.length} senders. Exit now?',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Continue', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.split(RegExp(r'[\s@]'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return '?';
  }
}

class ExtractedPdfData {
  final SenderInfo sender;
  final EmailMessage email;
  final String extractedText;
  final String? password;
  final int pageCount;

  ExtractedPdfData({
    required this.sender,
    required this.email,
    required this.extractedText,
    this.password,
    required this.pageCount,
  });
}

// Results screen to show all extracted data
class BatchResultsScreen extends StatelessWidget {
  final List<ExtractedPdfData> extractedData;

  const BatchResultsScreen({super.key, required this.extractedData});

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
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Extracted Data',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${extractedData.length} PDFs processed',
                            style: TextStyle(color: Colors.grey[400], fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // List of extracted data
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: extractedData.length,
                  itemBuilder: (context, index) {
                    final data = extractedData[index];
                    return _buildResultCard(context, data, index);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(BuildContext context, ExtractedPdfData data, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF3D3D5C).withOpacity(0.5),
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.all(16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF10B981), Color(0xFF34D399)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white),
        ),
        title: Text(
          data.sender.displayName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${data.pageCount} pages • ${_formatCharCount(data.extractedText.length)}',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
        iconColor: Colors.grey[400],
        collapsedIconColor: Colors.grey[600],
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF252542),
              borderRadius: BorderRadius.circular(12),
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: SelectableText(
                data.extractedText.isEmpty 
                    ? 'No text content extracted'
                    : data.extractedText,
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: data.extractedText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF1A1A2E),
                        behavior: SnackBarBehavior.floating,
                        content: Text('Copied text from ${data.sender.displayName}'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy Text'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6366F1),
                    side: const BorderSide(color: Color(0xFF6366F1)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatCharCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K chars';
    }
    return '$count chars';
  }
}
