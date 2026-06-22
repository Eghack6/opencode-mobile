import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../models/part.dart';
import '../providers/chat_provider.dart';
import 'code_block.dart';
import 'reason_block.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool reasoningExpanded;
  final bool animate;

  const MessageBubble({
    super.key,
    required this.message,
    this.reasoningExpanded = false,
    this.animate = false,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              2,
              isUser ? 12 : 48,
              2,
            ),
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isUser
                            ? theme.colorScheme.primary.withOpacity(0.15)
                            : theme.colorScheme.shadow.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildParts(context, theme, isUser),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Text(
                    _formatTime(widget.message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制到剪贴板'),
                      duration: Duration(seconds: 1),
                    ),
                  );
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制到剪贴板'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildParts(BuildContext context, ThemeData theme, bool isUser) {
    final widgets = <Widget>[];
    final textColor = isUser
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    for (final part in widget.message.parts) {
      if (part.isReasoning) {
        widgets.add(ReasonBlock(
          content: part.content,
          defaultExpanded: widget.reasoningExpanded,
        ));
      } else if (part.isCode) {
        widgets.add(CodeBlock(code: part.content, language: part.language));
      } else if (part.isToolCall) {
        widgets.add(_buildToolCall(part, theme, isUser));
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

  Widget _buildToolCall(Part part, ThemeData theme, bool isUser) {
    final color = isUser ? Colors.white.withOpacity(0.9) : theme.colorScheme.tertiary;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isUser
            ? Colors.white.withOpacity(0.15)
            : theme.colorScheme.tertiaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.build, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              part.content,
              style: TextStyle(fontSize: 12, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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

      if (line.startsWith('### ')) {
        children.add(WidgetSpan(
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
        ));
      } else if (line.startsWith('## ')) {
        children.add(WidgetSpan(
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
        ));
      } else if (line.startsWith('# ')) {
        children.add(WidgetSpan(
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
            child: _parseInlineMarkdown(line.substring(2), theme, textColor),
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
        fontSize: 14,
        height: 1.45,
        color: textColor,
      ),
    );
  }

  Widget _parseInlineMarkdown(String text, ThemeData theme, Color textColor) {
    final spans = <InlineSpan>[];
    final isDark = theme.brightness == Brightness.dark;

    final bold = RegExp(r'\*\*(.+?)\*\*');
    final italic = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');
    final inlineCode = RegExp(r'`(.+?)`');

    String remaining = text;
    while (remaining.isNotEmpty) {
      int earliest = remaining.length;
      String? matchType;
      String? matchContent;
      int? matchStart;

      for (final entry in [
        {'pattern': bold, 'type': 'bold'},
        {'pattern': italic, 'type': 'italic'},
        {'pattern': inlineCode, 'type': 'code'},
      ]) {
        final m = (entry['pattern'] as RegExp).firstMatch(remaining);
        if (m != null && m.start < earliest) {
          earliest = m.start;
          matchType = entry['type'] as String;
          matchContent = m.group(1);
          matchStart = m.start;
        }
      }

      if (matchType == null || matchContent == null) {
        spans.add(TextSpan(text: remaining));
        break;
      }

      if (matchStart! > 0) {
        spans.add(TextSpan(text: remaining.substring(0, matchStart)));
      }

      final matchedLen = matchType == 'bold'
          ? matchContent.length + 4
          : matchType == 'italic'
              ? matchContent.length + 2
              : matchContent.length + 2;
      final matched =
          remaining.substring(matchStart, matchStart + matchedLen);
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
      }
    }

    return RichText(
      text: TextSpan(
        children: spans,
        style: TextStyle(fontSize: 14, height: 1.45, color: textColor),
      ),
    );
  }
}
