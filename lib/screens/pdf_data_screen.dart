import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfDataScreen extends StatefulWidget {
  final Uint8List pdfData;
  final String filename;
  final String? password;

  const PdfDataScreen({
    super.key,
    required this.pdfData,
    required this.filename,
    this.password,
  });

  @override
  State<PdfDataScreen> createState() => _PdfDataScreenState();
}

class _PdfDataScreenState extends State<PdfDataScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  String _extractedText = '';
  List<PdfTableData> _tables = [];
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _extractPdfData();
  }

  Future<void> _extractPdfData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load PDF document with optional password
      final PdfDocument document;
      if (widget.password != null && widget.password!.isNotEmpty) {
        document = PdfDocument(
          inputBytes: widget.pdfData,
          password: widget.password!,
        );
      } else {
        document = PdfDocument(inputBytes: widget.pdfData);
      }

      _pageCount = document.pages.count;

      // Extract text from all pages
      final StringBuffer textBuffer = StringBuffer();
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      
      for (int i = 0; i < document.pages.count; i++) {
        final String pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
        if (pageText.isNotEmpty) {
          textBuffer.writeln('--- Page ${i + 1} ---\n');
          textBuffer.writeln(pageText);
          textBuffer.writeln('\n');
        }
      }

      // Try to extract table data
      _tables = _extractTables(extractor, document.pages.count);

      _extractedText = textBuffer.toString();
      
      // Dispose document
      document.dispose();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  List<PdfTableData> _extractTables(PdfTextExtractor extractor, int pageCount) {
    final List<PdfTableData> tables = [];
    
    try {
      for (int i = 0; i < pageCount; i++) {
        // Get text lines with layout
        final List<TextLine> lines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
        
        // Group lines that could be table rows (similar Y positions)
        final Map<double, List<TextLine>> rowGroups = {};
        
        for (final line in lines) {
          // Round Y position to group nearby lines
          final double yKey = (line.bounds.top / 5).round() * 5.0;
          rowGroups.putIfAbsent(yKey, () => []);
          rowGroups[yKey]!.add(line);
        }

        // Find potential tables (rows with multiple columns)
        List<List<String>> currentTable = [];
        
        final sortedKeys = rowGroups.keys.toList()..sort();
        
        for (final yKey in sortedKeys) {
          final rowLines = rowGroups[yKey]!;
          if (rowLines.length > 1) {
            // Sort by X position
            rowLines.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
            final row = rowLines.map((l) => l.text.trim()).toList();
            currentTable.add(row);
          } else if (currentTable.isNotEmpty && currentTable.length >= 2) {
            // End of table
            tables.add(PdfTableData(
              pageNumber: i + 1,
              rows: List.from(currentTable),
            ));
            currentTable = [];
          }
        }
        
        // Add remaining table
        if (currentTable.length >= 2) {
          tables.add(PdfTableData(
            pageNumber: i + 1,
            rows: currentTable,
          ));
        }
      }
    } catch (e) {
      print('Table extraction error: $e');
    }
    
    return tables;
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
              // App Bar
              _buildAppBar(),
              
              // Content
              Expanded(
                child: _buildContent(),
              ),
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
                Text(
                  widget.filename,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Extracted PDF Data',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (!_isLoading && _errorMessage == null)
            IconButton(
              icon: const Icon(Icons.copy_rounded, color: Colors.white70),
              onPressed: _copyToClipboard,
              tooltip: 'Copy all text',
            ),
        ],
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
            const Text(
              'Extracting PDF data...',
              style: TextStyle(color: Colors.white70),
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
                'Failed to Extract PDF',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!.contains('password')
                    ? 'Incorrect password or the PDF is encrypted.'
                    : _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          // Stats Card
          _buildStatsCard(),
          
          // Tab Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey[500],
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(12),
              ),
              tabs: const [
                Tab(text: 'Raw Text'),
                Tab(text: 'Tables'),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Tab Content
          Expanded(
            child: TabBarView(
              children: [
                _buildTextTab(),
                _buildTablesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF3D3D5C).withOpacity(0.5),
        ),
      ),
      child: Row(
        children: [
          _buildStatItem(
            icon: Icons.description_outlined,
            label: 'Pages',
            value: '$_pageCount',
            color: const Color(0xFF6366F1),
          ),
          _buildStatDivider(),
          _buildStatItem(
            icon: Icons.text_fields_rounded,
            label: 'Characters',
            value: _formatNumber(_extractedText.length),
            color: const Color(0xFF10B981),
          ),
          _buildStatDivider(),
          _buildStatItem(
            icon: Icons.table_chart_outlined,
            label: 'Tables',
            value: '${_tables.length}',
            color: const Color(0xFFF59E0B),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 40,
      color: const Color(0xFF3D3D5C),
    );
  }

  Widget _buildTextTab() {
    if (_extractedText.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.text_snippet_outlined, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No text content found',
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF3D3D5C).withOpacity(0.5),
        ),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          _extractedText,
          style: TextStyle(
            color: Colors.grey[300],
            fontSize: 13,
            height: 1.6,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildTablesTab() {
    if (_tables.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_chart_outlined, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No tables detected',
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Tables with columnar data will appear here',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _tables.length,
      itemBuilder: (context, index) {
        final table = _tables[index];
        return _buildTableCard(table, index);
      },
    );
  }

  Widget _buildTableCard(PdfTableData table, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
          // Table header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.table_chart_rounded,
                    color: Color(0xFFF59E0B),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Table ${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252542),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Page ${table.pageNumber}',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Table content
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(const Color(0xFF252542)),
              dataRowColor: MaterialStateProperty.all(Colors.transparent),
              border: TableBorder.all(
                color: const Color(0xFF3D3D5C),
                width: 1,
                borderRadius: BorderRadius.circular(8),
              ),
              columns: table.rows.isNotEmpty
                  ? table.rows.first
                      .map((cell) => DataColumn(
                            label: Text(
                              cell,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ))
                      .toList()
                  : [],
              rows: table.rows.length > 1
                  ? table.rows
                      .skip(1)
                      .map((row) => DataRow(
                            cells: row
                                .map((cell) => DataCell(
                                      Text(
                                        cell,
                                        style: TextStyle(
                                          color: Colors.grey[300],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ))
                      .toList()
                  : [],
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _extractedText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF10B981)),
            SizedBox(width: 12),
            Text(
              'Text copied to clipboard',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }
}

class PdfTableData {
  final int pageNumber;
  final List<List<String>> rows;

  PdfTableData({
    required this.pageNumber,
    required this.rows,
  });
}
