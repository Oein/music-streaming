import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../models/models.dart';
import '../player/player_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/safe_sides.dart';
import '../widgets/track_cover.dart';
import 'album_detail_screen.dart';

// Listening stats: a year of daily listening as a contribution-style heatmap,
// what was played on the selected day, and the most played tracks / albums /
// artists over a chosen period.

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatListenTime(double seconds) {
  final s = seconds.round();
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  if (m < 60) return '${m}m';
  final h = m ~/ 60, rm = m % 60;
  return rm == 0 ? '${h}h' : '${h}h ${rm}m';
}

String _plays(int n) => n == 1 ? '1 play' : '$n plays';

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

// Calendar-day arithmetic that ignores DST shifts.
DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

enum _Period { week, month, year, all }

extension on _Period {
  String get label => switch (this) {
        _Period.week => '7 days',
        _Period.month => '30 days',
        _Period.year => 'Year',
        _Period.all => 'All time',
      };
  DateTime? get from => switch (this) {
        _Period.week => _addDays(_today(), -6),
        _Period.month => _addDays(_today(), -29),
        _Period.year => _addDays(_today(), -364),
        _Period.all => null,
      };
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  // The heatmap shows 53 week columns ending with the current week.
  static const _weeks = 53;

  late final DateTime _gridStart;
  Map<DateTime, ListenDay> _calendar = {};
  bool _calendarLoading = true;
  String? _error;

  DateTime _selected = _today();
  Future<DayListenDetail>? _dayFuture;

  _Period _period = _Period.month;
  Future<TopListens>? _topFuture;

  @override
  void initState() {
    super.initState();
    final today = _today();
    // Columns are Monday-first weeks; the last column contains today.
    final thisMonday = _addDays(today, -(today.weekday - 1));
    _gridStart = _addDays(thisMonday, -7 * (_weeks - 1));
    _refresh();
  }

  Future<void> _refresh() async {
    final api = context.read<ApiClient>();
    // Include whatever is playing right now.
    await context.read<PlayerService>().flushListens();
    setState(() {
      _dayFuture = api.listenDay(_selected);
      _topFuture = api.topListens(from: _period.from, to: _today());
    });
    try {
      final days = await api.listenCalendar(_gridStart, _today());
      if (!mounted) return;
      setState(() {
        _calendar = {for (final d in days) d.day: d};
        _calendarLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _calendarLoading = false;
        _error = 'Couldn\'t load listening history. Pull down to try again.';
      });
    }
  }

  void _select(DateTime day) {
    setState(() {
      _selected = day;
      _dayFuture = context.read<ApiClient>().listenDay(day);
    });
  }

  void _setPeriod(_Period p) {
    setState(() {
      _period = p;
      _topFuture =
          context.read<ApiClient>().topListens(from: p.from, to: _today());
    });
  }

