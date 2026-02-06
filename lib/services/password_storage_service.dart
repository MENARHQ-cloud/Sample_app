import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PasswordStorageService {
  static const String _passwordsKey = 'sender_passwords';
  static const String _extractionHistoryKey = 'extraction_history';
  
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Password Management
  Future<void> savePassword(String senderEmail, String password) async {
    final passwords = await getPasswords();
    passwords[senderEmail.toLowerCase()] = password;
    await _prefs?.setString(_passwordsKey, jsonEncode(passwords));
  }

  Future<String?> getPassword(String senderEmail) async {
    final passwords = await getPasswords();
    return passwords[senderEmail.toLowerCase()];
  }

  Future<Map<String, String>> getPasswords() async {
    final jsonStr = _prefs?.getString(_passwordsKey);
    if (jsonStr == null) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      return {};
    }
  }

  Future<void> removePassword(String senderEmail) async {
    final passwords = await getPasswords();
    passwords.remove(senderEmail.toLowerCase());
    await _prefs?.setString(_passwordsKey, jsonEncode(passwords));
  }

  // Extraction History Management
  Future<void> saveExtractionRecord(ExtractionRecord record) async {
    final history = await getExtractionHistory();
    
    // Find existing record for this sender or add new
    final existingIndex = history.indexWhere(
      (r) => r.senderEmail.toLowerCase() == record.senderEmail.toLowerCase()
    );
    
    if (existingIndex >= 0) {
      // Merge with existing record
      final existing = history[existingIndex];
      final mergedEmails = {...existing.extractedEmails, ...record.extractedEmails};
      history[existingIndex] = ExtractionRecord(
        senderEmail: record.senderEmail,
        senderName: record.senderName,
        extractedEmails: mergedEmails,
        lastExtractionDate: record.lastExtractionDate,
        totalPdfsExtracted: mergedEmails.length,
      );
    } else {
      history.add(record);
    }
    
    await _saveExtractionHistory(history);
  }

  Future<List<ExtractionRecord>> getExtractionHistory() async {
    final jsonStr = _prefs?.getString(_extractionHistoryKey);
    if (jsonStr == null) return [];
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((e) => ExtractionRecord.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<ExtractionRecord?> getExtractionRecord(String senderEmail) async {
    final history = await getExtractionHistory();
    try {
      return history.firstWhere(
        (r) => r.senderEmail.toLowerCase() == senderEmail.toLowerCase()
      );
    } catch (e) {
      return null;
    }
  }

  Future<Set<int>> getExtractedEmailIds(String senderEmail) async {
    final record = await getExtractionRecord(senderEmail);
    return record?.extractedEmails.keys.map((k) => int.parse(k)).toSet() ?? {};
  }

  Future<void> _saveExtractionHistory(List<ExtractionRecord> history) async {
    final jsonStr = jsonEncode(history.map((r) => r.toJson()).toList());
    await _prefs?.setString(_extractionHistoryKey, jsonStr);
  }

  Future<void> clearAllData() async {
    await _prefs?.remove(_passwordsKey);
    await _prefs?.remove(_extractionHistoryKey);
  }
}

class ExtractionRecord {
  final String senderEmail;
  final String senderName;
  final Map<String, ExtractedEmailInfo> extractedEmails; // key: emailId
  final DateTime lastExtractionDate;
  final int totalPdfsExtracted;

  ExtractionRecord({
    required this.senderEmail,
    required this.senderName,
    required this.extractedEmails,
    required this.lastExtractionDate,
    required this.totalPdfsExtracted,
  });

  factory ExtractionRecord.fromJson(Map<String, dynamic> json) {
    final emails = (json['extractedEmails'] as Map<String, dynamic>?)?.map(
      (key, value) => MapEntry(key, ExtractedEmailInfo.fromJson(value)),
    ) ?? {};
    
    return ExtractionRecord(
      senderEmail: json['senderEmail'] ?? '',
      senderName: json['senderName'] ?? '',
      extractedEmails: emails,
      lastExtractionDate: DateTime.tryParse(json['lastExtractionDate'] ?? '') ?? DateTime.now(),
      totalPdfsExtracted: json['totalPdfsExtracted'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'senderEmail': senderEmail,
    'senderName': senderName,
    'extractedEmails': extractedEmails.map((k, v) => MapEntry(k, v.toJson())),
    'lastExtractionDate': lastExtractionDate.toIso8601String(),
    'totalPdfsExtracted': totalPdfsExtracted,
  };
}

class ExtractedEmailInfo {
  final String subject;
  final DateTime date;
  final String pdfFilename;
  final String extractedText;
  final int pageCount;

  ExtractedEmailInfo({
    required this.subject,
    required this.date,
    required this.pdfFilename,
    required this.extractedText,
    required this.pageCount,
  });

  factory ExtractedEmailInfo.fromJson(Map<String, dynamic> json) {
    return ExtractedEmailInfo(
      subject: json['subject'] ?? '',
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      pdfFilename: json['pdfFilename'] ?? '',
      extractedText: json['extractedText'] ?? '',
      pageCount: json['pageCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'subject': subject,
    'date': date.toIso8601String(),
    'pdfFilename': pdfFilename,
    'extractedText': extractedText,
    'pageCount': pageCount,
  };
}
