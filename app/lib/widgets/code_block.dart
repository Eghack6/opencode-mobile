import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart';
import 'package:highlight/languages/all.dart';
import 'toast.dart';

class CodeBlock extends StatefulWidget {
  final String code;
  final String? language;

  const CodeBlock({super.key, required this.code, this.language});

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;

  static final _highlighter = Highlight();

  List<TextSpan> _highlightCode(String code, String? lang, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final defaultColor =
        isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1E1E1E);

    if (lang == null || !allLanguages.containsKey(lang)) {
      return [
        TextSpan(
            text: code,
            style: TextStyle(
                color: defaultColor,
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4))
      ];
    }

    final result = _highlighter.parse(code, language: lang);
    if (result.nodes == null || result.nodes!.isEmpty) {
      return [
        TextSpan(
            text: code,
            style: TextStyle(
                color: defaultColor,
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4))
      ];
    }

    return _convertNodes(result.nodes!, isDark);
  }

  List<TextSpan> _convertNodes(List<Node> nodes, bool isDark) {
    final spans = <TextSpan>[];
    for (final node in nodes) {
      if (node.value != null) {
        spans.add(TextSpan(
          text: node.value,
          style: _getStyleForClass(node.className, isDark),
        ));
      }
      if (node.children != null && node.children!.isNotEmpty) {
        spans.addAll(_convertNodes(node.children!, isDark));
      }
    }
    return spans;
  }

  TextStyle? _getStyleForClass(String? className, bool isDark) {
    if (className == null) return null;
    final color = _syntaxColors[className];
    if (color != null) {
      return TextStyle(
          color: isDark ? color.$1 : color.$2,
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.4);
    }
    return null;
  }

  static const Map<String, (Color, Color)> _syntaxColors = {
    'keyword': (Color(0xFF569CD6), Color(0xFF0000FF)),
    'built_in': (Color(0xFF4EC9B0), Color(0xFF267F99)),
    'type': (Color(0xFF4EC9B0), Color(0xFF267F99)),
    'literal': (Color(0xFF569CD6), Color(0xFF0000FF)),
    'number': (Color(0xFFB5CEA8), Color(0xFF098658)),
    'string': (Color(0xFFCE9178), Color(0xFFA31515)),
    'regexp': (Color(0xFFCE9178), Color(0xFFA31515)),
    'symbol': (Color(0xFFCE9178), Color(0xFFA31515)),
    'comment': (Color(0xFF6A9955), Color(0xFF008000)),
    'doctag': (Color(0xFF6A9955), Color(0xFF008000)),
    'meta': (Color(0xFF6A9955), Color(0xFF008000)),
    'meta-keyword': (Color(0xFF569CD6), Color(0xFF0000FF)),
    'meta-string': (Color(0xFFCE9178), Color(0xFFA31515)),
    'title': (Color(0xFFDCDCAA), Color(0xFF795E26)),
    'title.class_': (Color(0xFF4EC9B0), Color(0xFF267F99)),
    'title.function_': (Color(0xFFDCDCAA), Color(0xFF795E26)),
    'attr': (Color(0xFF9CDCFE), Color(0xFFE50000)),
    'attribute': (Color(0xFF9CDCFE), Color(0xFFE50000)),
    'variable': (Color(0xFF9CDCFE), Color(0xFF001080)),
    'params': (Color(0xFF9CDCFE), Color(0xFF001080)),
    'selector-tag': (Color(0xFF569CD6), Color(0xFF0000FF)),
    'selector-id': (Color(0xFFDCDCAA), Color(0xFF795E26)),
    'selector-class': (Color(0xFFDCDCAA), Color(0xFF795E26)),
    'tag': (Color(0xFF569CD6), Color(0xFF0000FF)),
    'name': (Color(0xFF569CD6), Color(0xFF0000FF)),
    'deletion': (Color(0xFFFF5555), Color(0xFFFF5555)),
    'addition': (Color(0xFF6A9955), Color(0xFF008000)),
  };

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    showToast(context, '已复制 ${widget.code.split('\n').length} 行代码');
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _showFullscreen(BuildContext context) {
    final theme = Theme.of(context);

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: Text(widget.language ?? '代码',
              style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: '复制',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.code));
                showToast(context, '已复制到剪贴板');
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(
                  widget.code.split('\n').length,
                  (i) => Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.4,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SelectableText.rich(
                  TextSpan(
                    children:
                        _highlightCode(widget.code, widget.language, theme),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final langDisplay = widget.language ?? '';
    final lines = widget.code.split('\n');
    final lineCount = lines.length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: isDark ? Colors.white10 : Colors.black12,
            child: Row(
              children: [
                Icon(Icons.code, size: 14, color: theme.colorScheme.primary),
                if (langDisplay.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    langDisplay,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Text(
                  '$lineCount 行',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showFullscreen(context),
                  child: Icon(Icons.fullscreen,
                      size: 18, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _copyCode,
                  child: Text(
                    _copied ? '已复制' : '复制',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (lineCount > 1)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(
                        lineCount,
                        (i) => Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.4,
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.25),
                          ),
                        ),
                      ),
                    ),
                  if (lineCount > 1) const SizedBox(width: 10),
                  SelectableText.rich(
                    TextSpan(
                      children: _highlightCode(
                          widget.code, widget.language, theme),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
