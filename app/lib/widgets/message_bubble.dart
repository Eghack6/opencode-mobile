import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app.dart';
import '../models/message.dart';
import '../models/part.dart';
import '../providers/chat_provider.dart';
import 'code_block.dart';
import 'reason_block.dart';
import 'toast.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool reasoningExpanded;
  final bool animate;
  final bool showTypingCursor;

  const MessageBubble({
    super.key,
    required this.message,
    this.reasoningExpanded = false,
    this.animate = false,
    this.showTypingCursor = false,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with TickerProviderStateMixin {
  // Entrance animation
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // Typewriter effect
  int _revealIndex = 0;
  Timer? _typewriterTimer;
  static const int _typewriterTotalLength = 800;

  // Cursor blink animation
  AnimationController? _cursorController;

  @override
  void initState() {
    super.initState();

    // Entrance animation
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    if (widget.animate) {
      _animController.forward();
    } else {
      _animController.value = 1;
    }

    // Typewriter + cursor for streaming messages
    if (widget.showTypingCursor) {
      _revealIndex = 0;
      _cursorController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      )..repeat(reverse: true);
      _typewriterTimer = Timer.periodic(
        const Duration(milliseconds: 8),
        (_) => _advanceTypewriter(),
      );
    } else {
      _revealIndex = widget.message.textContent.length;
    }
  }

  void _advanceTypewriter() {
    final textLen = widget.message.textContent.length;
    if (_revealIndex < textLen) {
      // Reveal 1 code unit per tick (handles multi-byte chars correctly)
      setState(() {
        _revealIndex++;
      });
    } else {
      // All text revealed, stop the timer (cursor keeps blinking)
      _typewriterTimer?.cancel();
      _typewriterTimer = null;
    }
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.showTypingCursor) {
      // Start cursor if not started
      _cursorController ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      )..repeat(reverse: true);

      // Start typewriter timer if more text arrived and timer not running
      if (_typewriterTimer == null && _revealIndex < widget.message.textContent.length) {
        _typewriterTimer = Timer.periodic(
          const Duration(milliseconds: 8),
          (_) => _advanceTypewriter(),
        );
      }
    } else {
      // Streaming ended: stop everything, show all text
      _typewriterTimer?.cancel();
      _typewriterTimer = null;
      _revealIndex = widget.message.textContent.length;
      _cursorController?.stop();
      _cursorController?.reset();
      _cursorController = null;
    }
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    _animController.dispose();
    _cursorController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUser = widget.message.isUser;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: GestureDetector(
          onLongPress: () => _showContextMenu(context, theme, isUser),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isUser ? 48 : 12,
              3,
              isUser ? 12 : 48,
              3,
            ),
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Glass bubble
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    // User: gradient fill; AI: frosted glass
                    gradient: isUser
                        ? GlassColors.primaryGradient
                        : null,
                    color: isUser
                        ? null
                        : (isDark
                            ? Colors.white.withOpacity(0.07)
                            : Colors.white.withOpacity(0.65)),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 6),
                      bottomRight: Radius.circular(isUser ? 6 : 20),
                    ),
                    border: Border.all(
                      color: isUser
                          ? Colors.white.withOpacity(0.2)
                          : (isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.white.withOpacity(0.6)),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isUser
                            ? GlassColors.primaryStart.withOpacity(0.25)
                            : (isDark
                                ? Colors.black.withOpacity(0.3)
                                : Colors.black.withOpacity(0.04)),
                        blurRadius: isUser ? 12 : 8,
                        offset: const Offset(0, 4),
                        spreadRadius: isUser ? -2 : 0,
                      ),
                      if (!isUser)
                        BoxShadow(
                          color: Colors.white.withOpacity(isDark ? 0.03 : 0.5),
                          blurRadius: 1,
                          offset: const Offset(0, -0.5),
                          spreadRadius: 0,
                        ),
                    ],
                  ),
                  // Frosted glass blur for AI messages
                  child: isUser
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ..._buildParts(context, theme, isUser),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: const Radius.circular(6),
                            bottomRight: const Radius.circular(20),
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: _cursorController != null
                                ? AnimatedBuilder(
                                    animation: _cursorController!,
                                    builder: (context, _) => Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: _buildParts(context, theme, isUser),
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ..._buildParts(context, theme, isUser),
                                    ],
                                  ),
                          ),
                        ),
                ),
                // Timestamp
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isUser) ...[
                        GestureDetector(
                          onTap: () => _showCopyToast(context),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.copy, size: 11,
                                color: theme.colorScheme.onSurface.withOpacity(0.2)),
                          ),
                        ),
                        Text(
                          _formatTime(widget.message.createdAt),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w300,
                            color: theme.colorScheme.onSurface.withOpacity(0.3),
                          ),
                        ),
                      ] else ...[
                        Text(
                          _formatTime(widget.message.createdAt),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w300,
                            color: theme.colorScheme.onSurface.withOpacity(0.3),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _showCopyToast(context),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.copy, size: 11,
                                color: theme.colorScheme.onSurface.withOpacity(0.2)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCopyToast(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.message.textContent));
    showToast(context, '已复制到剪贴板');
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(date.year, date.month, date.day);
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    if (msgDay == today) return timeStr;
    if (msgDay == today.subtract(const Duration(days: 1))) {
      return '昨天 $timeStr';
    }
    return '${date.month}/${date.day} $timeStr';
  }

  void _showContextMenu(BuildContext context, ThemeData theme, bool isUser) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制文本'),
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: widget.message.textContent));
                  Navigator.pop(ctx);
                  showToast(context, '已复制到剪贴板');
                },
              ),
              if (isUser)
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('重新发送'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.read<ChatProvider>().sendMessage(widget.message.textContent);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.select_all),
                title: const Text('复制全部'),
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: widget.message.fullContent));
                  Navigator.pop(ctx);
                  showToast(context, '已复制到剪贴板');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Inline blinking cursor as a WidgetSpan — follows text flow
  WidgetSpan _buildCursorSpan(Color textColor) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Opacity(
        opacity: _cursorController?.value ?? 0.0,
        child: Text(
          '|',
          style: TextStyle(
            fontSize: 14.5,
            height: 1.6,
            fontWeight: FontWeight.w300,
            color: textColor,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildParts(BuildContext context, ThemeData theme, bool isUser) {
    final widgets = <Widget>[];
    final textColor = isUser
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    // During typewriter: show truncated text + inline cursor
    if (widget.showTypingCursor && _cursorController != null) {
      final fullText = widget.message.textContent;
      final visibleText = fullText.substring(0, _revealIndex.clamp(0, fullText.length));
      if (visibleText.isNotEmpty) {
        // Parse inline markdown for the visible portion and append cursor
        widgets.add(_buildMarkdownTextWithCursor(visibleText, theme, textColor));
      }
      return widgets;
    }

    // Normal rendering (not streaming or streaming done)
    for (final part in widget.message.parts) {
      if (part.isReasoning) {
        widgets.add(ReasonBlock(
          content: part.content,
          defaultExpanded: widget.reasoningExpanded,
        ));
      } else if (part.isCode) {
        widgets.add(CodeBlock(code: part.content, language: part.language));
      } else if (part.isImage) {
        widgets.add(_buildImagePart(part));
      } else if (part.isToolCall) {
        // tool call is not useful to display
      } else if (part.isToolResult) {
        widgets.add(_buildToolResult(part, theme));
      } else {
        widgets.addAll(_buildTextWithCodeBlocks(part.content, theme, isUser, textColor));
      }
    }

    return widgets;
  }

  List<Widget> _buildTextWithCodeBlocks(String text, ThemeData theme, bool isUser, Color textColor) {
    final blocks = <Widget>[];
    final regex = RegExp(r'```(\w*)\n([\s\S]*?)```');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        final before = text.substring(lastEnd, match.start);
        if (before.trim().isNotEmpty) {
          blocks.add(_buildMarkdownText(before, theme, textColor));
        }
      }
      final lang = match.group(1) ?? '';
      final code = match.group(2) ?? '';
      blocks.add(
          CodeBlock(code: code, language: lang.isNotEmpty ? lang : null));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      final remaining = text.substring(lastEnd);
      if (remaining.trim().isNotEmpty) {
        blocks.add(_buildMarkdownText(remaining, theme, textColor));
      }
    }

    if (blocks.isEmpty && text.trim().isNotEmpty) {
      blocks.add(_buildMarkdownText(text, theme, textColor));
    }

    return blocks;
  }

  static final Map<String, Uint8List> _imageBytesCache = {};

  Widget _buildImagePart(Part part) {
    final url = part.imageUrl ?? '';
    if (url.isEmpty) return const SizedBox.shrink();
    Widget image;
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma < 0) return const SizedBox.shrink();
      final base64 = url.substring(comma + 1);
      final bytes = _imageBytesCache.putIfAbsent(url, () => base64Decode(base64));
      image = Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const Text('图片加载失败'),
      );
    } else {
      image = Image.network(
        url,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const Text('图片加载失败'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: RepaintBoundary(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: image,
          ),
        ),
      ),
    );
  }

  Widget _buildToolResult(Part part, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color:
            isDark ? Colors.grey.withOpacity(0.15) : Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? Colors.grey.withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Text(
        part.content,
        style: TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          color: theme.colorScheme.onSurface.withOpacity(0.7),
        ),
        maxLines: 8,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildMarkdownText(String text, ThemeData theme, Color textColor) {
    final lines = text.split('\n');
    final children = <InlineSpan>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.trim().isEmpty) {
        children.add(const WidgetSpan(child: SizedBox(height: 6)));
        continue;
      }

      // Table: collect consecutive lines starting with |
      if (line.trimLeft().startsWith('|')) {
        final tableLines = <String>[line.trimRight()];
        while (i + 1 < lines.length && lines[i + 1].trimLeft().startsWith('|')) {
          i++;
          tableLines.add(lines[i].trimRight());
        }
        if (tableLines.length >= 2) {
          children.add(WidgetSpan(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _buildTable(tableLines, theme, textColor),
            ),
          ));
          continue;
        }
      }

      // Horizontal rule: ---
      if (RegExp(r'^-{3,}\s*$').hasMatch(line.trim())) {
        children.add(WidgetSpan(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: textColor.withOpacity(0.25), height: 1),
          ),
        ));
        continue;
      }

      if (line.startsWith('### ')) {
        children.add(WidgetSpan(
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                line.substring(4),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ),
        ));
      } else if (line.startsWith('## ')) {
        children.add(WidgetSpan(
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Text(
                line.substring(3),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ),
        ));
      } else if (line.startsWith('# ')) {
        children.add(WidgetSpan(
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Text(
                line.substring(2),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ),
        ));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        children.add(WidgetSpan(
          child: Padding(
            padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('\u2022  ',
                    style: TextStyle(
                        fontSize: 14, color: textColor.withOpacity(0.7))),
                Expanded(
                  child: _parseInlineMarkdown(line.substring(2), theme, textColor),
                ),
              ],
            ),
          ),
        ));
      } else if (RegExp(r'^\d+[.)]\s').hasMatch(line)) {
        final numEnd = line.indexOf(RegExp(r'[.)]\s'));
        children.add(WidgetSpan(
          child: Padding(
            padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${line.substring(0, numEnd + 1)}  ',
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Expanded(
                  child:
                      _parseInlineMarkdown(line.substring(numEnd + 2), theme, textColor),
                ),
              ],
            ),
          ),
        ));
      } else if (line.startsWith('> ')) {
        if (children.isNotEmpty) {
          children.add(const WidgetSpan(child: SizedBox(height: 4)));
        }
        // Collect consecutive blockquote lines
        final quoteLines = <String>[line.substring(2)];
        while (i + 1 < lines.length && lines[i + 1].startsWith('> ')) {
          i++;
          quoteLines.add(lines[i].substring(2));
        }
        children.add(WidgetSpan(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: textColor.withOpacity(0.3),
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: quoteLines.map((l) => _parseInlineMarkdown(l, theme, textColor)).toList(),
            ),
          ),
        ));
      } else {
        if (i > 0 && children.isNotEmpty) {
          children.add(const WidgetSpan(child: SizedBox(height: 2)));
        }
        children.add(WidgetSpan(
          child: _parseInlineMarkdown(line, theme, textColor),
        ));
      }
    }

    return SelectableText.rich(
      TextSpan(children: children),
      style: TextStyle(
        fontSize: 14.5,
        height: 1.6,
        fontWeight: FontWeight.w300,
        letterSpacing: 0.1,
        color: textColor,
      ),
    );
  }

  /// Same as _buildMarkdownText but appends a blinking cursor at the end
  Widget _buildMarkdownTextWithCursor(String text, ThemeData theme, Color textColor) {
    final lines = text.split('\n');
    final children = <InlineSpan>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        children.add(const WidgetSpan(child: SizedBox(height: 6)));
        continue;
      }
      if (i > 0 && children.isNotEmpty) {
        children.add(const WidgetSpan(child: SizedBox(height: 2)));
      }
      children.add(WidgetSpan(
        child: _parseInlineMarkdown(line, theme, textColor),
      ));
    }

    // Append blinking cursor inline
    children.add(_buildCursorSpan(textColor));

    return SelectableText.rich(
      TextSpan(children: children),
      style: TextStyle(
        fontSize: 14.5,
        height: 1.6,
        fontWeight: FontWeight.w300,
        letterSpacing: 0.1,
        color: textColor,
      ),
    );
  }

  Widget _buildTable(List<String> rows, ThemeData theme, Color textColor) {
    // Parse header (row 0)
    final headers = rows[0].split('|').where((s) => s.isNotEmpty).toList();
    // Parse alignment from separator (row 1)
    final alignments = <TextAlign>[];
    if (rows.length > 1) {
      final parts = rows[1].split('|').where((s) => s.isNotEmpty).toList();
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.startsWith(':') && trimmed.endsWith(':')) {
          alignments.add(TextAlign.center);
        } else if (trimmed.startsWith(':')) {
          alignments.add(TextAlign.left);
        } else if (trimmed.endsWith(':')) {
          alignments.add(TextAlign.right);
        } else {
          alignments.add(TextAlign.left);
        }
      }
    }
    final colCount = headers.length;
    final borderColor = textColor.withOpacity(0.2);
    final headerBg = textColor.withOpacity(0.08);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(color: borderColor, width: 0.5),
        columnWidths: {
          for (int i = 0; i < colCount; i++)
            i: const IntrinsicColumnWidth(),
        },
        children: [
          // Header row
          TableRow(
            decoration: BoxDecoration(color: headerBg),
            children: headers.map((h) => _tableCell(h.trim(), true, theme, textColor)).toList(),
          ),
          // Body rows
          for (int r = 2; r < rows.length; r++)
            TableRow(
              children: rows[r]
                  .split('|')
                  .where((s) => s.isNotEmpty)
                  .toList()
                  .asMap()
                  .entries
                  .map((e) => _tableCell(
                        e.value.trim(),
                        false,
                        theme,
                        textColor,
                        align: e.key < alignments.length ? alignments[e.key] : TextAlign.left,
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _tableCell(String text, bool isHeader, ThemeData theme, Color textColor, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: DefaultTextStyle(
        style: TextStyle(
          fontSize: 13,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: textColor,
        ),
        child: _parseInlineMarkdown(text, theme, textColor, align: align),
      ),
    );
  }

  int _matchLen(String type, String content, String? url) {
    switch (type) {
      case 'bold': return content.length + 4;
      case 'italic': return content.length + 2;
      case 'code': return content.length + 2;
      case 'strike': return content.length + 4;
      case 'link': return content.length + (url?.length ?? 0) + 4;
      default: return content.length;
    }
  }

  Widget _parseInlineMarkdown(String text, ThemeData theme, Color textColor, {TextAlign? align}) {
    final spans = <InlineSpan>[];
    final isDark = theme.brightness == Brightness.dark;

    final bold = RegExp(r'\*\*(.+?)\*\*');
    final italic = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');
    final inlineCode = RegExp(r'`(.+?)`');
    final strike = RegExp(r'~~(.+?)~~');
    final link = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
    final bareUrl = RegExp(r'https?://[^\s<>\[\]\"\)]+');

    String remaining = text;
    while (remaining.isNotEmpty) {
      int earliest = remaining.length;
      String? matchType;
      String? matchContent;
      String? matchUrl;
      int? matchStart;
      int? matchLen;

      for (final entry in [
        {'pattern': bold, 'type': 'bold'},
        {'pattern': italic, 'type': 'italic'},
        {'pattern': inlineCode, 'type': 'code'},
        {'pattern': strike, 'type': 'strike'},
        {'pattern': link, 'type': 'link'},
        {'pattern': bareUrl, 'type': 'bareUrl'},
      ]) {
        final m = (entry['pattern'] as RegExp).firstMatch(remaining);
        if (m != null && m.start < earliest) {
          earliest = m.start;
          matchType = entry['type'] as String;
          matchContent = m.group(1);
          matchUrl = m.groupCount >= 2 ? m.group(2) : null;
          matchStart = m.start;
          matchLen = m.end - m.start;
        }
      }

      if (matchType == null || matchContent == null) {
        spans.add(TextSpan(text: remaining));
        break;
      }

      if (matchStart! > 0) {
        spans.add(TextSpan(text: remaining.substring(0, matchStart)));
      }

      int matchedLength;
      if (matchType == 'bareUrl') {
        matchedLength = matchLen!;
        matchUrl = matchContent; // For bare URLs, the URL is the matched text itself
      } else {
        matchedLength = _matchLen(matchType, matchContent, matchUrl);
      }
      final matched = remaining.substring(matchStart, matchStart + matchedLength);
      remaining = remaining.substring(matchStart + matched.length);

      switch (matchType) {
        case 'bold':
          spans.add(TextSpan(
            text: matchContent,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ));
          break;
        case 'italic':
          spans.add(TextSpan(
            text: matchContent,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ));
          break;
        case 'strike':
          spans.add(TextSpan(
            text: matchContent,
            style: const TextStyle(decoration: TextDecoration.lineThrough),
          ));
          break;
        case 'code':
          final codeBg = isDark ? Colors.white10 : Colors.black12;
          final codeTextColor = textColor.withOpacity(0.9);
          spans.add(WidgetSpan(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: codeBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: textColor.withOpacity(0.1),
                ),
              ),
              child: Text(
                matchContent,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: codeTextColor,
                ),
              ),
            ),
          ));
          break;
        case 'link':
          spans.add(WidgetSpan(
            child: GestureDetector(
              onTap: () async {
                final uri = Uri.tryParse(matchUrl ?? '');
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
              child: Text(
                matchContent,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary,
                ),
              ),
            ),
          ));
          break;
        case 'bareUrl':
          spans.add(WidgetSpan(
            child: GestureDetector(
              onTap: () async {
                final uri = Uri.tryParse(matchUrl ?? '');
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
              child: Text(
                matched,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary,
                ),
              ),
            ),
          ));
          break;
      }
    }

    return RichText(
      textAlign: align ?? TextAlign.start,
      text: TextSpan(
        children: spans,
        style: TextStyle(fontSize: 14.5, height: 1.6, fontWeight: FontWeight.w300, letterSpacing: 0.1, color: textColor),
      ),
    );
  }
}
