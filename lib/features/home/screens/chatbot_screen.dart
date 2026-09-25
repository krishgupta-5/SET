import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startup_expense_tracker/theme/app_theme.dart';
import 'package:startup_expense_tracker/services/chat_service.dart';
import 'package:startup_expense_tracker/services/ai_context_manager.dart';

import 'package:flutter_markdown/flutter_markdown.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  bool _isTyping = false;

  // Static so chat persists across navigation, but resets on app restart
  static final List<Map<String, dynamic>> _chatMessages = [];

  @override
  void initState() {
    super.initState();
    if (_chatMessages.isEmpty) {
      _chatMessages.add({
        'role': 'ai',
        'text': 'Hello! I am your AI Startup CFO. Ask me anything about your runway, burn rate, expenses, or team efficiency.',
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage({String? retryText}) async {
    final text = retryText ?? _messageController.text.trim();
    if (text.isEmpty) return;

    if (retryText == null) {
      _messageController.clear();
    }
    
    // Remove previous error message if retrying
    if (retryText != null && _chatMessages.isNotEmpty && _chatMessages.last['role'] == 'error') {
      setState(() {
        _chatMessages.removeLast();
      });
    } else if (retryText == null) {
      setState(() {
        _chatMessages.add({'role': 'user', 'text': text});
      });
    }

    setState(() {
      _isTyping = true;
    });

    _scrollToBottom();

    try {
      // Pass history (excluding errors AND excluding the newly added current user message)
      final history = _chatMessages
          .where((m) => m['role'] != 'error')
          .toList();
      if (history.isNotEmpty && history.last['role'] == 'user') {
        history.removeLast(); // The backend appends the current question manually
      }
          
      setState(() {
        _chatMessages.add({'role': 'ai', 'text': ''});
      });

      final stream = ChatService.streamMessage(text, history);
      
      await for (final chunk in stream) {
        if (!mounted) return;
        setState(() {
          _chatMessages.last['text'] = (_chatMessages.last['text'] as String) + chunk;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chatMessages.add({
          'role': 'error', 
          'text': 'Oops! Something went wrong. \n\n${e.toString()}',
          'originalText': text, // Store to allow retry
        });
      });
    } finally {
      if (mounted) {
        setState(() {
          _isTyping = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.isDarkMode
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: context.appBackground,
        appBar: AppBar(
          backgroundColor: context.appBackground,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: context.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A84FF).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFF0A84FF),
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "AI CFO",
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh, color: context.textSecondary),
              tooltip: "Clear Context Cache",
              onPressed: () async {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Clearing cache...')),
                );
                await AiContextManager().invalidate();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cache cleared.')),
                  );
                }
              },
            )
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(24),
                  itemCount: _chatMessages.length,
                  itemBuilder: (context, index) {
                    final msg = _chatMessages[index];
                    final isUser = msg['role'] == 'user';
                    final isError = msg['role'] == 'error';

                    if (!isUser && !isError && (msg['text'] == null || (msg['text'] as String).isEmpty)) {
                      return const SizedBox.shrink();
                    }

                    return Align(
                      alignment:
                          isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isUser
                                  ? const Color(0xFF0A84FF)
                                  : isError
                                  ? const Color(0xFFFF453A).withValues(alpha: 0.1)
                                  : context.cardBackground,
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomRight:
                                isUser
                                    ? const Radius.circular(4)
                                    : const Radius.circular(16),
                            bottomLeft:
                                !isUser
                                    ? const Radius.circular(4)
                                    : const Radius.circular(16),
                          ),
                          border:
                              isUser
                                  ? null
                                  : Border.all(
                                    color:
                                        isError
                                            ? const Color(0xFFFF453A).withValues(alpha: 0.3)
                                            : context.borderColor,
                                  ),
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.85,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isUser || isError)
                              Text(
                                msg['text'] ?? "",
                                style: GoogleFonts.inter(
                                  color:
                                      isUser
                                          ? Colors.white
                                          : const Color(0xFFFF453A),
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              )
                            else
                              MarkdownBody(
                                data: msg['text'] ?? "",
                                selectable: true,
                                styleSheet: MarkdownStyleSheet(
                                  p: GoogleFonts.inter(
                                    color: context.textPrimary,
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                  strong: GoogleFonts.inter(
                                    color: context.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  listBullet: GoogleFonts.inter(
                                    color: context.textPrimary,
                                  ),
                                ),
                              ),
                            if (isError && msg['originalText'] != null) ...[
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () {
                                  if (!_isTyping) {
                                    _sendMessage(retryText: msg['originalText']);
                                  }
                                },
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Retry'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF453A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              )
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_isTyping && (_chatMessages.isEmpty || _chatMessages.last['role'] != 'ai' || (_chatMessages.last['text'] as String).isEmpty))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: context.cardBackground,
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomLeft: const Radius.circular(4),
                          ),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0A84FF),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Thinking...",
                              style: GoogleFonts.inter(
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
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: context.appBackground,
                  border: Border(top: BorderSide(color: context.borderColor)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.cardBackground,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: TextField(
                          controller: _messageController,
                          enabled: !_isTyping,
                          style: GoogleFonts.inter(
                            color: context.textPrimary,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: "Ask about your startup's finances...",
                            hintStyle: GoogleFonts.inter(
                              color: context.textSecondary,
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                          ),
                          onSubmitted: (_) {
                            if (!_isTyping) _sendMessage();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        if (!_isTyping) _sendMessage();
                      },
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _isTyping ? context.textSecondary : const Color(0xFF0A84FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
