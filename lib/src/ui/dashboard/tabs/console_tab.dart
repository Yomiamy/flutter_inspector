import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/flutter_inspector.dart';
import '../../../models/database_entry.dart';
import '../../../models/log_entry.dart';
import '../../../models/log_level.dart';
import '../../../models/navigator_entry.dart';
import '../../../models/network_entry.dart';
import '../../../models/timestamped_entry.dart';
import '../../../extensions/log_level_color_extension.dart';
import '../../../observers/inspector_route_names.dart';
import '../../../utils/console_utils.dart';
import '../../theme/theme.dart';
import 'console/log_detail_view.dart';
import 'network/network_detail_view.dart';

/// Row background applied to error logs and failed network calls so they stand
/// out while scrolling a long merged timeline. Kept faint on purpose: the tint
/// marks the row without competing with the level-coloured text.
final Color _kErrorRowTint = ThemeColor.colorF44336.withOpacity(0.08);

/// Tab for displaying a cross-layer merged timeline (logs, network, navigation,
/// database) with a source filter and per-type row dispatch.
class ConsoleTab extends StatefulWidget {
  const ConsoleTab({required this.inspector, super.key});

  final FlutterInspector inspector;

  @override
  State<ConsoleTab> createState() => _ConsoleTabState();
}

class _ConsoleTabState extends State<ConsoleTab> {
  /// The currently selected timeline sources. Initialised to all four (the
  /// "All" state).
  Set<TimelineSource> _selected = {
    TimelineSource.log,
    TimelineSource.network,
    TimelineSource.nav,
    TimelineSource.db,
  };

  bool _showOnlyBookmarks = false;

  /// Keyword and level constraints applied on top of the source selection.
  ConsoleFilter _filter = const ConsoleFilter();

  final ScrollController _scrollController = ScrollController();

  /// Owned here (not by [_SearchBar]) so [_jumpToEntry] can clear the
  /// visible text when it resets [_filter] — otherwise the field would keep
  /// showing a keyword that no longer filters anything.
  final TextEditingController _searchController = TextEditingController();

  static const Set<TimelineSource> _all = {
    TimelineSource.log,
    TimelineSource.network,
    TimelineSource.nav,
    TimelineSource.db,
  };

  static const Map<TimelineSource, String> _sourceLabels = {
    TimelineSource.log: 'Log',
    TimelineSource.network: 'Network',
    TimelineSource.nav: 'Nav',
    TimelineSource.db: 'DB',
  };

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  /// Whether the filter currently equals "All" (every source selected).
  bool get _isAll => _selected.length == _all.length;

  void _selectAll() => setState(() {
    _selected = {..._all};
    _showOnlyBookmarks = false;
  });

  void _selectOnly(TimelineSource source) => setState(() {
    _selected = {source};
    _showOnlyBookmarks = false;
  });

  void _setKeyword(String keyword) => setState(() {
    _filter = ConsoleFilter(
      keyword: keyword,
      levels: _filter.levels,
      errorsOnly: _filter.errorsOnly,
    );
  });

  void _toggleLevel(LogLevel level) => setState(() {
    final levels = {..._filter.levels};
    if (!levels.remove(level)) levels.add(level);
    _filter = ConsoleFilter(
      keyword: _filter.keyword,
      levels: levels,
      // Picking a level means the user wants that level, not "all failures".
      errorsOnly: false,
    );
  });

  /// Row height used to approximate a scroll offset.
  ///
  /// Rows vary in height by type, so there is no exact offset to compute
  /// without measuring every row above the target. Landing near the entry is
  /// enough to read what came before and after it, which is the whole point of
  /// going back to the full timeline.
  static const double _kApproxRowHeight = 72;

