import 'dart:async';
import 'dart:typed_data';
import 'package:enough_mail/enough_mail.dart';

class SenderInfo {
  final String email;
  final String name;
  final int messageCount;

  SenderInfo({
    required this.email,
    required this.name,
    required this.messageCount,
  });

  String get displayName => name.isNotEmpty ? name : email;
}

class EmailMessage {
  final String subject;
  final String from;
  final String fromName;
  final DateTime date;
  final String body;
  final List<AttachmentInfo> attachments;
  final int sequenceId;

  EmailMessage({
    required this.subject,
    required this.from,
    required this.fromName,
    required this.date,
    required this.body,
    required this.attachments,
    required this.sequenceId,
  });
}

class AttachmentInfo {
  final String filename;
  final String mimeType;
  final int size;
  final String partId;

  AttachmentInfo({
    required this.filename,
    required this.mimeType,
    required this.size,
    required this.partId,
  });
}

class GmailService {
  ImapClient? _imapClient;
  String? _email;
  String? _appPassword;

  bool get isConnected => _imapClient?.isLoggedIn ?? false;

  Future<bool> authenticate(String email, String appPassword) async {
    try {
      _email = email;
      _appPassword = appPassword;

      _imapClient = ImapClient(isLogEnabled: false);
      
      await _imapClient!.connectToServer(
        'imap.gmail.com',
        993,
        isSecure: true,
      );

      await _imapClient!.login(email, appPassword);
      
      return true;
    } catch (e) {
      print('Authentication error: $e');
      await disconnect();
      return false;
    }
  }

  /// Ensures the IMAP connection is active, reconnects if needed
  Future<bool> ensureConnected() async {
    try {
      if (_imapClient != null && _imapClient!.isLoggedIn) {
        // Try a simple operation to verify connection is alive
        try {
          await _imapClient!.noop();
          return true;
        } catch (e) {
          print('Connection check failed, reconnecting: $e');
        }
      }

      // Need to reconnect
      if (_email != null && _appPassword != null) {
        print('Reconnecting to IMAP...');
        _imapClient = ImapClient(isLogEnabled: false);
        await _imapClient!.connectToServer('imap.gmail.com', 993, isSecure: true);
        await _imapClient!.login(_email!, _appPassword!);
        print('Reconnected successfully');
        return true;
      }
      
      return false;
    } catch (e) {
      print('Reconnection failed: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      if (_imapClient != null && _imapClient!.isConnected) {
        await _imapClient!.logout();
      }
    } catch (e) {
      print('Disconnect error: $e');
    } finally {
      _imapClient = null;
    }
  }

  Future<List<SenderInfo>> getSendersWithStatementPdf() async {
    if (_imapClient == null || !_imapClient!.isLoggedIn) {
      throw Exception('Not authenticated');
    }

    try {
      // Select INBOX
      await _imapClient!.selectInbox();

      // Search for emails with "statement" in subject
      final searchResult = await _imapClient!.searchMessages(
        searchCriteria: 'SUBJECT "statement"',
      );

      if (searchResult.matchingSequence == null || 
          searchResult.matchingSequence!.isEmpty) {
        return [];
      }

      // Fetch messages to check for PDF attachments
      final messages = await _imapClient!.fetchMessages(
        searchResult.matchingSequence!,
        '(ENVELOPE BODYSTRUCTURE)',
      );

      // Group by sender and filter for PDF attachments
      final Map<String, List<MimeMessage>> senderMessages = {};

      for (final message in messages.messages) {
        if (_hasPdfAttachment(message)) {
          final from = message.from?.first;
          if (from != null) {
            final email = from.email.toLowerCase();
            senderMessages.putIfAbsent(email, () => []);
            senderMessages[email]!.add(message);
          }
        }
      }

      // Convert to SenderInfo list
      return senderMessages.entries.map((entry) {
        final firstMessage = entry.value.first;
        final from = firstMessage.from?.first;
        return SenderInfo(
          email: entry.key,
          name: from?.personalName ?? '',
          messageCount: entry.value.length,
        );
      }).toList()
        ..sort((a, b) => b.messageCount.compareTo(a.messageCount));
    } catch (e) {
      print('Error fetching senders: $e');
      rethrow;
    }
  }

  bool _hasPdfAttachment(MimeMessage message) {
    final bodyStructure = message.body;
    if (bodyStructure == null) return false;
    
    return _checkPartForPdf(bodyStructure);
  }

