import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TelegramImagePicker extends StatefulWidget {
  final String? existingFileId;
  final String? initialImagePath;
  final Function(String fileId) onUploaded;
  final Function() onRemoved;

  const TelegramImagePicker({
    super.key,
    this.existingFileId,
    this.initialImagePath,
    required this.onUploaded,
    required this.onRemoved,
  });

  @override
  State<TelegramImagePicker> createState() => _TelegramImagePickerState();
}

class _TelegramImagePickerState extends State<TelegramImagePicker> {
  bool _isUploading = false;
  String? _fileId;
  String? _fileName;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fileId = widget.existingFileId;

    // ✅ Auto-upload image if initialImagePath is provided
    if (widget.initialImagePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _uploadImageFromPath(widget.initialImagePath!);
      });
    }
  }

  Future<String?> uploadToTelegram(String filePath) async {
    try {
      await dotenv.load(fileName: ".env.local");
      final botToken = dotenv.env['TELEGRAM_BOT_TOKEN'];

      if (botToken == null) {
        throw Exception('Telegram bot token not found in environment');
      }

      final uri = Uri.parse("https://api.telegram.org/bot$botToken/sendPhoto");

      var request = http.MultipartRequest('POST', uri);
      request.fields['chat_id'] = '-1003885930746';

      request.files.add(await http.MultipartFile.fromPath('photo', filePath));

      final response = await request.send();

      if (response.statusCode == 200) {
        final res = await http.Response.fromStream(response);
        final data = jsonDecode(res.body);

        // 🔥 IMPORTANT: take highest quality image
        return data['result']['photo'].last['file_id'];
      } else {
        throw Exception("Upload failed: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint('Error uploading to Telegram: $e');
      return null;
    }
  }

  Future<String> getTelegramImageUrl(String fileId) async {
    try {
      await dotenv.load(fileName: ".env.local");
      final botToken = dotenv.env['TELEGRAM_BOT_TOKEN'];

      if (botToken == null) {
        throw Exception('Telegram bot token not found in environment');
      }

      final res = await http.get(
        Uri.parse(
          "https://api.telegram.org/bot$botToken/getFile?file_id=$fileId",
        ),
      );

      final data = jsonDecode(res.body);
      final path = data['result']['file_path'];

      return "https://api.telegram.org/file/bot$botToken/$path";
    } catch (e) {
      debugPrint('Error getting Telegram image URL: $e');
      rethrow;
    }
  }

  // ✅ Upload image from file path (for auto-upload from scan)
  Future<void> _uploadImageFromPath(String filePath) async {
    try {
      setState(() {
        _isUploading = true;
        _fileName = filePath.split('/').last;
      });

      final fileId = await uploadToTelegram(filePath);

      if (fileId == null) {
        throw Exception('Failed to upload image to Telegram');
      }

      setState(() {
        _isUploading = false;
        _fileId = fileId;
      });

      widget.onUploaded(fileId);
    } catch (e) {
      debugPrint('Error auto-uploading to Telegram: $e');
      setState(() {
        _isUploading = false;
        _fileName = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to upload receipt: $e',
              style: TextStyle(fontFamily: 'Satoshi', color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (image == null) return;

      setState(() {
        _isUploading = true;
        _fileName = image.name;
      });

      // Upload to Telegram
      final fileId = await uploadToTelegram(image.path);

      if (fileId == null) {
        throw Exception('Failed to upload image to Telegram');
      }

      setState(() {
        _isUploading = false;
        _fileId = fileId;
      });

      widget.onUploaded(fileId);
    } catch (e) {
      debugPrint('Error uploading to Telegram: $e');
      setState(() {
        _isUploading = false;
        _fileName = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to upload receipt: $e',
              style: TextStyle(fontFamily: 'Satoshi', color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _removeAttachment() {
    setState(() {
      _fileId = null;
      _fileName = null;
    });
    widget.onRemoved();
  }

  @override
  Widget build(BuildContext context) {
    if (_fileId != null) {
      // Show uploaded file preview
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF30D158).withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF30D158).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Color(0xFF30D158),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Receipt uploaded to Telegram",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: const Color(0xFF30D158),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _fileName ?? "receipt.jpg",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _removeAttachment,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Show image preview
            FutureBuilder<String>(
              future: getTelegramImageUrl(_fileId!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF30D158),
                      strokeWidth: 2,
                    ),
                  );
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return Container(
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        "Failed to load image",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }

                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    snapshot.data!,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            "Failed to load image",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    // Show upload zone
    return GestureDetector(
      onTap: _isUploading ? null : _pickAndUploadImage,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: const Color(0xFF141416).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isUploading
                ? const Color(0xFF0A84FF).withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: _isUploading
            ? Column(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: const Color(0xFF0A84FF),
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Uploading to Telegram...",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: const Color(0xFF0A84FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    color: Colors.white38,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Tap to upload receipt",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Stored securely in Telegram",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: Colors.white24,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