  /// Clears every filter and scrolls the full timeline to [entry].
  Future<void> _jumpToEntry(TimestampedEntry entry) async {
    final index = widget.inspector.mergedTimeline(sources: _all).indexOf(entry);
    // Gone from the ring buffer between render and tap: nothing to scroll to.
    if (index < 0) return;

    _searchController.clear();
    setState(() {
      _filter = const ConsoleFilter();
      _selected = {..._all};
      _showOnlyBookmarks = false;
    });

    // The list is longer now, so its scroll extent is too. Scrolling in the
    // same frame would clamp against the filtered list's old extent.
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;

    final offset = (index * _kApproxRowHeight).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    await _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _toggleErrorsOnly() => setState(() {
    _filter = ConsoleFilter(
      keyword: _filter.keyword,
      // The shortcut supersedes the level set, so drop it rather than leave a
      // selection that has no effect while the chip is on.
      levels: const {},
      errorsOnly: !_filter.errorsOnly,
    );
  });

  @override
  Widget build(BuildContext context) {
    var entries = widget.inspector.mergedTimeline(sources: _selected);
    entries = applyConsoleFilter(entries, _filter);
    if (_showOnlyBookmarks) {
      entries = entries.where((e) => widget.inspector.isBookmarked(e)).toList();
    }

    return Column(
      children: [
        _SearchBar(controller: _searchController, onChanged: _setKeyword),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const SizedBox(width: ThemeSize.space8),
                    FilterChip(
                      label: const Text('All'),
                      selected: _isAll,
                      onSelected: (_) => _selectAll(),
                    ),
                    for (final source in TimelineSource.values) ...[
                      const SizedBox(width: ThemeSize.space8),
                      FilterChip(
                        label: Text(_sourceLabels[source] ?? ''),
                        selected: !_isAll && _selected.contains(source),
                        onSelected: (_) => _selectOnly(source),
                      ),
                    ],
                    const SizedBox(width: ThemeSize.space8),
                    FilterChip(
                      label: const Text('📌 Bookmarks'),
                      selected: _showOnlyBookmarks,
                      onSelected: (_) => setState(() {
                        _showOnlyBookmarks = !_showOnlyBookmarks;
                      }),
                    ),
                    const SizedBox(width: ThemeSize.space8),
                    FilterChip(
                      label: const Text('⚡ Errors only'),
                      selected: _filter.errorsOnly,
                      onSelected: (_) => _toggleErrorsOnly(),
                    ),
                    for (final entry in logLevelLabels.entries) ...[
                      const SizedBox(width: ThemeSize.space8),
                      FilterChip(
                        label: Text(entry.value),
                        selected: _filter.levels.contains(entry.key),
                        onSelected: (_) => _toggleLevel(entry.key),
                      ),
                    ],
                    const SizedBox(width: ThemeSize.space8),
                  ],
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                widget.inspector.clearLogs();
                widget.inspector.clearNetwork();
                widget.inspector.clearNavigator();
                widget.inspector.clearDatabase();
                _refresh();
              },
            ),
          ],
        ),
        Expanded(
          child: _showOnlyBookmarks && entries.isEmpty
              ? const Center(child: Text('No bookmarked entries'))
              : !_filter.isEmpty && entries.isEmpty
              ? const Center(child: Text('No matches'))
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _EntryRowDispatcher(
                    entry: entries[index],
                    inspector: widget.inspector,
                    onToggleBookmark: () => setState(() {
                      widget.inspector.toggleBookmark(entries[index]);
                    }),
                    onJump: _filter.isEmpty
                        ? null
                        : () => _jumpToEntry(entries[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Wraps a row so tapping it jumps back to the unfiltered timeline.
///
/// Only the tap is taken over. Long-press still reaches the row underneath, so
/// bookmarking keeps working while a filter is active — an entry you just
/// searched for is precisely one you may want to pin.
class _JumpRow extends StatelessWidget {
  const _JumpRow({
    required this.onJump,
    required this.onLongPress,
    required this.child,
  });

  final VoidCallback? onJump;
  final VoidCallback onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // The child is wrapped in IgnorePointer, so without an opaque behavior
      // there is nothing left to hit-test and neither gesture would fire.
      behavior: HitTestBehavior.opaque,
      onTap: onJump,
      onLongPress: onLongPress,
      child: child,
    );
  }
}

/// Keyword field for the console timeline.
///
/// Deliberately leaner than the network tab's namesake, which also carries the
/// refresh/clear buttons and a match counter: the console keeps those in its
/// own chip row, so bundling them here would duplicate existing controls.
class _SearchBar extends StatefulWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  /// Owned by the parent [_ConsoleTabState] so a jump-to-entry can clear the
  /// visible text alongside the filter it resets.
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ThemeSize.space8,
        ThemeSize.space8,
        ThemeSize.space8,
        ThemeSize.space4,
      ),
      child: TextField(
        controller: widget.controller,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search message / url / route / table',
          prefixIcon: const Icon(Icons.search, size: ThemeSize.size20),
          suffixIcon: widget.controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: ThemeSize.size20),
                  onPressed: _clear,
                ),
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) {
          widget.onChanged(value);
          // Rebuild so the clear affordance tracks emptiness.
          setState(() {});
        },
      ),
    );
  }
}