  bool _checkPartForPdf(BodyPart part) {
    final mediaType = part.contentType?.mediaType.toString().toLowerCase() ?? '';
    final filename = part.contentDisposition?.filename?.toLowerCase() ?? '';
    
    if (mediaType == 'application/pdf' || filename.endsWith('.pdf')) {
      return true;
    }
    
    if (part.parts != null) {
      for (final subPart in part.parts!) {
        if (_checkPartForPdf(subPart)) {
          return true;
        }
      }
    }
    
    return false;
  }

  Future<EmailMessage?> getLatestEmailFromSender(String senderEmail) async {
    // Ensure we have an active connection
    final connected = await ensureConnected();
    if (!connected) {
      throw Exception('Not authenticated - please login again');
    }

    try {
      print('Fetching latest email from: $senderEmail');
      
      await _imapClient!.selectInbox();

      // Search for emails from sender with "statement" in subject
      // Try exact email match first
      print('Searching for emails from: $senderEmail');
      var searchResult = await _imapClient!.searchMessages(
        searchCriteria: 'FROM "$senderEmail" SUBJECT "statement"',
      );

      // If no results, try a broader search with just the domain part
      if (searchResult.matchingSequence == null || 
          searchResult.matchingSequence!.isEmpty) {
        print('No exact match, trying broader search...');
        // Try with just the email address without quotes
        searchResult = await _imapClient!.searchMessages(
          searchCriteria: 'FROM $senderEmail SUBJECT statement',
        );
      }

      if (searchResult.matchingSequence == null || 
          searchResult.matchingSequence!.isEmpty) {
        print('No emails found from $senderEmail with statement subject');
        return null;
      }

      // Get the latest message (last in sequence)
      final sequence = searchResult.matchingSequence!;
      final sequenceIds = sequence.toList();
      print('Found ${sequenceIds.length} emails, fetching latest (ID: ${sequenceIds.last})');
      
      final latestId = sequenceIds.last;
      final latestSequence = MessageSequence.fromId(latestId);

      // Fetch the full message with body
      final messages = await _imapClient!.fetchMessages(
        latestSequence,
        '(ENVELOPE BODY[] BODYSTRUCTURE)',
      );

      if (messages.messages.isEmpty) {
        print('Failed to fetch message content');
        return null;
      }

      final message = messages.messages.first;
      print('Fetched email: ${message.decodeSubject()}');
      
      // Extract attachments
      final attachments = <AttachmentInfo>[];
      _extractPdfAttachments(message.body, attachments, '');
      print('Found ${attachments.length} PDF attachment(s)');

      return EmailMessage(
        subject: message.decodeSubject() ?? 'No Subject',
        from: message.from?.first.email ?? 'Unknown',
        fromName: message.from?.first.personalName ?? '',
        date: message.decodeDate() ?? DateTime.now(),
        body: message.decodeTextHtmlPart() ?? message.decodeTextPlainPart() ?? '',
        attachments: attachments,
        sequenceId: latestId,
      );
    } catch (e) {
      print('Error fetching email from $senderEmail: $e');
      rethrow;
    }
  }

  void _extractPdfAttachments(BodyPart? part, List<AttachmentInfo> attachments, String parentId) {
    if (part == null) return;

    final mediaType = part.contentType?.mediaType.toString().toLowerCase() ?? '';
    final filename = part.contentDisposition?.filename ?? 
                     part.contentType?.parameters['name'] ?? '';
    
    // Build the part ID
    String partId = parentId.isEmpty ? '1' : parentId;
    
    if (mediaType == 'application/pdf' || filename.toLowerCase().endsWith('.pdf')) {
      attachments.add(AttachmentInfo(
        filename: filename.isNotEmpty ? filename : 'attachment.pdf',
        mimeType: 'application/pdf',
        size: part.size ?? 0,
        partId: partId,
      ));
    }
    
    if (part.parts != null) {
      for (int i = 0; i < part.parts!.length; i++) {
        final subPartId = parentId.isEmpty ? '${i + 1}' : '$parentId.${i + 1}';
        _extractPdfAttachments(part.parts![i], attachments, subPartId);
      }
    }
  }

  Future<Uint8List?> downloadAttachment(EmailMessage email, AttachmentInfo attachment) async {
    if (_imapClient == null || !_imapClient!.isLoggedIn) {
      throw Exception('Not authenticated');
    }

    try {
      await _imapClient!.selectInbox();
      
      // Fetch the specific body part for the attachment
      final sequence = MessageSequence.fromId(email.sequenceId);
      
      // Fetch with full body to get attachment data
      final fetchResult = await _imapClient!.fetchMessages(
        sequence,
        '(BODY[])',
      );

      if (fetchResult.messages.isEmpty) return null;

      final message = fetchResult.messages.first;
      
      // Find and decode the PDF attachment in MIME parts
      return _findPdfInMimeParts(message);
    } catch (e) {
      print('Error downloading attachment: $e');
      return null;
    }
  }

