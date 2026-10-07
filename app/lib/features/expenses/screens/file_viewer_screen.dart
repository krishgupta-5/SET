import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../theme/app_theme.dart';

class FileViewerScreen extends StatefulWidget {
  final String fileId;
  final String fileName;
  final String? filePath;

  const FileViewerScreen({
    super.key,
    required this.fileId,
    required this.fileName,
    this.filePath,
  });

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  bool _isLoading = true;
  String? _error;
  String? _fileUrl;
  String? _textPreview;
  bool _textLoadError = false;
  bool _isWebViewLoading = true;
  WebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _loadFileUrl();
  }

  Future<void> _loadFileUrl() async {
    try {
      await dotenv.load(fileName: ".env.local");
      final botToken = dotenv.env['TELEGRAM_BOT_TOKEN'];

      if (botToken == null) {
        throw Exception('Telegram bot token not found');
      }

      // Get file info first
      final fileInfoResponse = await http.get(
        Uri.parse(
          "https://api.telegram.org/bot$botToken/getFile?file_id=${widget.fileId}",
        ),
      );

      if (fileInfoResponse.statusCode != 200) {
        throw Exception('Failed to get file info');
      }

      final fileInfoData = jsonDecode(fileInfoResponse.body);
      if (!fileInfoData['ok']) {
        throw Exception('File not found');
      }

      final fileInfo = fileInfoData['result'];
      final filePath = fileInfo['file_path'] as String;
      final fileUrl = "https://api.telegram.org/file/bot$botToken/$filePath";

      if (_isTextFile(widget.fileName)) {
        try {
          final textResponse = await http.get(Uri.parse(fileUrl));
          if (textResponse.statusCode == 200) {
            _textPreview = textResponse.body;
          } else {
            _textLoadError = true;
          }
        } catch (_) {
          _textLoadError = true;
        }
      }

      if (_isWebPreviewSupported(widget.fileName) && mounted) {
        _webViewController = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(const Color(0x00000000))
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (_) {
                if (mounted) {
                  setState(() => _isWebViewLoading = true);
                }
              },
              onPageFinished: (_) {
                if (mounted) {
                  setState(() => _isWebViewLoading = false);
                }
              },
              onNavigationRequest: (request) {
                return NavigationDecision.navigate;
              },
            ),
          )
          ..loadRequest(
            Uri.parse(
              'https://docs.google.com/viewer?url=${Uri.encodeComponent(fileUrl)}&embedded=true',
            ),
          );
      }

      setState(() {
        _fileUrl = fileUrl;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showMinimalToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError
                  ? const Color(0xFFFF453A)
                  : const Color(0xFF30D158),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.cardBackground,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.borderColor),
        ),
        duration: const Duration(seconds: 3),
        elevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor),
              boxShadow: context.cardShadow,
            ),
            child: Icon(Icons.arrow_back, color: context.textPrimary, size: 20),
          ),
        ),
        title: Text(
          widget.fileName,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_fileUrl != null)
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _fileUrl!));
                _showMinimalToast("File link copied to clipboard");
              },
              icon: Icon(Icons.copy, color: context.textSecondary),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: context.textPrimary,
          strokeWidth: 2,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFF453A), size: 64),
            const SizedBox(height: 16),
            Text(
              "Failed to load file",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      color: context.appBackground,
      child: Column(
        children: [
          // Header with file info
          Container(
            padding: const EdgeInsets.all(16),
            color: context.cardBackground,
            child: Row(
              children: [
                Icon(
                  _getFileIcon(widget.fileName),
                  color: const Color(0xFF30D158),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.fileName,
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _isImageFile(widget.fileName)
                            ? 'Image preview'
                            : _isTextFile(widget.fileName)
                            ? 'Text preview'
                            : _isWebPreviewSupported(widget.fileName)
                            ? 'Document preview'
                            : 'Preview not available in app',
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isImageFile(widget.fileName) && _fileUrl != null)
            Expanded(
              child: Container(
                color: context.appBackground,
                child: InteractiveViewer(child: Image.network(_fileUrl!)),
              ),
            ),
          if (_isTextFile(widget.fileName))
            Expanded(
              child: Container(
                color: context.appBackground,
                padding: const EdgeInsets.all(16),
                child: _textLoadError
                    ? Center(
                        child: Text(
                          'Unable to load text preview.',
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: SelectableText(
                          _textPreview ?? 'Loading text preview...',
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textPrimary,
                            fontSize: 14,
                          ),
                        ),
                      ),
              ),
            ),
          if (_isWebPreviewSupported(widget.fileName) &&
              _webViewController != null)
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _webViewController!),
                  if (_isWebViewLoading)
                    Center(
                      child: CircularProgressIndicator(
                        color: context.textPrimary,
                        strokeWidth: 2,
                      ),
                    ),
                ],
              ),
            ),
          if (!_isImageFile(widget.fileName) &&
              !_isTextFile(widget.fileName) &&
              !_isWebPreviewSupported(widget.fileName))
            Expanded(
              child: Container(
                color: context.appBackground,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _getFileIcon(widget.fileName),
                        color: context.textSecondary,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'File cannot be previewed',
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.fileName,
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textSecondary,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () async {
                          if (_fileUrl != null) {
                            final uri = Uri.parse(_fileUrl!);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.open_in_browser),
                        label: Text(
                          'Open in Browser',
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.appBackground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.textPrimary,
                          foregroundColor: context.appBackground,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'mkv':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.audio_file;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
        return Icons.archive;
      default:
        return Icons.insert_drive_file;
    }
  }

  bool _isImageFile(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension);
  }

  bool _isTextFile(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    return ['txt', 'csv'].contains(extension);
  }

  bool _isWebPreviewSupported(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    return ['pdf', 'doc', 'docx', 'xls', 'xlsx'].contains(extension);
  }
}
