import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../services/gmail_service.dart';
import '../services/password_storage_service.dart';

class BatchProcessScreen extends StatefulWidget {
  final GmailService gmailService;
  final List<SenderInfo> selectedSenders;
  final PasswordStorageService passwordStorage;
  final bool isRerun; // true if running for already-processed senders

  const BatchProcessScreen({
    super.key,
    required this.gmailService,
    required this.selectedSenders,
    required this.passwordStorage,
    this.isRerun = false,
  });

  @override
  State<BatchProcessScreen> createState() => _BatchProcessScreenState();
}

class _BatchProcessScreenState extends State<BatchProcessScreen> {
  // Phase 1: Password validation
  int _currentIndex = 0;
  EmailMessage? _currentEmail;
  Uint8List? _currentPdfData;
  bool _isLoadingEmail = true;
  bool _isValidatingPdf = false;
  String? _errorMessage;
  String? _pdfError;
  final TextEditingController _passwordController = TextEditingController();
  
  // Store validated passwords
  final Map<String, String> _validatedPasswords = {};
  
  // Phase 2: Extraction
  bool _isExtractionPhase = false;
  bool _isExtracting = false;
  int _extractionSenderIndex = 0;
  int _extractionEmailIndex = 0;
  int _totalEmailsToExtract = 0;
  int _extractedCount = 0;
  String _currentExtractionStatus = '';
  
  // Final results
  final Map<String, SenderExtractionResult> _extractionResults = {};
  
  @override
  void initState() {
    super.initState();
    _loadSavedPasswords();
  }