/// Dispatches a [TimestampedEntry] to the matching row visual by runtime type.
class _EntryRowDispatcher extends StatelessWidget {
  const _EntryRowDispatcher({
    required this.entry,
    required this.inspector,
    required this.onToggleBookmark,
    this.onJump,
  });

  final TimestampedEntry entry;
  final FlutterInspector inspector;
  final VoidCallback onToggleBookmark;

  /// Set only while a filter is narrowing the list. Tapping a row then means
  /// "take me back to this moment in the full timeline" rather than "show me
  /// this entry's details" — the detail view is one tap away again afterwards.
  final VoidCallback? onJump;

  @override
  Widget build(BuildContext context) {
    // Intercepting here rather than in each row keeps the two tap meanings in
    // one place, and gives navigation/database rows a jump target even though
    // they have no detail view of their own to tap into.
    if (onJump != null) {
      return _JumpRow(
        onJump: onJump,
        onLongPress: onToggleBookmark,
        // Absorbs the row's own tap (detail view) so it cannot compete with
        // the jump, while _JumpRow re-offers long-press above it.
        child: IgnorePointer(
          child: _EntryRowDispatcher(
            entry: entry,
            inspector: inspector,
            onToggleBookmark: onToggleBookmark,
          ),
        ),
      );
    }

    switch (entry) {
      case final LogEntry e:
        return _LogEntryRow(
          entry: e,
          inspector: inspector,
          onToggleBookmark: onToggleBookmark,
        );
      case final NetworkEntry e:
        return _NetworkEntryRow(
          entry: e,
          inspector: inspector,
          onToggleBookmark: onToggleBookmark,
        );
      case final NavigatorEntry e:
        return _NavigatorEntryRow(
          entry: e,
          inspector: inspector,
          onToggleBookmark: onToggleBookmark,
        );
      case final DatabaseEntry e:
        return _DatabaseEntryRow(
          entry: e,
          inspector: inspector,
          onToggleBookmark: onToggleBookmark,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _LogEntryRow extends StatelessWidget {
  const _LogEntryRow({
    required this.entry,
    required this.inspector,
    required this.onToggleBookmark,
  });

  final LogEntry entry;
  final FlutterInspector inspector;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final canTap =
        (entry.stackTrace?.isNotEmpty ?? false) ||
        (entry.data?.isNotEmpty ?? false);
    final isBookmarked = inspector.isBookmarked(entry);
    return ListTile(
      tileColor: entry.level == LogLevel.error ? _kErrorRowTint : null,
      title: Row(
        children: [
          if (isBookmarked) ...[
            const Icon(
              Icons.push_pin,
              size: ThemeSize.size18,
              color: ThemeColor.colorFF9800,
            ),
            const SizedBox(width: ThemeSize.space4),
          ],
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(color: entry.level.color),
            ),
          ),
        ],
      ),
      subtitle: Text(entry.displayTime),
      trailing: canTap
          ? const Icon(Icons.chevron_right, size: ThemeSize.size18)
          : null,
      onTap: canTap
          ? () => pushInspectorRoute(
              context,
              kInspectorLogDetailRoute,
              (_) => LogDetailView(entry: entry),
            )
          : null,
      onLongPress: onToggleBookmark,
    );
  }
}

class _NetworkEntryRow extends StatelessWidget {
  const _NetworkEntryRow({
    required this.entry,
    required this.inspector,
    required this.onToggleBookmark,
  });