  Uint8List? _findPdfInMimeParts(MimeMessage message) {
    // If message itself has PDF content
    final headerMediaType = message.mediaType.toString().toLowerCase();
    if (headerMediaType == 'application/pdf') {
      return message.decodeContentBinary();
    }
    
    // Try to find in nested parts
    if (message.parts != null) {
      for (final part in message.parts!) {
        final result = _searchMimePartForPdf(part);
        if (result != null) return result;
      }
    }
    
    return null;
  }


  Uint8List? _searchMimePartForPdf(MimePart part) {
    final contentType = part.mediaType.toString().toLowerCase();
    final filename = part.decodeFileName()?.toLowerCase() ?? '';
    
    if (contentType == 'application/pdf' || filename.endsWith('.pdf')) {
      return part.decodeContentBinary();
    }
    
    // Search nested parts
    if (part.parts != null) {
      for (final subPart in part.parts!) {
        final result = _searchMimePartForPdf(subPart);
        if (result != null) return result;
      }
    }
    
    return null;
  }

  /// Get all emails from a specific sender within the last 2 years
  /// [excludeIds] - Set of sequence IDs to exclude (already extracted)
  Future<List<EmailMessage>> getAllEmailsFromSender(
    String senderEmail, {
    Set<int>? excludeIds,
  }) async {
    // Ensure we have an active connection
    final connected = await ensureConnected();
    if (!connected) {
      throw Exception('Not authenticated - please login again');
    }

    try {
      await _imapClient!.selectInbox();

      // Calculate date 2 years ago
      final twoYearsAgo = DateTime.now().subtract(const Duration(days: 730));
      final dateStr = '${twoYearsAgo.day}-${_monthName(twoYearsAgo.month)}-${twoYearsAgo.year}';

      // Search for emails from sender with "statement" in subject since 2 years ago
      final searchResult = await _imapClient!.searchMessages(
        searchCriteria: 'FROM "$senderEmail" SUBJECT "statement" SINCE $dateStr',
      );

      if (searchResult.matchingSequence == null || 
          searchResult.matchingSequence!.isEmpty) {
        return [];
      }

      final sequence = searchResult.matchingSequence!;
      final allIds = sequence.toList();
      
      // Filter out already extracted IDs
      final idsToFetch = excludeIds != null 
          ? allIds.where((id) => !excludeIds.contains(id)).toList()
          : allIds;

      if (idsToFetch.isEmpty) {
        return [];
      }

      final emails = <EmailMessage>[];

      // Fetch emails in batches of 10 to avoid timeout
      for (int i = 0; i < idsToFetch.length; i += 10) {
        final batchEnd = (i + 10 < idsToFetch.length) ? i + 10 : idsToFetch.length;
        final batchIds = idsToFetch.sublist(i, batchEnd);
        
        for (final msgId in batchIds) {
          try {
            final msgSequence = MessageSequence.fromId(msgId);
            final messages = await _imapClient!.fetchMessages(
              msgSequence,
              '(ENVELOPE BODY[] BODYSTRUCTURE)',
            );

            if (messages.messages.isNotEmpty) {
              final message = messages.messages.first;
              
              // Check if it has PDF attachments
              final attachments = <AttachmentInfo>[];
              _extractPdfAttachments(message.body, attachments, '');
              
              if (attachments.isNotEmpty) {
                emails.add(EmailMessage(
                  subject: message.decodeSubject() ?? 'No Subject',
                  from: message.from?.first.email ?? 'Unknown',
                  fromName: message.from?.first.personalName ?? '',
                  date: message.decodeDate() ?? DateTime.now(),
                  body: message.decodeTextHtmlPart() ?? message.decodeTextPlainPart() ?? '',
                  attachments: attachments,
                  sequenceId: msgId,
                ));
              }
            }
          } catch (e) {
            print('Error fetching message $msgId: $e');
            // Continue with next message
          }
        }
      }

      // Sort by date descending (newest first)
      emails.sort((a, b) => b.date.compareTo(a.date));
      
      return emails;
    } catch (e) {
      print('Error fetching all emails: $e');
      rethrow;
    }
  }

  String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}