  void _play(List<TrackListenStat> items, int index) {
    final tracks = <Track>[];
    var start = 0;
    for (var i = 0; i < items.length; i++) {
      final t = items[i].track;
      if (t == null) continue;
      if (i == index) start = tracks.length;
      tracks.add(t);
    }
    if (tracks.isNotEmpty) {
      context.read<PlayerService>().playQueue(tracks, startIndex: start);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Listening stats')),
      bottomNavigationBar: const MiniPlayer(),
      body: SafeSides(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _section(theme, 'Activity'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              _HeatmapCard(
                start: _gridStart,
                weeks: _weeks,
                data: _calendar,
                loading: _calendarLoading,
                selected: _selected,
                onSelect: _select,
              ),
              _yearSummary(theme),
              const SizedBox(height: 8),
              _dayDetail(theme),
              const SizedBox(height: 8),
              _section(theme, 'Most played'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<_Period>(
                  showSelectedIcon: false,
                  segments: [
                    for (final p in _Period.values)
                      ButtonSegment(value: p, label: Text(p.label)),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) => _setPeriod(s.first),
                ),
              ),
              const SizedBox(height: 8),
              _topSection(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(title, style: theme.textTheme.titleMedium),
      );

  // Total for the heatmap's range, days listened, and the current streak.
  Widget _yearSummary(ThemeData theme) {
    if (_calendarLoading) return const SizedBox.shrink();
    final total = _calendar.values.fold<double>(0, (s, d) => s + d.seconds);
    final active = _calendar.values.where((d) => d.seconds > 0).length;
    var streak = 0;
    var d = _today();
    // A streak still counts if today has no listening yet.
    if ((_calendar[d]?.seconds ?? 0) == 0) d = _addDays(d, -1);
    while ((_calendar[d]?.seconds ?? 0) > 0) {
      streak++;
      d = _addDays(d, -1);
    }
    final style = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Text(
        '${formatListenTime(total)} in the last year · '
        '$active ${active == 1 ? 'day' : 'days'} listened · '
        '${streak == 0 ? 'no current streak' : '$streak-day streak'}',
        style: style,
      ),
    );
  }

  Widget _dayDetail(ThemeData theme) {
    final d = _selected;
    final title = d == _today()
        ? 'Today'
        : '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year}';
    return FutureBuilder<DayListenDetail>(
      future: _dayFuture,
      builder: (context, snap) {
        final detail = snap.data;
        final header = Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const Spacer(),
              if (detail != null && detail.seconds > 0)
                Text(
                  '${formatListenTime(detail.seconds)} · ${_plays(detail.plays)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        );
        if (snap.connectionState != ConnectionState.done) {
          return Column(children: [
            header,
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          ]);
        }
        if (snap.hasError) {
          return Column(children: [
            header,
            const ListTile(title: Text('Couldn\'t load this day.')),
          ]);
        }
        if (detail == null || detail.tracks.isEmpty) {
          return Column(children: [
            header,
            ListTile(
              title: Text('Nothing played on this day.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ]);
        }
        return Column(children: [
          header,
          for (var i = 0; i < detail.tracks.length; i++)
            _trackRow(theme, detail.tracks, i, ranked: false),
        ]);
      },
    );
  }

  Widget _trackRow(ThemeData theme, List<TrackListenStat> items, int i,
      {required bool ranked}) {
    final s = items[i];
    return ListTile(
      leading: Row(mainAxisSize: MainAxisSize.min, children: [
        if (ranked)
          SizedBox(
            width: 28,
            child: Text('${i + 1}',
                style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        TrackCover(coverArtId: s.track?.coverArtId, size: 44),
      ]),
      title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [s.artist, s.albumName].whereType<String>().join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_plays(s.plays), style: theme.textTheme.bodyMedium),
          Text(formatListenTime(s.seconds),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
      enabled: s.track != null,
      onTap: s.track == null ? null : () => _play(items, i),
    );
  }

  Widget _topSection(ThemeData theme) {
    return FutureBuilder<TopListens>(
      future: _topFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          );
        }
        final top = snap.data;
        if (snap.hasError || top == null) {
          return const ListTile(title: Text('Couldn\'t load top lists.'));
        }
        if (top.tracks.isEmpty) {
          return ListTile(
            title: Text('Nothing played in this period yet.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          );
        }
        final muted = theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Wrap(spacing: 24, runSpacing: 8, children: [
                _stat(theme, formatListenTime(top.seconds), 'listened'),
                _stat(theme, '${top.plays}', 'plays'),
                _stat(theme, '${top.days}', top.days == 1 ? 'day' : 'days'),
              ]),
            ),
            _subhead(theme, 'Tracks'),
            for (var i = 0; i < top.tracks.length; i++)
              _trackRow(theme, top.tracks, i, ranked: true),
            _subhead(theme, 'Albums'),
            SizedBox(
              height: 196,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: top.albums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final a = top.albums[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: a.album == null
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    AlbumDetailScreen(album: a.album!))),
                    child: SizedBox(
                      width: 128,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(children: [
                            TrackCover(
                                coverArtId: a.album?.coverArtId, size: 128),
                            Positioned(
                              left: 6,
                              top: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Text(a.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(
                              '${_plays(a.plays)} · ${formatListenTime(a.seconds)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: muted),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            _subhead(theme, 'Artists'),
            _ArtistBars(artists: top.artists),
          ],
        );
      },
    );
  }

  Widget _subhead(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );

  Widget _stat(ThemeData theme, String value, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.headlineSmall),
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );
}

// Contribution-style grid: one column per week (Monday on top), one cell per
// day, shaded by listening time relative to the busiest day in range.
class _HeatmapCard extends StatelessWidget {
  final DateTime start;
  final int weeks;
  final Map<DateTime, ListenDay> data;
  final bool loading;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  const _HeatmapCard({
    required this.start,
    required this.weeks,
    required this.data,
    required this.loading,
    required this.selected,
    required this.onSelect,
  });

  static const _gap = 3.0;
  static const _labelW = 30.0;
  // Cells grow to fill wide windows, within these bounds; narrower than the
  // minimum, the grid scrolls (starting at the current week).
  static const _minCell = 12.0;
  static const _maxCell = 18.0;

  // 0 = no listening, 1..4 = quartiles of the busiest day.
  int _level(double seconds, double max) {
    if (seconds <= 0 || max <= 0) return 0;
    final r = seconds / max;
    if (r > 0.75) return 4;
    if (r > 0.5) return 3;
    if (r > 0.25) return 2;
    return 1;
  }

  Color _color(ColorScheme cs, int level) => level == 0
      ? cs.surfaceContainerHighest
      : Color.lerp(
          cs.primary.withValues(alpha: 0.25), cs.primary, (level - 1) / 3)!;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(builder: (context, c) {
          final avail = c.maxWidth - _labelW;
          final cell =
              (avail / weeks - _gap).clamp(_minCell, _maxCell).toDouble();
          return _grid(context, cell, scrolls: weeks * (cell + _gap) > avail);
        }),
      );

  Widget _grid(BuildContext context, double cell, {required bool scrolls}) {
    final cs = Theme.of(context).colorScheme;
    final today = _today();
    final max =
        data.values.fold<double>(0, (m, d) => d.seconds > m ? d.seconds : m);
    final labelStyle = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: cs.onSurfaceVariant, fontSize: 10);

    final columns = <Widget>[];
    for (var w = 0; w < weeks; w++) {
      final weekStart = _addDays(start, w * 7);
      // Month label above the first column that starts a new month.
      final prev = _addDays(weekStart, -7);
      final showMonth = w == 0 || prev.month != weekStart.month;
      columns.add(Padding(
        padding: const EdgeInsets.only(right: _gap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 16,
              width: cell,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: 40,
                child: showMonth
                    ? Text(_months[weekStart.month - 1], style: labelStyle)
                    : null,
              ),
            ),
            for (var d = 0; d < 7; d++)
              _dayCell(cs, cell, _addDays(weekStart, d), today, max),
          ],
        ),
      ));
    }

    final grid = Row(children: columns);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Weekday labels (Mon / Wed / Fri), aligned with the rows.
            SizedBox(
              width: _labelW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  for (var d = 0; d < 7; d++)
                    SizedBox(
                      height: cell + _gap,
                      child: d.isEven && d < 6
                          ? Text(_weekdays[d], style: labelStyle)
                          : null,
                    ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedOpacity(
                opacity: loading ? 0.4 : 1,
                duration: const Duration(milliseconds: 200),
                child: scrolls
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        // Start scrolled to the current week.
                        reverse: true,
                        child: grid,
                      )
                    : grid,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Less', style: labelStyle),
            const SizedBox(width: 4),
            for (var l = 0; l <= 4; l++)
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: _color(cs, l),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            const SizedBox(width: 4),
            Text('More', style: labelStyle),
          ],
        ),
      ],
    );
  }

  Widget _dayCell(
      ColorScheme cs, double size, DateTime day, DateTime today, double max) {
    final future = day.isAfter(today);
    final d = data[day];
    final isSelected = day == selected;
    final tip = d == null || d.seconds == 0
        ? 'No listening · ${formatDay(day)}'
        : '${formatListenTime(d.seconds)} · ${_plays(d.plays)} · ${formatDay(day)}';
    final cell = Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(bottom: _gap),
      decoration: BoxDecoration(
        color: future
            ? Colors.transparent
            : _color(cs, _level(d?.seconds ?? 0, max)),
        borderRadius: BorderRadius.circular(3),
        border: isSelected ? Border.all(color: cs.onSurface, width: 1.5) : null,
      ),
    );
    if (future) return cell;
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(day),
        child: cell,
      ),
    );
  }
}

// Top artists as horizontal bars scaled to the most played one.
class _ArtistBars extends StatelessWidget {
  final List<ArtistListenStat> artists;
  const _ArtistBars({required this.artists});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (artists.isEmpty) return const SizedBox.shrink();
    final maxPlays =
        artists.map((a) => a.plays).fold<int>(1, (m, p) => p > m ? p : m);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final a in artists)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Stack(children: [
                    FractionallySizedBox(
                      widthFactor: (a.plays / maxPlays).clamp(0.02, 1.0),
                      child: Container(
                        height: 30,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(a.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: Text(
                    '${_plays(a.plays)} · ${formatListenTime(a.seconds)}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
