import 'package:flutter/material.dart';
import '../../ai/widgets/ai_widgets.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:startup_expense_tracker/widgets/rx_ui.dart';
import 'package:startup_expense_tracker/services/chat_service.dart';
import 'package:startup_expense_tracker/services/ai_context_manager.dart';
import 'package:startup_expense_tracker/services/ai_cache_service.dart';

import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isTyping = false;
  bool _isLoadingHistory = true;

  List<Map<String, dynamic>> _chatMessages = [];
  late SharedPreferences _prefs;
  // Scoped per user so a shared device never shows another account's chat.
  final String _chatHistoryKey = AiCacheService.chatHistoryKey();

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    _prefs = await SharedPreferences.getInstance();
    // Drop the pre-fix shared key so one account's chat never shows in another.
    await _prefs.remove(AiCacheService.legacyChatHistoryKey);
    final String? storedHistory = _prefs.getString(_chatHistoryKey);

    List<Map<String, dynamic>>? restored;
    if (storedHistory != null) {
      try {
        restored = (jsonDecode(storedHistory) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((m) => (m['text'] ?? '').toString().trim().isNotEmpty)
            .toList();
      } catch (_) {
        restored = null; // corrupted history → start fresh
      }
    }
    if (!mounted) return;

    if (restored != null && restored.isNotEmpty) {
      setState(() {
        _chatMessages = restored!;
        _isLoadingHistory = false;
      });
    } else {
      setState(() {
        _chatMessages.add({
          'role': 'ai',
          'text':
              'Hello! 👋 I am your AI Startup CFO. Ask me anything about your **runway**, **burn rate**, **expenses**, **team efficiency**, or **financial forecasts**. I have full context of your startup\'s data and I\'m ready to help!',
        });
        _isLoadingHistory = false;
      });
      _saveChatHistory();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _saveChatHistory() async {
    // Filter out error messages and cap history at 50 messages
    List<Map<String, dynamic>> messagesToSave = _chatMessages
        .where((m) => m['role'] != 'error')
        .toList();
    if (messagesToSave.length > 50) {
      messagesToSave = messagesToSave.sublist(messagesToSave.length - 50);
    }
    await _prefs.setString(_chatHistoryKey, jsonEncode(messagesToSave));
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
    if (retryText != null &&
        _chatMessages.isNotEmpty &&
        _chatMessages.last['role'] == 'error') {
      setState(() {
        _chatMessages.removeLast();
      });
    } else if (retryText == null) {
      setState(() {
        _chatMessages.add({'role': 'user', 'text': text});
      });
      _saveChatHistory();
    }

    setState(() {
      _isTyping = true;
    });

    _scrollToBottom();

    try {
      // Pass history (excluding errors AND excluding the newly added current user message)
      final history = _chatMessages.where((m) => m['role'] != 'error').toList();
      if (history.isNotEmpty && history.last['role'] == 'user') {
        history
            .removeLast(); // The backend appends the current question manually
      }

      setState(() {
        _chatMessages.add({'role': 'ai', 'text': ''});
      });

      final stream = ChatService.streamMessage(text, history);

      await for (final chunk in stream) {
        if (!mounted) return;
        setState(() {
          _chatMessages.last['text'] =
              (_chatMessages.last['text'] as String) + chunk;
        });
        _scrollToBottom();
      }
      if ((_chatMessages.last['text'] as String).trim().isEmpty) {
        throw const ChatException("The AI didn't return an answer. Please try again.");
      }
      _saveChatHistory();
    } catch (e) {
      if (!mounted) return;
      debugPrint('Chat error: $e');
      setState(() {
        // Drop the partial/empty AI bubble so a cut-off answer isn't saved
        // to history or sent back to the model as context.
        if (_chatMessages.isNotEmpty && _chatMessages.last['role'] == 'ai') {
          _chatMessages.removeLast();
        }
        _chatMessages.add({
          'role': 'error',
          'text': e is ChatException
              ? e.message
              : 'Something went wrong. Please try again.',
          'originalText': text, // Store to allow retry
        });
      });
      _saveChatHistory();
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
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- UI (presentation only) ---

  static const String _welcome =
      'Hello! 👋 I am your AI Startup CFO. Ask me anything about your **runway**, **burn rate**, **expenses**, **team efficiency**, or **financial forecasts**. I have full context of your startup\'s data and I\'m ready to help!';

  Future<void> _clearChat() async {
    setState(() {
      _chatMessages = [
        {'role': 'ai', 'text': _welcome},
      ];
    });
    await _saveChatHistory();
    await AiContextManager().invalidate();
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      _toast('Chat and context cleared');
    }
  }

  Future<void> _clearCache() async {
    ScaffoldMessenger.of(context).clearSnackBars();
    _toast('Clearing cache…');
    await AiContextManager().invalidate();
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      _toast('Cache cleared');
    }
  }

  void _toast(String text) {
    final rx = context.rx;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: RxText.body(context, color: rx.onInverse)),
        backgroundColor: rx.inverse,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final showThinking =
        _isTyping &&
        (_chatMessages.isEmpty ||
            _chatMessages.last['role'] != 'ai' ||
            (_chatMessages.last['text'] as String).isEmpty);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.rxOverlayStyle,
      child: Scaffold(
        backgroundColor: rx.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: _isLoadingHistory
                    ? const Center(child: AiBot(size: 100))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount:
                            _chatMessages.length + (showThinking ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _chatMessages.length) {
                            return _buildThinking();
                          }
                          return _buildMessage(_chatMessages[index]);
                        },
                      ),
              ),
              _buildComposer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final rx = context.rx;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 8, 8),
      child: Row(
        children: [
          RxCircleButton(
            icon: HugeIcons.strokeRoundedArrowLeft01,
            semanticLabel: 'Back',
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 6),
          const AiBotAvatar(size: 40, animate: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI CFO',
                  style: RxText.title(context).copyWith(fontSize: 20),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _isTyping
                        ? 'Thinking…'
                        : 'Online · reads your live numbers',
                    key: ValueKey(_isTyping),
                    style: RxText.caption(
                      context,
                      color: _isTyping ? null : rx.positive,
                    ),
                  ),
                ),
              ],
            ),
          ),
          RxCircleButton(
            icon: HugeIcons.strokeRoundedRefresh,
            semanticLabel: 'Clear context cache',
            onTap: _clearCache,
          ),
          RxCircleButton(
            icon: HugeIcons.strokeRoundedDelete02,
            semanticLabel: 'Clear chat',
            onTap: _clearChat,
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = msg['role'] == 'user';
    final isError = msg['role'] == 'error';
    final text = (msg['text'] as String?) ?? '';

    // Streaming placeholder: hidden until the first chunk arrives.
    if (!isUser && !isError && text.isEmpty) return const SizedBox.shrink();

    const r = Radius.circular(20);
    const tail = Radius.circular(6);
    final radius = BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: isUser ? r : tail,
      bottomRight: isUser ? tail : r,
    );

    final bodyStyle = RxText.body(
      context,
    ).copyWith(fontWeight: FontWeight.w400, height: 1.45);

    Widget content;
    if (isUser) {
      content = Text(text, style: bodyStyle.copyWith(color: rx.onInverse));
    } else if (isError) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: bodyStyle.copyWith(color: rx.negative)),
          if (msg['originalText'] != null) ...[
            const SizedBox(height: 10),
            RxPressable(
              onTap: () {
                if (!_isTyping) {
                  _sendMessage(retryText: msg['originalText']);
                }
              },
              semanticLabel: 'Retry',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: rx.negative,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedRefresh,
                      color: Colors.white,
                      size: 14,
                      strokeWidth: 2,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Retry',
                      style: RxText.caption(
                        context,
                        color: Colors.white,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    } else {
      content = MarkdownBody(
        data: text,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: bodyStyle,
          strong: bodyStyle.copyWith(fontWeight: FontWeight.w600),
          em: bodyStyle.copyWith(fontStyle: FontStyle.italic),
          listBullet: bodyStyle,
          h1: RxText.heading(context).copyWith(fontSize: 18),
          h2: RxText.heading(context).copyWith(fontSize: 16),
          h3: RxText.heading(context),
          code: RxText.caption(
            context,
            color: rx.textPrimary,
          ).copyWith(backgroundColor: rx.surfaceMuted),
          blockSpacing: 10,
        ),
      );
    }

    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * (isUser ? 0.78 : 0.76),
      ),
      decoration: BoxDecoration(
        color: isUser
            ? rx.inverse
            : isError
            ? rx.negativeSoft
            : rx.surface,
        borderRadius: radius,
        border: Border.all(
          color: !isUser && !isError && isDark
              ? rx.hairline
              : Colors.transparent,
        ),
        boxShadow: !isUser && !isError ? rx.cardShadow : null,
      ),
      child: content,
    );

    if (isUser) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    }
    // AI side: the robot sits beside its reply, like a chat profile.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, right: 8),
          child: AiBotAvatar(size: 28),
        ),
        Flexible(child: bubble),
      ],
    );
  }

  Widget _buildThinking() {
    final rx = context.rx;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12, right: 8),
          child: AiBotAvatar(size: 28, thinking: true),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: rx.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
              bottomLeft: Radius.circular(6),
            ),
            boxShadow: rx.cardShadow,
          ),
          child: const AiTypingDots(),
        ),
      ],
    );
  }

  Widget _buildComposer() {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 5, 5, 5),
        decoration: BoxDecoration(
          color: rx.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: isDark ? rx.hairline : Colors.transparent),
          boxShadow: rx.cardShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                enabled: !_isTyping,
                maxLength: 500,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                cursorColor: rx.textPrimary,
                style: RxText.body(
                  context,
                ).copyWith(fontWeight: FontWeight.w400),
                decoration: InputDecoration(
                  counterText: "",
                  isDense: true,
                  hintText: 'Ask about your numbers…',
                  hintStyle: RxText.body(
                    context,
                    color: rx.textTertiary,
                  ).copyWith(fontWeight: FontWeight.w400),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: (_) {
                  if (!_isTyping) _sendMessage();
                },
              ),
            ),
            const SizedBox(width: 8),
            RxPressable(
              onTap: _isTyping
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      _sendMessage();
                    },
              semanticLabel: 'Send',
              haptic: false,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _isTyping ? rx.surfaceMuted : rx.inverse,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowUp02,
                  color: _isTyping ? rx.textTertiary : rx.onInverse,
                  size: 18,
                  strokeWidth: 2.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
