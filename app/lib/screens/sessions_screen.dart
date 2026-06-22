import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../models/session.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  String _searchQuery = '';
  final _searchController = TextEditingController();
  List<Session>? _searchResults;
  bool _searching = false;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _performSearch(String query, ChatProvider provider) {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = query;
    });
    if (query.isEmpty) {
      setState(() {
        _searchResults = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await provider.searchSessions(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('会话列表'),
        centerTitle: true,
      ),
      body: Consumer<ChatProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final sessions = _searchResults ?? provider.sessions;

          if (provider.sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 64,
                      color: theme.colorScheme.onSurface.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text(
                    '暂无会话',
                    style: TextStyle(
                      fontSize: 18,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '开始一段新对话吧',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索会话和消息...',
                    prefixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)),
                          )
                        : const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerLow,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _searchResults = null;
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) =>
                      _performSearch(v, context.read<ChatProvider>()),
                ),
              ),
              Expanded(
                child: sessions.isEmpty && !_searching
                    ? Center(
                        child: Text(
                            _searchQuery.isEmpty ? '' : '没有找到匹配的会话',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.4),
                            )),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: sessions.length,
                        itemBuilder: (context, index) {
                          return _SessionTile(session: sessions[index]);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createSession(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _createSession(BuildContext context) {
    context.read<ChatProvider>().createSession();
    // Close the sessions screen to go back to the chat with the new session
    Navigator.pop(context);
  }
}

class _SessionTile extends StatelessWidget {
  final Session session;

  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected =
        context.watch<ChatProvider>().currentSession?.id == session.id;

    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.error,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: ListTile(
        selected: isSelected,
        selectedTileColor:
            theme.colorScheme.primaryContainer.withOpacity(0.3),
        leading: CircleAvatar(
          backgroundColor: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHigh,
          child: Icon(
            Icons.chat,
            size: 20,
            color: isSelected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
        ),
        title: Text(
          session.title ?? '未命名会话',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          _formatDate(session.createdAt),
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
        trailing: Icon(Icons.chevron_right,
            size: 20,
            color: theme.colorScheme.onSurface.withOpacity(0.3)),
        onTap: () {
          context.read<ChatProvider>().selectSession(session.id);
          Navigator.pop(context);
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${date.month}/${date.day}';
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定删除「${session.title ?? '未命名会话'}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              context.read<ChatProvider>().deleteSession(session.id);
              Navigator.pop(ctx, true);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
