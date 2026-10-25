import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../services/telegram_service.dart';

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

  Uint8List? _bytes;

  /// Loads the file through the authenticated backend proxy; the bot token
  /// never reaches the app, and only the owner can fetch the file.
  Future<void> _loadFileUrl() async {
    try {
      final bytes = await TelegramService.downloadBytes(widget.fileId);
      if (_isTextFile(widget.fileName)) {
        try {
          _textPreview = utf8.decode(bytes, allowMalformed: true);
        } catch (_) {
          _textLoadError = true;
        }
      }
      // Documents (PDF/Office) can't be previewed in-app without exposing a
      // public URL; offer "open externally" via a temp file instead.
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _fileUrl = TelegramService.imageUrl(widget.fileId);
        _isLoading = false;
        _isWebViewLoading = false;
      });
    } catch (e) {
      debugPrint('File load failed: $e');
      if (!mounted) return;
      setState(() {
        _error = "This file couldn't be loaded. It may have expired.";
        _isLoading = false;
      });
    }
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
            fontFamily: 'Geist',
            color: context.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [

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
            Icon(Icons.error_outline, color: context.rx.negative, size: 64),
            const SizedBox(height: 16),
            Text(
              "Failed to load file",
              style: TextStyle(
                fontFamily: 'Geist',
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                fontFamily: 'Geist',
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
                  color: context.rx.positive,
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
                          fontFamily: 'Geist',
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
                          fontFamily: 'Geist',
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
          if (_isImageFile(widget.fileName) && _bytes != null)
            Expanded(
              child: Container(
                color: context.appBackground,
                child: InteractiveViewer(child: Image.memory(_bytes!)),
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
                            fontFamily: 'Geist',
                            color: context.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: SelectableText(
                          _textPreview ?? 'Loading text preview...',
                          style: TextStyle(
                            fontFamily: 'Geist',
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
                          fontFamily: 'Geist',
                          color: context.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.fileName,
                        style: TextStyle(
                          fontFamily: 'Geist',
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
                            fontFamily: 'Geist',
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
