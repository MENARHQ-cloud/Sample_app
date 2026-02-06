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
    if (_imapClient == null || !_imapClient!.isLoggedIn) {
      throw Exception('Not authenticated');
    }

    try {
      await _imapClient!.selectInbox();

      // Search for emails from sender with "statement" in subject
      final searchResult = await _imapClient!.searchMessages(
        searchCriteria: 'FROM "$senderEmail" SUBJECT "statement"',
      );

      if (searchResult.matchingSequence == null || 
          searchResult.matchingSequence!.isEmpty) {
        return null;
      }

      // Get the latest message (last in sequence)
      final sequence = searchResult.matchingSequence!;
      final sequenceIds = sequence.toList();
      final latestId = sequenceIds.last;
      final latestSequence = MessageSequence.fromId(latestId);

      // Fetch the full message with body
      final messages = await _imapClient!.fetchMessages(
        latestSequence,
        '(ENVELOPE BODY[] BODYSTRUCTURE)',
      );

      if (messages.messages.isEmpty) return null;

      final message = messages.messages.first;
      
      // Extract attachments
      final attachments = <AttachmentInfo>[];
      _extractPdfAttachments(message.body, attachments, '');

      return EmailMessage(
        subject: message.decodeSubject() ?? 'No Subject',
        from: message.from?.first.email ?? 'Unknown',
        fromName: message.from?.first.personalName ?? '',
        date: message.decodeDate() ?? DateTime.now(),
        body: message.decodeTextPlainPart() ?? message.decodeTextHtmlPart() ?? '',
        attachments: attachments,
        sequenceId: latestId,
      );
    } catch (e) {
      print('Error fetching email: $e');
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
}
