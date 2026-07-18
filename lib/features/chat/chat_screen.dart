import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/features/chat/widgets/screen_share_panel.dart';
import 'package:brutus_app/features/chat/widgets/vision_panel.dart';
import 'package:brutus_app/providers/chat_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  // 'Speak for me' — last chosen language persists during the session.
  String _speakLang = 'en-US';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // No auto-connect here — system power is controlled from the home orb.
    // sendText() will auto-power-on if the user types without powering up first.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Camera plugin requires us to release the controller when going to
    // background, otherwise Android will pull the surface from under us
    // and the next resume gets a black preview.
    final notifier = ref.read(chatProvider.notifier);
    final chatState = ref.read(chatProvider);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (chatState.visionMode != VisionMode.off) {
        notifier.stopVision();
      }
    }
    if (state == AppLifecycleState.resumed) {
      // Reconcile screen-share state with the native foreground service.
      // If the user backgrounded the app while sharing, the service kept
      // running; we just need to make the UI reflect that.
      notifier.reconcileScreenShare();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
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
    final chatState = ref.watch(chatProvider);

    ref.listen(chatProvider, (prev, next) {
      if ((prev?.messages.length ?? 0) != next.messages.length ||
          prev?.liveTranscript != next.liveTranscript) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceMuted,
              AppColors.background,
              AppColors.background,
            ],
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(chatState),
              if (chatState.errorMessage != null)
                _buildErrorBanner(chatState.errorMessage!),
              Expanded(child: _buildMessages(chatState)),
              const VisionPanel(),
              const ScreenSharePanel(),
              _buildInputBar(chatState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String error) {
    final chatState = ref.read(chatProvider);
    final needsMicSettings = chatState.needsPermissionSettings;
    final needsCamSettings = chatState.visionNeedsSettings;
    final needsSettings = needsMicSettings || needsCamSettings;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.errorLight,
      child: Row(
        children: [
          const Icon(Iconsax.warning_2, size: 14, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
          GestureDetector(
            onTap: () {
              final notifier = ref.read(chatProvider.notifier);
              if (needsCamSettings) {
                notifier.openVisionPermissionSettings();
              } else if (needsMicSettings) {
                notifier.openPermissionSettings();
              } else {
                notifier.powerOn();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                needsSettings ? 'Settings' : 'Retry',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _buildHeader(ChatState state) {
    final statusColor = state.isConnected
        ? AppColors.success
        : state.status == VoiceStatus.connecting
            ? AppColors.warning
            : AppColors.textTertiary;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Iconsax.message, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Brutus AI',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: state.isConnected
                            ? [
                                BoxShadow(
                                  color: statusColor.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _statusLabel(state),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: state.status == VoiceStatus.idle && !state.isConnected
                            ? AppColors.textTertiary
                            : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Power toggle — full system on/off
          _IconBtn(
            icon: Icons.power_settings_new,
            color: state.isConnected ? AppColors.success : AppColors.textTertiary,
            tooltip: state.isConnected ? 'Power off' : 'Power on',
            onTap: () {
              final notifier = ref.read(chatProvider.notifier);
              if (state.isConnected) {
                notifier.powerOff();
              } else {
                notifier.powerOn();
              }
            },
          ),
          if (state.messages.isNotEmpty)
            _IconBtn(
              icon: Iconsax.trash,
              color: AppColors.textTertiary,
              tooltip: 'Clear chat',
              onTap: () => _confirmClear(context),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildMessages(ChatState state) {
    final messages = state.messages;
    // Only show the in-chat live bubble for the AI's transcript. The user's
    // transcript is reflected in the input bar's hint text instead.
    final hasLive = state.liveTranscript.isNotEmpty &&
        state.liveOwner == LiveTranscriptOwner.ai;
    final isThinking = state.status == VoiceStatus.thinking && !hasLive && messages.isNotEmpty;
    final totalItems = messages.length + (hasLive ? 1 : 0) + (isThinking ? 1 : 0);

    if (totalItems == 0) {
      // LayoutBuilder + SingleChildScrollView so the empty-state column can
      // shrink/scroll when the keyboard pushes the available area down,
      // instead of overflowing by a few pixels.
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 76, height: 76,
                      decoration: BoxDecoration(gradient: AppColors.heroGradient, shape: BoxShape.circle),
                      child: const Icon(Iconsax.message, size: 30, color: Colors.white),
                    ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
                    const SizedBox(height: 14),
                    Text('Talk to Brutus', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      state.status == VoiceStatus.connecting
                          ? 'Connecting to Gemini...'
                          : state.isConnected
                              ? 'Type a message or hold the mic'
                              : 'Connecting...',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary),
                    ),
                    if (state.status == VoiceStatus.connecting)
                      const Padding(
                        padding: EdgeInsets.only(top: 14),
                        child: SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (index < messages.length) {
          return _buildBubble(messages[index])
              .animate(delay: Duration(milliseconds: 30 * (index > 5 ? 0 : index)))
              .fadeIn(duration: 250.ms)
              .slideY(begin: 0.04);
        }
        if (hasLive && index == messages.length) {
          return _buildLiveBubble(state.liveTranscript);
        }
        return _buildTypingIndicator(state.currentToolName);
      },
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final isUser = msg.role == MessageRole.user;
    final isTool = msg.role == MessageRole.tool;
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.78;

    if (isTool) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Text(
              msg.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            _BrutusAvatar(),
            const SizedBox(width: 10),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            child: GestureDetector(
              onLongPress: () => _copyMessage(msg.text),
              child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                gradient: isUser
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.primaryDark],
                      )
                    : null,
                color: isUser ? null : AppColors.surfaceVariant,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 20),
                ),
                border: isUser
                    ? null
                    : Border.all(
                        color: AppColors.border.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                boxShadow: isUser
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUser)
                    SelectableText(
                      msg.text,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    _BrutusMarkdown(text: msg.text),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(msg.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: isUser
                          ? Colors.white.withValues(alpha: 0.65)
                          : AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// Long-press any bubble → copy its text, with a haptic tick and a
  /// lightweight confirmation snackbar.
  void _copyMessage(String text) {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
  }

  Widget _buildLiveBubble(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _BrutusAvatar(),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(20),
                ),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(child: _BrutusMarkdown(text: text)),
                  const SizedBox(width: 8),
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .fade(duration: 600.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(String? toolName) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _BrutusAvatar(),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
                bottomLeft: Radius.circular(6),
              ),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
            child: toolName != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Iconsax.flash_1,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Using $toolName...',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      3,
                      (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.textTertiary.withValues(alpha: 0.45),
                        ),
                      )
                          .animate(
                              onPlay: (c) => c.repeat(reverse: true),
                              delay: Duration(milliseconds: i * 200))
                          .fade(duration: 600.ms, begin: 0.3, end: 1.0),
                    ),
                  ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _buildInputBar(ChatState state) {
    final systemOff = !state.isConnected;
    final muted = state.isMicMuted;
    // Mic is "live" only when system is on AND not muted AND we're in Live mode
    // (in REST mode the mic is purely cosmetic — text input is the path).
    final live = state.isConnected && !muted && state.isLiveMode;

    // Keyboard handling — when the soft keyboard is up, the outer
    // Scaffold's resizeToAvoidBottomInset pulls the body up over the
    // keyboard, and the bottom nav is hidden behind it. Drop the
    // nav-clearance entirely.
    //
    // When the keyboard is closed: AppShell uses `extendBody: true` so
    // the chat body draws UNDER the translucent NavigationBar. M3's
    // NavigationBar is 80dp tall, plus the device's gesture-area inset
    // (~24dp on Samsung One UI). We need at least that much bottom
    // padding or the action row (mic | camera | screen | speak) gets
    // buried behind the nav bar.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final bottomPadding =
        keyboardOpen ? 6.0 : 80.0 + MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(12, 6, 12, bottomPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.border.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1 — text field + send button (full-width composer)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _buildTextField(state, live, muted, systemOff)),
              const SizedBox(width: 8),
              _buildSendButton(),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2 — action toggles (mic, vision, screen-share, speak-for-me)
          _buildActionRow(state, live, muted, systemOff),
        ],
      ),
    );
  }

  /// The composer text field. Visually wraps to multi-line up to 5 rows
  /// before scrolling internally.
  Widget _buildTextField(
    ChatState state,
    bool live,
    bool muted,
    bool systemOff,
  ) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 140),
      decoration: BoxDecoration(
        color: live
            ? AppColors.primary.withValues(alpha: 0.05)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: live
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.border,
          width: 0.5,
        ),
      ),
      child: TextField(
        controller: _controller,
        maxLines: 5,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.newline,
        style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: live
              ? (state.liveOwner == LiveTranscriptOwner.user &&
                      state.liveTranscript.isNotEmpty
                  ? state.liveTranscript
                  : 'Listening — speak or type…')
              : muted
                  ? 'Mic muted — tap mic to unmute'
                  : systemOff
                      ? 'System off — tap mic to power on'
                      : 'Message Brutus…',
          hintStyle: TextStyle(
            color: live ? AppColors.primary : AppColors.textTertiary,
            fontStyle: live &&
                    (state.liveOwner != LiveTranscriptOwner.user ||
                        state.liveTranscript.isEmpty)
                ? FontStyle.italic
                : FontStyle.normal,
            fontSize: 14,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }

  /// Send button — gradient pill matching the hero gradient.
  Widget _buildSendButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _send,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.primaryGlow,
          ),
          child: const Icon(Iconsax.send_1, size: 20, color: Colors.white),
        ),
      ),
    );
  }

  /// Bottom action row — Mic | Vision | Screen-share | Speak-for-me.
  /// Spaced evenly, centred, all 44dp tap targets.
  Widget _buildActionRow(
    ChatState state,
    bool live,
    bool muted,
    bool systemOff,
  ) {
    final ringScale = 1.0 + (live ? state.audioLevel * 0.4 : 0.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Mic toggle — wrapped in a fixed 44dp slot so the ringScale
        // animation only affects the inner pill, not the row layout.
        SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  final notifier = ref.read(chatProvider.notifier);
                  if (systemOff) {
                    notifier.powerOn();
                  } else {
                    notifier.toggleMic();
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  transform: Matrix4.identity()
                    ..scaleByDouble(ringScale, ringScale, 1.0, 1.0),
                  transformAlignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: live
                        ? AppColors.primary
                        : muted
                            ? AppColors.error.withValues(alpha: 0.12)
                            : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: live
                          ? AppColors.primary
                          : muted
                              ? AppColors.error.withValues(alpha: 0.3)
                              : AppColors.border,
                      width: 0.5,
                    ),
                    boxShadow: live
                        ? [
                            BoxShadow(
                              color:
                                  AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 12 + state.audioLevel * 16,
                              spreadRadius: 0,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    systemOff || muted
                        ? Iconsax.microphone_slash_1
                        : Iconsax.microphone,
                    size: 20,
                    color: live
                        ? Colors.white
                        : muted
                            ? AppColors.error
                            : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
        _VisionToggle(state: state),
        _ScreenShareToggle(state: state),
        _SpeakButton(
          onTap: () => _showSpeakOptions(),
          lang: _speakLang,
        ),
      ],
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(chatProvider.notifier).sendText(text);
  }

  void _showSpeakOptions() {
    // Capture any text the user may already have typed in the main composer
    // as a starting point. The sheet has its own field — typing here doesn't
    // affect the chat composer above.
    final initialText = _controller.text.trim();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return _SpeakSheet(
          initialLang: _speakLang,
          initialText: initialText,
          onLangChanged: (lang) {
            // Persist the selection so the badge in the input bar updates
            // even if the user closes the sheet without sending.
            setState(() => _speakLang = lang);
          },
          onSpeak: (text, lang) {
            setState(() => _speakLang = lang);
            Navigator.pop(ctx);
            ref.read(chatProvider.notifier).speakText(text, lang: lang);
          },
        );
      },
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final notifier = ref.read(chatProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text(
          'This permanently removes the current chat history from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      notifier.clearHistory();
    }
  }

  String _statusLabel(ChatState state) {
    if (state.status == VoiceStatus.connecting) return 'Connecting...';
    if (state.isConnected) {
      switch (state.status) {
        case VoiceStatus.listening: return 'Listening...';
        case VoiceStatus.thinking: return 'Thinking...';
        case VoiceStatus.speaking: return 'Speaking...';
        default: return 'Connected';
      }
    }
    if (state.status == VoiceStatus.error) return 'Connection failed';
    return 'Offline';
  }

  String _formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Compact tooltip-aware icon button used in the chat header.
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// Camera toggle for the input bar. Three states:
///   • System off   → disabled grey camera-slash icon
///   • Vision off   → primary-tinted camera, tap to start
///   • Vision on    → filled primary, tap to stop
class _VisionToggle extends ConsumerWidget {
  final ChatState state;
  const _VisionToggle({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemOff = !state.isConnected;
    final visionOn = state.visionMode != VisionMode.off;
    final needsSettings = state.visionNeedsSettings;

    Color bg;
    Color fg;
    Border? border;
    IconData icon;
    if (systemOff) {
      bg = AppColors.surfaceVariant;
      fg = AppColors.textTertiary;
      border = Border.all(color: AppColors.border, width: 0.5);
      // iconsax_flutter 1.0.1 doesn't ship `video_slash` (only `video_slash_copy`).
      // `camera_slash` reads the same: a camera with a strikethrough.
      icon = Iconsax.camera_slash;
    } else if (visionOn) {
      bg = AppColors.primary;
      fg = Colors.white;
      border = null;
      icon = Iconsax.video;
    } else {
      bg = AppColors.primary.withValues(alpha: 0.1);
      fg = AppColors.primary;
      border = Border.all(
        color: AppColors.primary.withValues(alpha: 0.25),
        width: 0.5,
      );
      icon = Iconsax.video;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final notifier = ref.read(chatProvider.notifier);
          if (systemOff) {
            // Trying to enable vision while off — surface a hint
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Power on Brutus first, then enable vision.',
                  style: TextStyle(fontSize: 13),
                ),
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }
          if (needsSettings) {
            notifier.openVisionPermissionSettings();
            return;
          }
          if (visionOn) {
            await notifier.stopVision();
          } else {
            await _showVisionSheet(context, notifier, state.visionDataMode);
          }
        },
        onLongPress: visionOn
            ? () => ref.read(chatProvider.notifier).switchVisionLens()
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: border,
            boxShadow: visionOn
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Icon(icon, size: 20, color: fg),
        ),
      ),
    );
  }

  /// Quick lens picker before starting vision. Lets the user choose lens +
  /// data mode in one sheet so the bandwidth choice is in their hands before
  /// the camera ever opens.
  Future<void> _showVisionSheet(
    BuildContext context,
    ChatNotifier notifier,
    VisionDataMode initialMode,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        VisionDataMode pickedMode = initialMode;
        return StatefulBuilder(
          builder: (ctx, setSheetState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Iconsax.video, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Text(
                        'Show Brutus what you see',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pickedMode == VisionDataMode.standard
                        ? 'A 720p frame is sent to Gemini every 2 seconds. Stop anytime.'
                        : 'A 480p frame is sent every 4 seconds — friendlier on cellular.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ── Data mode chooser ──
                  Row(
                    children: [
                      Expanded(
                        child: _ModeChip(
                          label: 'Standard',
                          sub: '720p · 2s',
                          icon: Iconsax.wifi,
                          selected: pickedMode == VisionDataMode.standard,
                          onTap: () => setSheetState(
                            () => pickedMode = VisionDataMode.standard,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ModeChip(
                          label: 'Low data',
                          sub: '480p · 4s',
                          icon: Iconsax.simcard,
                          selected: pickedMode == VisionDataMode.low,
                          onTap: () => setSheetState(
                            () => pickedMode = VisionDataMode.low,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _LensCard(
                          icon: Iconsax.camera,
                          label: 'Back camera',
                          sub: 'See what you see',
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            notifier.startVision(
                              front: false,
                              mode: pickedMode,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _LensCard(
                          icon: Iconsax.camera,
                          label: 'Front camera',
                          sub: 'See you',
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            notifier.startVision(
                              front: true,
                              mode: pickedMode,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Screen-share toggle for the input bar. Mirrors [_VisionToggle]:
///   • System off    → disabled grey monitor icon
///   • Sharing off   → primary-tinted monitor, tap to start (consent dialog)
///   • Sharing on    → filled red, tap to stop
class _ScreenShareToggle extends ConsumerWidget {
  final ChatState state;
  const _ScreenShareToggle({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemOff = !state.isConnected;
    final on = state.screenShareOn;

    Color bg;
    Color fg;
    Border? border;
    final IconData icon = on ? Iconsax.monitor_recorder : Iconsax.monitor;
    if (systemOff) {
      bg = AppColors.surfaceVariant;
      fg = AppColors.textTertiary;
      border = Border.all(color: AppColors.border, width: 0.5);
    } else if (on) {
      bg = AppColors.error;
      fg = Colors.white;
      border = null;
    } else {
      bg = AppColors.primary.withValues(alpha: 0.1);
      fg = AppColors.primary;
      border = Border.all(
        color: AppColors.primary.withValues(alpha: 0.25),
        width: 0.5,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final notifier = ref.read(chatProvider.notifier);
          if (systemOff) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Power on Brutus first, then share your screen.',
                  style: TextStyle(fontSize: 13),
                ),
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }
          if (on) {
            await notifier.stopScreenShare();
            return;
          }
          // Pre-flight: stop vision if running. Both pipelines push frames
          // to Gemini and running both at once doubles bandwidth without
          // adding much value — vision wins, screen share takes over only
          // when explicitly toggled.
          if (state.visionMode != VisionMode.off) {
            await notifier.stopVision();
          }
          final r = await notifier.startScreenShare();
          if (!context.mounted) return;
          if (r == ScreenShareStartResult.denied) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Screen share consent denied.'),
                duration: Duration(seconds: 2),
              ),
            );
          } else if (r == ScreenShareStartResult.failed) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not start screen sharing.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: border,
            boxShadow: on
                ? [
                    BoxShadow(
                      color: AppColors.error.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Icon(icon, size: 20, color: fg),
        ),
      ),
    );
  }
}

/// Compact selectable chip used in the vision lens picker for the bandwidth
/// profile. Mirrors the styling of `_LensCard` but in a smaller footprint.
class _ModeChip extends StatelessWidget {
  final String label;
  final String sub;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({
    required this.label,
    required this.sub,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primarySurface
          : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.border,
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Iconsax.tick_circle,
                  size: 16,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LensCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _LensCard({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class _BrutusAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'B',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// Markdown renderer styled to match the chat theme. Used for Brutus's
/// (assistant) bubbles so things like **bold**, lists, and code render properly.
class _BrutusMarkdown extends StatelessWidget {
  final String text;
  const _BrutusMarkdown({required this.text});

  /// Cleans up artefacts that show up in streamed Gemini text:
  ///  • Lone `**` (orphaned bold start/end from chunked deltas)
  ///  • Stray `*` at the start of a line that isn't a list bullet
  ///  • Multiple consecutive blank lines
  ///  • Trailing whitespace on each line
  ///  • Markdown table separators when the table is incomplete
  ///  • Leading `#` without space (orphaned headings)
  static String _sanitize(String raw) {
    var s = raw;
    // Collapse `* ` indented bullets to a clean unicode bullet for prettier rendering
    // BUT keep markdown list syntax that flutter_markdown understands.
    // Strip dangling `**` pairs (odd count means streaming finished mid-bold).
    final boldOpen = '**'.allMatches(s).length;
    if (boldOpen.isOdd) {
      // remove the last unclosed **
      final i = s.lastIndexOf('**');
      if (i >= 0) s = s.replaceRange(i, i + 2, '');
    }
    // Same for single-asterisk italics (`*foo*`) — odd count means orphan
    final stars = RegExp(r'(?<!\*)\*(?!\*)').allMatches(s).length;
    if (stars.isOdd) {
      final m = RegExp(r'(?<!\*)\*(?!\*)').allMatches(s).toList();
      if (m.isNotEmpty) {
        final last = m.last;
        s = s.replaceRange(last.start, last.end, '');
      }
    }
    // Remove inline placeholder symbols Gemini sometimes spits when audio-mode
    // has trailing prosody markers (rare): `<...>`-style tags.
    s = s.replaceAll(RegExp(r'<[/a-zA-Z][^>]*>'), '');
    // Trim trailing whitespace on each line + collapse 3+ newlines to 2
    s = s.split('\n').map((l) => l.trimRight()).join('\n');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.trim();
  }

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: _sanitize(text),
      shrinkWrap: true,
      selectable: true,
      softLineBreak: true,
      onTapLink: (_, href, _) {
        // Future: open href via url_launcher
      },
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(
          fontSize: 15,
          height: 1.5,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w400,
        ),
        strong: const TextStyle(
          fontSize: 15,
          height: 1.5,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        em: const TextStyle(
          fontSize: 15,
          height: 1.5,
          color: AppColors.textPrimary,
          fontStyle: FontStyle.italic,
        ),
        listBullet: const TextStyle(
          fontSize: 15,
          height: 1.5,
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
        listIndent: 20,
        code: TextStyle(
          fontSize: 13,
          color: AppColors.primary,
          fontFamily: 'monospace',
          backgroundColor: AppColors.primarySurface.withValues(alpha: 0.6),
        ),
        codeblockDecoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.15),
          ),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquote: const TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: AppColors.primary, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        h1: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        h2: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        h3: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        a: const TextStyle(
          color: AppColors.primary,
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.w600,
        ),
        // Tighten paragraph spacing — feels more conversational
        pPadding: const EdgeInsets.only(bottom: 4),
        h1Padding: const EdgeInsets.only(top: 8, bottom: 4),
        h2Padding: const EdgeInsets.only(top: 8, bottom: 4),
        h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
        blockSpacing: 6,
      ),
    );
  }
}

// ── Speak-for-me button ───────────────────────────────────────────────────────

/// Compact button that opens the dedicated "Speak for me" composer sheet.
/// Uses a megaphone icon (clearly distinct from the AudioTrack-style speaker)
/// and shows the active language as a tiny EN/HI badge.
class _SpeakButton extends StatelessWidget {
  final VoidCallback onTap;
  final String lang;

  const _SpeakButton({required this.onTap, required this.lang});

  @override
  Widget build(BuildContext context) {
    final isHindi = lang == 'hi-IN';
    return Tooltip(
      message: 'Speak for me (${isHindi ? 'Hindi' : 'English'})',
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Megaphone icon — speaks "broadcast my words" rather than
                  // "audio playback". Visually distinct from the playback
                  // speaker icon used elsewhere.
                  const Icon(
                    Iconsax.send_2,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isHindi ? 'HI' : 'EN',
                        style: const TextStyle(
                          fontSize: 7,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Speak sheet ───────────────────────────────────────────────────────────────

/// Self-contained "Speak for me" composer. Has its own text field, language
/// picker, and send button. Independent of the main chat input — typing here
/// doesn't affect the chat composer above. Tapping send speaks the text aloud
/// in the chosen language and closes the sheet.
class _SpeakSheet extends StatefulWidget {
  final String initialLang;
  final String initialText;
  final void Function(String text, String lang) onSpeak;
  final ValueChanged<String> onLangChanged;

  const _SpeakSheet({
    required this.initialLang,
    required this.initialText,
    required this.onSpeak,
    required this.onLangChanged,
  });

  @override
  State<_SpeakSheet> createState() => _SpeakSheetState();
}

class _SpeakSheetState extends State<_SpeakSheet> {
  late String _selected;
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialLang;
    _controller = TextEditingController(text: widget.initialText);
    _hasText = _controller.text.trim().isNotEmpty;
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _focusNode = FocusNode();
    // Auto-focus the field after the sheet animates in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSpeak(text, _selected);
  }

  @override
  Widget build(BuildContext context) {
    // viewInsets pushes the sheet up over the keyboard. Without this the
    // text field gets hidden behind the IME on phones with software
    // keyboards.
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.5),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 32,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Iconsax.send_2,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Speak for me',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Type something — Brutus will read it aloud.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Text field
                Container(
                  constraints: const BoxConstraints(
                    minHeight: 96,
                    maxHeight: 200,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.6),
                      width: 0.5,
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 6,
                    minLines: 3,
                    autofocus: false,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: _selected == 'hi-IN'
                          ? 'जो बोलना है, यहाँ टाइप करो…'
                          : 'Type what Brutus should say…',
                      hintStyle: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Language label
                const Text(
                  'Voice language',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),

                // Language chips
                Row(
                  children: [
                    _LangChip(
                      label: '🇬🇧  English',
                      selected: _selected == 'en-US',
                      onTap: () {
                        setState(() => _selected = 'en-US');
                        widget.onLangChanged('en-US');
                      },
                    ),
                    const SizedBox(width: 10),
                    _LangChip(
                      label: '🇮🇳  Hindi',
                      selected: _selected == 'hi-IN',
                      onTap: () {
                        setState(() => _selected = 'hi-IN');
                        widget.onLangChanged('hi-IN');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Send / speak button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _hasText ? _send : null,
                    icon: const Icon(Iconsax.send_1, size: 18),
                    label: Text(
                      _hasText
                          ? (_selected == 'hi-IN'
                              ? 'सुनाओ — Speak'
                              : 'Send — Speak')
                          : 'Type something first',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.border,
                      disabledForegroundColor: AppColors.textTertiary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LangChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.border.withValues(alpha: 0.6),
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
