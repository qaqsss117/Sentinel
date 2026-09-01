import 'dart:async';
import 'dart:io';

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/xboard/utils/xboard_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:go_router/go_router.dart';

class TicketSupportPage extends StatefulWidget {
  const TicketSupportPage({super.key});

  @override
  State<TicketSupportPage> createState() => _TicketSupportPageState();
}

class _TicketSupportPageState extends State<TicketSupportPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  Timer? _refreshTimer;
  List<TicketModel> _tickets = const [];
  TicketDetailModel? _ticket;
  int? _selectedTicketId;
  Object? _error;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isSending = false;
  bool _isClosing = false;
  bool _isCreating = false;

  bool get _hasOpenTicket => _tickets.any((ticket) => ticket.status == 0);

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isSending && !_isClosing && !_isCreating) {
        _refresh(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool showLoading = true, int? selectTicketId}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final tickets = await XBoardSDK.instance.ticket.getTickets();
      final selected = _selectTicket(
        tickets,
        selectTicketId ?? _selectedTicketId,
      );
      final detail = selected == null
          ? null
          : await XBoardSDK.instance.ticket.getTicket(selected.id);
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _selectedTicketId = selected?.id;
        _ticket = detail;
        _error = null;
        _isLoading = false;
      });
      _scrollToLatestMessage();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    } finally {
      _isRefreshing = false;
    }
  }

  TicketModel? _selectTicket(List<TicketModel> tickets, int? selectedId) {
    for (final ticket in tickets) {
      if (ticket.id == selectedId) return ticket;
    }
    for (final ticket in tickets) {
      if (ticket.status == 0) return ticket;
    }
    return tickets.isEmpty ? null : tickets.first;
  }

  Future<void> _selectTicketById(int ticketId) async {
    if (ticketId == _selectedTicketId) return;
    setState(() {
      _selectedTicketId = ticketId;
      _ticket = null;
      _error = null;
    });
    try {
      final detail = await XBoardSDK.instance.ticket.getTicket(ticketId);
      if (!mounted || _selectedTicketId != ticketId) return;
      setState(() => _ticket = detail);
      _scrollToLatestMessage();
    } catch (error) {
      if (!mounted || _selectedTicketId != ticketId) return;
      setState(() => _error = error);
    }
  }

  Future<void> _sendMessage() async {
    final ticket = _ticket;
    final message = _messageController.text.trim();
    if (ticket == null || ticket.status != 0 || message.isEmpty || _isSending) {
      return;
    }

    setState(() => _isSending = true);
    try {
      await XBoardSDK.instance.ticket.replyTicket(ticket.id, message);
      _messageController.clear();
      await _refresh(showLoading: false, selectTicketId: ticket.id);
    } catch (error) {
      if (!mounted) return;
      XBoardNotification.showError(
        AppLocalizations.of(context).ticketActionFailed(error.toString()),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _createTicket() async {
    if (_hasOpenTicket || _isCreating) return;
    final draft = await showDialog<_TicketDraft>(
      context: context,
      builder: (_) => const _NewTicketDialog(),
    );
    if (draft == null || !mounted) return;

    setState(() => _isCreating = true);
    try {
      await XBoardSDK.instance.ticket.createTicket(
        draft.subject,
        draft.message,
        draft.level,
      );
      if (!mounted) return;
      XBoardNotification.showSuccess(
        AppLocalizations.of(context).ticketCreated,
      );
      _selectedTicketId = null;
      await _refresh(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      XBoardNotification.showError(
        AppLocalizations.of(context).ticketActionFailed(error.toString()),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _closeTicket() async {
    final ticket = _ticket;
    if (ticket == null || ticket.status != 0 || _isClosing) return;
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.ticketClose),
        content: Text(localizations.ticketCloseConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localizations.onlineSupportCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(localizations.ticketClose),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isClosing = true);
    try {
      await XBoardSDK.instance.ticket.closeTicket(ticket.id);
      if (!mounted) return;
      XBoardNotification.showSuccess(localizations.ticketClosed);
      await _refresh(showLoading: false, selectTicketId: ticket.id);
    } catch (error) {
      if (!mounted) return;
      XBoardNotification.showError(
        localizations.ticketActionFailed(error.toString()),
      );
    } finally {
      if (mounted) setState(() => _isClosing = false);
    }
  }

  void _scrollToLatestMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _showTicketHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: _TicketList(
            tickets: _tickets,
            selectedTicketId: _selectedTicketId,
            onSelected: (ticketId) {
              Navigator.pop(context);
              _selectTicketById(ticketId);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    final localizations = AppLocalizations.of(context);
    final scaffold = Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text(localizations.onlineSupportTitle),
              actions: [
                IconButton(
                  onPressed: _tickets.isEmpty ? null : _showTicketHistory,
                  tooltip: localizations.ticketHistory,
                  icon: const Icon(Icons.history),
                ),
                if (!_hasOpenTicket)
                  IconButton(
                    onPressed: _isCreating ? null : _createTicket,
                    tooltip: localizations.ticketNew,
                    icon: const Icon(Icons.add_comment_outlined),
                  ),
              ],
            ),
      body: _buildBody(isDesktop),
    );

    if (isDesktop) return scaffold;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go('/');
      },
      child: scaffold,
    );
  }

  Widget _buildBody(bool isDesktop) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _tickets.isEmpty) {
      return _TicketError(error: _error!, onRetry: _refresh);
    }

    final conversation = _error != null && _ticket == null
        ? _TicketError(
            error: _error!,
            onRetry: () =>
                _refresh(showLoading: false, selectTicketId: _selectedTicketId),
          )
        : _ticket == null
        ? _EmptyConversation(onCreate: _hasOpenTicket ? null : _createTicket)
        : _TicketConversation(
            ticket: _ticket!,
            messageController: _messageController,
            scrollController: _scrollController,
            isSending: _isSending,
            isClosing: _isClosing,
            onSend: _sendMessage,
            onClose: _closeTicket,
            onRefresh: () => _refresh(showLoading: false),
          );

    if (!isDesktop) return conversation;
    return Row(
      children: [
        SizedBox(
          width: 300,
          child: Column(
            children: [
              _SupportHeader(
                canCreate: !_hasOpenTicket,
                isCreating: _isCreating,
                onCreate: _createTicket,
              ),
              const Divider(height: 1),
              Expanded(
                child: _TicketList(
                  tickets: _tickets,
                  selectedTicketId: _selectedTicketId,
                  onSelected: _selectTicketById,
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: conversation),
      ],
    );
  }
}

class _SupportHeader extends StatelessWidget {
  const _SupportHeader({
    required this.canCreate,
    required this.isCreating,
    required this.onCreate,
  });

  final bool canCreate;
  final bool isCreating;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              localizations.onlineSupportTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton.filledTonal(
            onPressed: canCreate && !isCreating ? onCreate : null,
            tooltip: localizations.ticketNew,
            icon: isCreating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
    );
  }
}

class _TicketList extends StatelessWidget {
  const _TicketList({
    required this.tickets,
    required this.selectedTicketId,
    required this.onSelected,
  });

  final List<TicketModel> tickets;
  final int? selectedTicketId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (tickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            localizations.ticketNoTickets,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tickets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final ticket = tickets[index];
        final isOpen = ticket.status == 0;
        return ListTile(
          selected: ticket.id == selectedTicketId,
          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
          leading: CircleAvatar(
            backgroundColor: isOpen
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(isOpen ? Icons.forum_outlined : Icons.lock_outline),
          ),
          title: Text(
            ticket.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            isOpen
                ? (ticket.replyStatus == 0
                      ? localizations.ticketSupportReplied
                      : localizations.ticketWaitingSupport)
                : localizations.ticketStatusClosed,
            maxLines: 1,
          ),
          trailing: Text(
            _formatTicketTime(context, ticket.updatedAt),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          onTap: () => onSelected(ticket.id),
        );
      },
    );
  }
}

class _TicketConversation extends StatelessWidget {
  const _TicketConversation({
    required this.ticket,
    required this.messageController,
    required this.scrollController,
    required this.isSending,
    required this.isClosing,
    required this.onSend,
    required this.onClose,
    required this.onRefresh,
  });

  final TicketDetailModel ticket;
  final TextEditingController messageController;
  final ScrollController scrollController;
  final bool isSending;
  final bool isClosing;
  final VoidCallback onSend;
  final VoidCallback onClose;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isOpen = ticket.status == 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOpen
                          ? localizations.ticketStatusOpen
                          : localizations.ticketStatusClosed,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: isOpen
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRefresh,
                tooltip: localizations.xboardRetry,
                icon: const Icon(Icons.refresh),
              ),
              if (isOpen)
                IconButton(
                  onPressed: isClosing ? null : onClose,
                  tooltip: localizations.ticketClose,
                  icon: isClosing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_outline),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView.builder(
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: ticket.messages.length,
              itemBuilder: (context, index) =>
                  _MessageBubble(message: ticket.messages[index]),
            ),
          ),
        ),
        if (isOpen)
          _MessageComposer(
            controller: messageController,
            isSending: isSending,
            onSend: onSend,
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Text(
              localizations.ticketClosedHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final TicketMessageModel message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: message.isMe
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(8),
            topRight: const Radius.circular(8),
            bottomLeft: Radius.circular(message.isMe ? 8 : 2),
            bottomRight: Radius.circular(message.isMe ? 2 : 8),
          ),
        ),
        child: Column(
          crossAxisAlignment: message.isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(message.message),
            const SizedBox(height: 4),
            Text(
              _formatTicketTime(context, message.createdAt),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: localizations.onlineSupportInputHint,
                    filled: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: isSending ? null : onSend,
                tooltip: localizations.onlineSupportSend,
                icon: isSending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              localizations.ticketNoTickets,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              localizations.ticketNoTicketsDescription,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (onCreate != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_comment_outlined),
                label: Text(localizations.ticketNew),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TicketError extends StatelessWidget {
  const _TicketError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              localizations.ticketLoadFailed(error.toString()),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(localizations.xboardRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketDraft {
  const _TicketDraft({
    required this.subject,
    required this.message,
    required this.level,
  });

  final String subject;
  final String message;
  final int level;
}

class _NewTicketDialog extends StatefulWidget {
  const _NewTicketDialog();

  @override
  State<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends State<_NewTicketDialog> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  int _level = 1;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _submit() {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    final localizations = AppLocalizations.of(context);
    if (subject.isEmpty) {
      XBoardNotification.showError(localizations.ticketSubjectRequired);
      return;
    }
    if (message.isEmpty) {
      XBoardNotification.showError(localizations.ticketMessageRequired);
      return;
    }
    Navigator.pop(
      context,
      _TicketDraft(subject: subject, message: message, level: _level),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(localizations.ticketNew),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _subjectController,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: localizations.ticketSubject,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(localizations.ticketPriority),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Text(localizations.ticketPriorityLow),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text(localizations.ticketPriorityNormal),
                  ),
                  ButtonSegment(
                    value: 2,
                    label: Text(localizations.ticketPriorityHigh),
                  ),
                ],
                selected: {_level},
                onSelectionChanged: (levels) {
                  setState(() => _level = levels.first);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _messageController,
                minLines: 4,
                maxLines: 8,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: localizations.ticketFirstMessage,
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.onlineSupportCancel),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send_outlined),
          label: Text(localizations.ticketCreate),
        ),
      ],
    );
  }
}

String _formatTicketTime(BuildContext context, DateTime value) {
  final localizations = MaterialLocalizations.of(context);
  final local = value.toLocal();
  final date = localizations.formatShortDate(local);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date $time';
}