  final NetworkEntry entry;
  final FlutterInspector inspector;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final isBookmarked = inspector.isBookmarked(entry);
    return ListTile(
      tileColor: entry.isFailed ? _kErrorRowTint : null,
      title: Row(
        children: [
          if (isBookmarked) ...[
            const Icon(
              Icons.push_pin,
              size: ThemeSize.size18,
              color: ThemeColor.colorFF9800,
            ),
            const SizedBox(width: ThemeSize.space4),
          ],
          Expanded(
            child: Text(
              '${entry.method} ${entry.statusCode ?? '-'} ${entry.url}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(entry.displayTime),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.duration != null &&
              entry.duration! >= inspector.slowRequestThreshold)
            Container(
              margin: const EdgeInsets.only(right: ThemeSize.space8),
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeSize.space4,
                vertical: 2.0,
              ),
              decoration: BoxDecoration(
                color: ThemeColor.colorFF9800.withOpacity(0.15),
                borderRadius: BorderRadius.circular(ThemeSize.radius4),
                border: Border.all(color: ThemeColor.colorFF9800),
              ),
              child: const Text(
                '🐢 SLOW',
                style: TextStyle(
                  fontSize: ThemeFontSize.fontSize10,
                  color: ThemeColor.colorFF9800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const Icon(Icons.chevron_right, size: ThemeSize.size18),
        ],
      ),
      onTap: () => pushInspectorRoute(
        context,
        kInspectorNetworkDetailRoute,
        (_) => NetworkDetailView(
          entry: entry,
          redactSensitiveData: inspector.redactSensitiveData,
        ),
      ),
      onLongPress: onToggleBookmark,
    );
  }
}

class _NavigatorEntryRow extends StatelessWidget {
  const _NavigatorEntryRow({
    required this.entry,
    required this.inspector,
    required this.onToggleBookmark,
  });

  final NavigatorEntry entry;
  final FlutterInspector inspector;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final isBookmarked = inspector.isBookmarked(entry);
    return ListTile(
      title: Row(
        children: [
          if (isBookmarked) ...[
            const Icon(
              Icons.push_pin,
              size: ThemeSize.size18,
              color: ThemeColor.colorFF9800,
            ),
            const SizedBox(width: ThemeSize.space4),
          ],
          Expanded(child: Text('${entry.action.name} ${entry.displayName}')),
        ],
      ),
      subtitle: Text(entry.displayTime),
      onLongPress: onToggleBookmark,
    );
  }
}

class _DatabaseEntryRow extends StatelessWidget {
  const _DatabaseEntryRow({
    required this.entry,
    required this.inspector,
    required this.onToggleBookmark,
  });

  final DatabaseEntry entry;
  final FlutterInspector inspector;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final isBookmarked = inspector.isBookmarked(entry);
    return ListTile(
      title: Row(
        children: [
          if (isBookmarked) ...[
            const Icon(
              Icons.push_pin,
              size: ThemeSize.size18,
              color: ThemeColor.colorFF9800,
            ),
            const SizedBox(width: ThemeSize.space4),
          ],
          Expanded(child: Text('${entry.operation.name} ${entry.tableName}')),
        ],
      ),
      subtitle: Text(entry.displayTime),
      onLongPress: onToggleBookmark,
    );
  }
}