  Future<void> _loadSavedPasswords() async {
    // Pre-load saved passwords
    for (final sender in widget.selectedSenders) {
      final savedPassword = await widget.passwordStorage.getPassword(sender.email);
      if (savedPassword != null) {
        _validatedPasswords[sender.email] = savedPassword;
      }
    }
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
    });

    // Check if we have a saved password
    final savedPassword = _validatedPasswords[_currentSender.email];
    if (savedPassword != null) {
      _passwordController.text = savedPassword;
    } else {
      _passwordController.clear();
    }

    try {
      final email = await widget.gmailService.getLatestEmailFromSender(
        _currentSender.email,
      );
      
      if (email != null && email.attachments.isNotEmpty) {
        final pdfData = await widget.gmailService.downloadAttachment(
          email,
          email.attachments.first,
        );
        
        setState(() {
          _currentEmail = email;
          _currentPdfData = pdfData;
          _isLoadingEmail = false;
        });
        
        // Auto-validate if we have a saved password
        if (savedPassword != null && savedPassword.isNotEmpty) {
          _autoValidate(savedPassword);
        }
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

  Future<void> _autoValidate(String password) async {
    if (_currentPdfData == null) return;

    try {
      final PdfDocument document;
      if (password.isNotEmpty) {
        document = PdfDocument(
          inputBytes: _currentPdfData!,
          password: password,
        );
      } else {
        document = PdfDocument(inputBytes: _currentPdfData!);
      }
      document.dispose();
      
      // Password works - move to next
      _moveToNext();
    } catch (e) {
      // Password didn't work - user needs to re-enter
      _passwordController.clear();
      _validatedPasswords.remove(_currentSender.email);
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
      
      final PdfDocument document;
      if (password.isNotEmpty) {
        document = PdfDocument(
          inputBytes: _currentPdfData!,
          password: password,
        );
      } else {
        document = PdfDocument(inputBytes: _currentPdfData!);
      }
      document.dispose();

      // Save the validated password
      _validatedPasswords[_currentSender.email] = password;
      await widget.passwordStorage.savePassword(_currentSender.email, password);

      setState(() {
        _isValidatingPdf = false;
      });

      _moveToNext();
    } catch (e) {
      setState(() {
        _isValidatingPdf = false;
        _pdfError = e.toString().contains('password') 
            ? 'Incorrect password. Please try again.'
            : 'Failed to open PDF: ${e.toString()}';
      });
    }
  }

  void _moveToNext() {
    if (_isLastSender) {
      // Start extraction phase
      _startExtractionPhase();
    } else {
      setState(() {
        _currentIndex++;
      });
      _loadCurrentSenderEmail();
    }
  }

  void _skipCurrentSender() {
    // Remove from validated passwords
    _validatedPasswords.remove(_currentSender.email);
    
    if (_isLastSender) {
      if (_validatedPasswords.isEmpty) {
        // No senders validated - go back
        Navigator.pop(context);
      } else {
        _startExtractionPhase();
      }
    } else {
      setState(() {
        _currentIndex++;
      });
      _loadCurrentSenderEmail();
    }
  }

  Future<void> _startExtractionPhase() async {
    if (_validatedPasswords.isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _isExtractionPhase = true;
      _isExtracting = true;
      _extractionSenderIndex = 0;
      _extractedCount = 0;
    });

    // Get senders with validated passwords
    final validatedSenders = widget.selectedSenders
        .where((s) => _validatedPasswords.containsKey(s.email))
        .toList();

    // Calculate total emails to extract
    int totalEmails = 0;
    for (final sender in validatedSenders) {
      totalEmails += sender.messageCount;
    }
    
    setState(() {
      _totalEmailsToExtract = totalEmails;
    });

    // Extract from each sender
    for (int i = 0; i < validatedSenders.length; i++) {
      final sender = validatedSenders[i];
      final password = _validatedPasswords[sender.email] ?? '';
      
      setState(() {
        _extractionSenderIndex = i;
        _currentExtractionStatus = 'Fetching emails from ${sender.displayName}...';
      });

      try {
        // Get already extracted email IDs for re-run
        Set<int>? excludeIds;
        if (widget.isRerun) {
          excludeIds = await widget.passwordStorage.getExtractedEmailIds(sender.email);
        }

        // Fetch all emails from this sender
        final emails = await widget.gmailService.getAllEmailsFromSender(
          sender.email,
          excludeIds: excludeIds,
        );

        final extractedEmails = <String, ExtractedEmailInfo>{};
        int successCount = 0;
        int failCount = 0;

        // Extract PDF data from each email
        for (int j = 0; j < emails.length; j++) {
          final email = emails[j];
          
          setState(() {
            _extractionEmailIndex = j;
            _currentExtractionStatus = 
                'Extracting ${j + 1}/${emails.length} from ${sender.displayName}';
          });

          try {
            // Download PDF
            final pdfData = await widget.gmailService.downloadAttachment(
              email,
              email.attachments.first,
            );

            if (pdfData != null) {
              // Extract text
              final extractedText = await _extractPdfText(pdfData, password);
              
              if (extractedText != null) {
                extractedEmails[email.sequenceId.toString()] = ExtractedEmailInfo(
                  subject: email.subject,
                  date: email.date,
                  pdfFilename: email.attachments.first.filename,
                  extractedText: extractedText.text,
                  pageCount: extractedText.pageCount,
                );
                successCount++;
              } else {
                failCount++;
              }
            } else {
              failCount++;
            }
          } catch (e) {
            print('Error extracting email ${email.sequenceId}: $e');
            failCount++;
          }

          setState(() {
            _extractedCount++;
          });
        }

        // Save extraction record
        await widget.passwordStorage.saveExtractionRecord(ExtractionRecord(
          senderEmail: sender.email,
          senderName: sender.displayName,
          extractedEmails: extractedEmails,
          lastExtractionDate: DateTime.now(),
          totalPdfsExtracted: extractedEmails.length,
        ));

        _extractionResults[sender.email] = SenderExtractionResult(
          sender: sender,
          totalEmails: emails.length,
          successCount: successCount,
          failCount: failCount,
          extractedData: extractedEmails,
        );

      } catch (e) {
        print('Error processing sender ${sender.email}: $e');
        _extractionResults[sender.email] = SenderExtractionResult(
          sender: sender,
          totalEmails: 0,
          successCount: 0,
          failCount: 0,
          extractedData: {},
          error: e.toString(),
        );
      }
    }

    setState(() {
      _isExtracting = false;
    });
  }

  Future<_ExtractedPdfResult?> _extractPdfText(Uint8List pdfData, String password) async {
    try {
      final PdfDocument document;
      if (password.isNotEmpty) {
        document = PdfDocument(inputBytes: pdfData, password: password);
      } else {
        document = PdfDocument(inputBytes: pdfData);
      }

      final extractor = PdfTextExtractor(document);
      final buffer = StringBuffer();
      
      for (int i = 0; i < document.pages.count; i++) {
        buffer.writeln(extractor.extractText(startPageIndex: i, endPageIndex: i));
      }

      final pageCount = document.pages.count;
      document.dispose();

      return _ExtractedPdfResult(text: buffer.toString(), pageCount: pageCount);
    } catch (e) {
      print('PDF extraction error: $e');
      return null;
    }
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
          child: _isExtractionPhase
              ? _buildExtractionPhase()
              : _buildPasswordPhase(),
        ),
      ),
    );
  }

  Widget _buildPasswordPhase() {
    return Column(
      children: [
        _buildPasswordHeader(),
        _buildPasswordProgressIndicator(),
        Expanded(child: _buildPasswordContent()),
      ],
    );
  }

  Widget _buildPasswordHeader() {
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
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
            onPressed: () => _showExitConfirmation(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Step 1: Validate Passwords',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Sender ${_currentIndex + 1} of ${widget.selectedSenders.length}',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _isLoadingEmail || _isValidatingPdf ? null : _skipCurrentSender,
            child: const Text('Skip', style: TextStyle(color: Color(0xFFF59E0B))),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordProgressIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: List.generate(widget.selectedSenders.length, (index) {
              Color color;
              if (_validatedPasswords.containsKey(widget.selectedSenders[index].email)) {
                color = const Color(0xFF10B981);
              } else if (index == _currentIndex) {
                color = const Color(0xFF6366F1);
              } else if (index < _currentIndex) {
                color = const Color(0xFFF59E0B); // Skipped
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
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Validated: ${_validatedPasswords.length}', 
                    style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                ],
              ),
              Row(
                children: [
                  Container(
                    width: 10, height: 10,
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

  Widget _buildPasswordContent() {
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
      return _buildErrorState();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSenderCard(),
          const SizedBox(height: 16),
          if (_currentEmail != null) _buildEmailPreview(),
          const SizedBox(height: 16),
          if (_currentPdfData != null) _buildPasswordSection(),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
                  child: const Text('Skip Sender'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSenderCard() {
    final hasSavedPassword = _validatedPasswords.containsKey(_currentSender.email);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasSavedPassword 
              ? const Color(0xFF10B981).withOpacity(0.5)
              : const Color(0xFF6366F1).withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: hasSavedPassword 
                    ? [const Color(0xFF10B981), const Color(0xFF34D399)]
                    : [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: hasSavedPassword
                  ? const Icon(Icons.check_rounded, color: Colors.white)
                  : Text(
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
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _currentSender.email,
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
                if (hasSavedPassword)
                  Text(
                    'Password saved',
                    style: TextStyle(color: Colors.green[400], fontSize: 11),
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
              '${_currentSender.messageCount} PDFs',
              style: const TextStyle(
                color: Color(0xFF6366F1), fontSize: 12, fontWeight: FontWeight.bold,
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
        border: Border.all(color: const Color(0xFF3D3D5C).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.email_outlined, color: Color(0xFF6366F1), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Latest Email (for password validation)',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _currentEmail!.subject,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            DateFormat('MMM d, yyyy').format(_currentEmail!.date),
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          if (_currentEmail!.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF252542),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFEF4444), size: 20),
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
                child: const Icon(Icons.lock_outline_rounded, color: Color(0xFF6366F1), size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'PDF Password',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF252542),
              borderRadius: BorderRadius.circular(12),
              border: _pdfError != null ? Border.all(color: Colors.red.withOpacity(0.5)) : null,
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
                  child: Text(_pdfError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'This password will be saved and used for all PDFs from this sender',
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isValidatingPdf
                  ? const SizedBox(
                      width: 20, height: 20,
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
                          _isLastSender ? 'Validate & Start Extraction' : 'Validate & Next',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtractionPhase() {
    if (_isExtracting) {
      return _buildExtractionProgress();
    } else {
      return _buildExtractionComplete();
    }
  }

  Widget _buildExtractionProgress() {
    final progress = _totalEmailsToExtract > 0 
        ? _extractedCount / _totalEmailsToExtract 
        : 0.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 100, height: 100,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 8,
                          backgroundColor: const Color(0xFF3D3D5C),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                        ),
                      ),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Step 2: Extracting PDFs',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentExtractionStatus,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$_extractedCount of $_totalEmailsToExtract emails processed',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E).withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatItem(
                    icon: Icons.people_outlined,
                    label: 'Senders',
                    value: '${_extractionSenderIndex + 1}/${_validatedPasswords.length}',
                  ),
                  Container(width: 1, height: 40, color: const Color(0xFF3D3D5C)),
                  _buildStatItem(
                    icon: Icons.check_circle_outline,
                    label: 'Extracted',
                    value: '$_extractedCount',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF6366F1), size: 24),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ],
    );
  }

  Widget _buildExtractionComplete() {
    int totalSuccess = 0;
    int totalFail = 0;
    for (final result in _extractionResults.values) {
      totalSuccess += result.successCount;
      totalFail += result.failCount;
    }

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF10B981), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Extraction Complete!',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$totalSuccess PDFs extracted successfully',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Summary Card
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF3D3D5C).withOpacity(0.5)),
          ),
          child: Row(
            children: [
              _buildSummaryItem('Senders', '${_extractionResults.length}', const Color(0xFF6366F1)),
              Container(width: 1, height: 50, color: const Color(0xFF3D3D5C)),
              _buildSummaryItem('PDFs Extracted', '$totalSuccess', const Color(0xFF10B981)),
              Container(width: 1, height: 50, color: const Color(0xFF3D3D5C)),
              _buildSummaryItem('Failed', '$totalFail', const Color(0xFFEF4444)),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Results list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _extractionResults.length,
            itemBuilder: (context, index) {
              final result = _extractionResults.values.toList()[index];
              return _buildResultCard(result);
            },
          ),
        ),

        // Actions
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            border: Border(top: BorderSide(color: const Color(0xFF3D3D5C).withOpacity(0.5))),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey[600]!),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Back to List'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DatasetViewScreen(
                            extractionResults: _extractionResults,
                            passwordStorage: widget.passwordStorage,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('View Dataset'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildResultCard(SenderExtractionResult result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3D3D5C).withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: result.error != null 
                  ? const Color(0xFFEF4444).withOpacity(0.2)
                  : const Color(0xFF10B981).withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              result.error != null ? Icons.error_outline : Icons.check_rounded,
              color: result.error != null ? const Color(0xFFEF4444) : const Color(0xFF10B981),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.sender.displayName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                Text(
                  result.error ?? '${result.successCount} PDFs extracted',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (result.error == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${result.successCount}',
                style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Exit Processing?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Validated passwords will be saved for future use.',
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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

class _ExtractedPdfResult {
  final String text;
  final int pageCount;
  _ExtractedPdfResult({required this.text, required this.pageCount});
}

class SenderExtractionResult {
  final SenderInfo sender;
  final int totalEmails;
  final int successCount;
  final int failCount;
  final Map<String, ExtractedEmailInfo> extractedData;
  final String? error;

  SenderExtractionResult({
    required this.sender,
    required this.totalEmails,
    required this.successCount,
    required this.failCount,
    required this.extractedData,
    this.error,
  });
}

// Dataset View Screen
class DatasetViewScreen extends StatefulWidget {
  final Map<String, SenderExtractionResult> extractionResults;
  final PasswordStorageService passwordStorage;

  const DatasetViewScreen({
    super.key,
    required this.extractionResults,
    required this.passwordStorage,
  });

  @override
  State<DatasetViewScreen> createState() => _DatasetViewScreenState();
}

class _DatasetViewScreenState extends State<DatasetViewScreen> {
  String? _selectedSender;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final allText = _getAllExtractedText();
    
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0F23), Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildSenderFilter(),
              Expanded(child: _buildDatasetContent()),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    int totalPdfs = 0;
    int totalChars = 0;
    for (final result in widget.extractionResults.values) {
      for (final email in result.extractedData.values) {
        totalPdfs++;
        totalChars += email.extractedText.length;
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Extracted Dataset',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildStatBox('Senders', '${widget.extractionResults.length}', const Color(0xFF6366F1)),
                const SizedBox(width: 16),
                _buildStatBox('PDFs', '$totalPdfs', const Color(0xFF10B981)),
                const SizedBox(width: 16),
                _buildStatBox('Characters', _formatCount(totalChars), const Color(0xFFF59E0B)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildSenderFilter() {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip('All', _selectedSender == null),
          ...widget.extractionResults.values.map((result) => 
            _buildFilterChip(result.sender.displayName, _selectedSender == result.sender.email,
              email: result.sender.email,
              count: result.successCount,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, {String? email, int? count}) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedSender = email;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF3D3D5C),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[400],
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withOpacity(0.2) : const Color(0xFF3D3D5C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[500],
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDatasetContent() {
    final filteredResults = _selectedSender == null
        ? widget.extractionResults.values.toList()
        : [widget.extractionResults[_selectedSender]!];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredResults.length,
      itemBuilder: (context, index) {
        final result = filteredResults[index];
        return _buildSenderDataCard(result);
      },
    );
  }

  Widget _buildSenderDataCard(SenderExtractionResult result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3D3D5C).withOpacity(0.5)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.all(16),
        childrenPadding: EdgeInsets.zero,
        title: Text(
          result.sender.displayName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${result.successCount} PDFs extracted',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
        iconColor: Colors.grey[400],
        collapsedIconColor: Colors.grey[600],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        children: result.extractedData.values.map((email) => 
          _buildEmailDataItem(email)
        ).toList(),
      ),
    );
  }

  Widget _buildEmailDataItem(ExtractedEmailInfo email) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: const Color(0xFF3D3D5C).withOpacity(0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  email.subject,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                DateFormat('MMM d, yyyy').format(email.date),
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF252542),
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxHeight: 150),
            child: SingleChildScrollView(
              child: SelectableText(
                email.extractedText.isEmpty ? 'No text extracted' : email.extractedText,
                style: TextStyle(color: Colors.grey[300], fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.description_outlined, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text('${email.pageCount} pages', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
              const SizedBox(width: 16),
              Icon(Icons.text_fields, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(_formatCount(email.extractedText.length), style: TextStyle(color: Colors.grey[600], fontSize: 11)),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: email.extractedText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Text copied to clipboard'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text('Copy', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        border: Border(top: BorderSide(color: const Color(0xFF3D3D5C).withOpacity(0.5))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _copyAllText,
                icon: const Icon(Icons.copy_all_rounded, size: 18),
                label: const Text('Copy All'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey[600]!),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Done'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getAllExtractedText() {
    final buffer = StringBuffer();
    for (final result in widget.extractionResults.values) {
      buffer.writeln('=== ${result.sender.displayName} ===\n');
      for (final email in result.extractedData.values) {
        buffer.writeln('--- ${email.subject} (${DateFormat('yyyy-MM-dd').format(email.date)}) ---');
        buffer.writeln(email.extractedText);
        buffer.writeln('\n');
      }
      buffer.writeln('\n');
    }
    return buffer.toString();
  }

  void _copyAllText() {
    final text = _getAllExtractedText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF10B981)),
            const SizedBox(width: 12),
            Text('Copied all text (${_formatCount(text.length)} chars)', 
              style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}
