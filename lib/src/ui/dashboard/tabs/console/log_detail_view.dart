import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/log_entry.dart';
import '../../../../utils/log_formatters.dart';
import '../../../../utils/share_text.dart';
import '../../../widgets/detail_section.dart';
import '../../../widgets/key_value_table.dart';
import '../../../theme/theme.dart';

/// Actions exposed in the detail view's share menu.
enum _ShareAction { copyConcise, copyRaw, shareConcise, shareRaw }

/// A full-screen, structured view of a single [LogEntry], showing General
/// info, an optional Stack Trace section, and a Data section plus sharing
/// (plain text / system share).
class LogDetailView extends StatefulWidget {
  const LogDetailView({required this.entry, super.key});

  final LogEntry entry;

  @override
  State<LogDetailView> createState() => _LogDetailViewState();
}

class _LogDetailViewState extends State<LogDetailView> {
  bool _isConcise = true;

  @override
  Widget build(BuildContext context) {
    final shortTs = _shortTimestamp(widget.entry.timestamp);
    return Scaffold(
      appBar: AppBar(
        title: Text('[${widget.entry.level.name}] $shortTs'),
        actions: [
          PopupMenuButton<_ShareAction>(
            icon: const Icon(Icons.share),
            onSelected: (action) => _onShare(context, action),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ShareAction.copyConcise,
                child: Text('Copy concise'),
              ),
              PopupMenuItem(
                value: _ShareAction.copyRaw,
                child: Text('Copy raw'),
              ),
              PopupMenuItem(
                value: _ShareAction.shareConcise,
                child: Text('Share concise…'),
              ),
              PopupMenuItem(
                value: _ShareAction.shareRaw,
                child: Text('Share raw…'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: ThemePadding.paddingAll12,
        children: [
          _generalSection(context),
          if (widget.entry.stackTrace?.isNotEmpty ?? false)
            _stackTraceSection(context),
          _dataSection(context),
        ],
      ),
    );
  }

  Widget _generalSection(BuildContext context) {
    return DetailSection(
      title: 'General',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailKeyValueRow.text('Message', widget.entry.message),
          DetailKeyValueRow.text('Level', widget.entry.level.name),
          DetailKeyValueRow.text(
            'Timestamp',
            widget.entry.timestamp.toIso8601String(),
          ),
        ],
      ),
    );
  }

  Widget _stackTraceSection(BuildContext context) {
    final stackTrace = widget.entry.stackTrace!;
    final displayedStackTrace =
        _isConcise ? normalizeStackTrace(stackTrace) : stackTrace;

    return DetailSection(
      title: 'Stack Trace',
      trailing: TextButton.icon(
        onPressed: () {
          setState(() {
            _isConcise = !_isConcise;
          });
        },
        icon: Icon(_isConcise ? Icons.unfold_more : Icons.unfold_less),
        label: Text(_isConcise ? 'Show raw' : 'Show concise'),
      ),
      child: Container(
        width: double.infinity,
        padding: ThemePadding.paddingAll8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(ThemeSize.radius4),
        ),
        child: SelectableText(
          displayedStackTrace,
          style: ThemeTextStyle.monospaceStyle,
        ),
      ),
    );
  }

  Widget _dataSection(BuildContext context) {
    return DetailSection(
      title: 'Data',
      child: KeyValueTable(data: widget.entry.data, emptyLabel: '(no data)'),
    );
  }

  String _shortTimestamp(DateTime ts) {
    return '${ts.year}-${_p(ts.month)}-${_p(ts.day)} '
        '${_p(ts.hour)}:${_p(ts.minute)}:${_p(ts.second)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  Future<void> _onShare(BuildContext context, _ShareAction action) async {
    final messenger = ScaffoldMessenger.of(context);

    final bool isConcise =
        action == _ShareAction.copyConcise || action == _ShareAction.shareConcise;

    final String logText = buildLogPlainText(
      widget.entry,
      isConcise: isConcise,
    );

    switch (action) {
      case _ShareAction.copyConcise:
      case _ShareAction.copyRaw:
        await Clipboard.setData(ClipboardData(text: logText));
        messenger.showSnackBar(
          const SnackBar(content: Text('Details copied to clipboard')),
        );
      case _ShareAction.shareConcise:
      case _ShareAction.shareRaw:
        try {
          await shareText(logText);
        } catch (_) {
          // Fallback to clipboard when the platform has no share sheet.
          await Clipboard.setData(ClipboardData(text: logText));
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Share unavailable — copied to clipboard'),
            ),
          );
        }
    }
  }
}
