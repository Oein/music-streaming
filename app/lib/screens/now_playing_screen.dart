import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../models/models.dart';
import '../player/player_service.dart';
import '../remote/remote_service.dart';
import '../remote/device_picker.dart';
import '../favorites/favorites_service.dart';
import '../settings/settings_service.dart';
import '../widgets/blurred_background.dart';
import '../widgets/marquee_text.dart';
import 'queue_screen.dart';
import 'track_actions.dart' show addToPlaylistFlow;

// Now Playing, cloned from the "beautifulfullscreen" design
// (github.com/Oein/beautifulfullscreen): a blurred cover-art background, the
// square cover beside big bold title + artist, a flat advanced controller
// (shuffle/repeat · transport · heart) over a thin progress bar, and a vertical
// volume slider pinned to the left edge.

// Signature accent used by the reference for progress/volume fills.
const _fill = Color(0xFFEEEEEE);
// Footprint reserved on the left for the pinned volume slider.
const _volumeGutter = 72.0;

// The three distinct Now Playing layouts, chosen by the window's aspect ratio.
// - landscape: wide windows — the beautifulfullscreen reference (cover left,
//   details filling the whole remaining width).
// - square:    ~1:1 windows — cover centered on top, details beneath.
// - portrait:  tall windows — the phone layout, designed on its own terms.
enum _NpMode { landscape, square, portrait }

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  // How long the pointer/touch must stay idle before the header fades out and
  // the cursor is hidden.
  static const _idleDelay = Duration(seconds: 3);

  // Whether the UI is "active" (recent pointer activity). While inactive the
  // header fades away (landscape only) and the mouse cursor is hidden.
  bool _uiActive = true;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    // Hide the status/navigation bars (and any OS taskbar) for a fullscreen
    // player; swiping brings them back temporarily (immersiveSticky).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Arm the idle countdown so things hide even without a first interaction.
    _armIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    // Restore the app's normal edge-to-edge chrome on the way out.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleDelay, () {
      if (mounted && _uiActive) setState(() => _uiActive = false);
    });
  }

  // Any pointer movement, hover, or touch: reveal the UI and restart the clock.
  void _onActivity() {
    if (!_uiActive) setState(() => _uiActive = true);
    _armIdleTimer();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final remote = context.watch<RemoteService>();
    final track = player.currentTrack;
    final api = context.read<ApiClient>();

    final size = MediaQuery.of(context).size;
    final isLandscape = size.width / size.height > 1.25;
    // The header only auto-hides in the landscape fullscreen layout; elsewhere
    // it stays put. The cursor hides on inactivity regardless.
    final headerVisible = !isLandscape || _uiActive;

    return MouseRegion(
      // Defer to child widgets' cursors while active; hide entirely when idle.
      cursor: _uiActive ? MouseCursor.defer : SystemMouseCursors.none,
      onHover: (_) => _onActivity(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _onActivity(),
        onPointerMove: (_) => _onActivity(),
        onPointerHover: (_) => _onActivity(),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Blurred cover-art background (blur 30 · brightness ~0.6).
              BlurredBackground(
                imageUrl: track?.coverArtId != null
                    ? api.coverUrl(track!.coverArtId, size: 64)
                    : null,
                darken: 0.4,
              ),

              // Main content.
              SafeArea(
                child: track == null
                    ? const Center(
                        child: Text('Nothing playing',
                            style: TextStyle(color: Colors.white70)))
                    : LayoutBuilder(
                        builder: (context, c) {
                          final ratio = c.maxWidth / c.maxHeight;
                          // Wide → landscape (reference), tall → portrait,
                          // in-between → square.
                          if (ratio > 1.25) {
                            return _HorizontalLayout(track: track, api: api);
                          }
                          if (ratio < 0.85) {
                            return _VerticalLayout(track: track, api: api);
                          }
                          return _SquareLayout(track: track, api: api);
                        },
                      ),
              ),

              // Vertical volume slider, pinned to the left edge — landscape
              // only. In square/portrait the volume moves to a horizontal
              // slider at the bottom of the details column.
              if (track != null && isLandscape)
                const Positioned(
                  left: 14,
                  top: 0,
                  bottom: 0,
                  child: Center(child: _VolumeSlider()),
                ),

              // Top bar (back + queue/devices) — kept for in-app navigation.
              // Fades out on inactivity in landscape; taps/moves bring it back.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !headerVisible,
                  child: AnimatedOpacity(
                    opacity: headerVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down,
                                  color: Colors.white, size: 28),
                              onPressed: () => Navigator.pop(context),
                            ),
                            if (remote.isRemote)
                              Chip(
                                avatar: const Icon(Icons.speaker_group,
                                    size: 14, color: Colors.white70),
                                label: Text(remote.activeDeviceName,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12)),
                                backgroundColor: Colors.white12,
                                side: BorderSide.none,
                              ),
                            const Spacer(),
                            if (track != null)
                              IconButton(
                                icon: const Icon(Icons.playlist_add,
                                    color: Colors.white70),
                                onPressed: () =>
                                    addToPlaylistFlow(context, track),
                              ),
                            IconButton(
                              icon: const Icon(Icons.playlist_play,
                                  color: Colors.white70),
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const QueueScreen())),
                            ),
                            IconButton(
                              icon: const Icon(Icons.devices_outlined,
                                  color: Colors.white70),
                              onPressed: () => showDevicePicker(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Up Next preview (reference's next-music layer).
              Positioned(
                top: MediaQuery.of(context).padding.top + 56,
                right: 16,
                child: _UpNextPreview(api: api),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Everything sizes off the window itself (both dimensions), never fixed pixels.
// Scale is the window measured against a reference layout, so a small window —
// even a wide-but-short 16:9 one — shrinks type/cover/controls together and the
// title keeps its room instead of getting clipped.
// Capped at 1.0 so large displays don't blow type/controls up past the
// reference size — only smaller windows scale down.
double _scaleFrom(double w, double h, double refW, double refH) =>
    math.min(w / refW, h / refH).clamp(0.4, 1.0).toDouble();

// Landscape: cover on the left, details filling the whole remaining width on
// the right — a faithful clone of the beautifulfullscreen horizontal layout.
// The details column is Expanded (not width-capped) so the title spans every
// pixel left of the right edge. Volume stays as the left vertical slider.
class _HorizontalLayout extends StatelessWidget {
  final Track track;
  final ApiClient api;
  const _HorizontalLayout({required this.track, required this.api});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth - _volumeGutter;
        final scale = _scaleFrom(w, c.maxHeight, 1200, 720);
        // Cover tracks the window (no fixed width): a fraction of height, but
        // never so wide it starves the title of horizontal room. Bounded to the
        // reference's ~340px so it doesn't dominate large displays.
        final coverSize =
            math.min(c.maxHeight * 0.5, w * 0.34).clamp(96.0, 340.0).toDouble();
        return Padding(
          // Symmetric vertical padding so the content stays truly centered
          // whether or not the (overlaid, auto-hiding) header is showing.
          padding: EdgeInsets.only(
              left: _volumeGutter, right: 48 * scale, top: 16, bottom: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _CoverArt(track: track, api: api, size: coverSize),
              SizedBox(width: 44 * scale),
              // Fill the entire remaining width — the title stretches across it.
              Expanded(
                child: _Details(
                    track: track,
                    mode: _NpMode.landscape,
                    centered: false,
                    scale: scale),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Square (~1:1): everything centered — cover on top, details beneath.
class _SquareLayout extends StatelessWidget {
  final Track track;
  final ApiClient api;
  const _SquareLayout({required this.track, required this.api});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final scale = _scaleFrom(c.maxWidth, c.maxHeight, 640, 640);
        final coverSize = math
            .min(c.maxWidth * 0.52, c.maxHeight * 0.44)
            .clamp(96.0, 560.0)
            .toDouble();
        return Padding(
          padding: EdgeInsets.symmetric(
              horizontal: 24 * scale, vertical: kToolbarHeight * 0.5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _CoverArt(track: track, api: api, size: coverSize),
              SizedBox(height: 28 * scale),
              _Details(
                  track: track,
                  mode: _NpMode.square,
                  centered: true,
                  scale: scale),
            ],
          ),
        );
      },
    );
  }
}

// Portrait (phone): a big near-full-width cover centered above the details, the
// whole block vertically centered.
class _VerticalLayout extends StatelessWidget {
  final Track track;
  final ApiClient api;
  const _VerticalLayout({required this.track, required this.api});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final scale = _scaleFrom(c.maxWidth, c.maxHeight, 420, 820);
        final coverSize = math
            .min(c.maxWidth * 0.86, c.maxHeight * 0.46)
            .clamp(96.0, 560.0)
            .toDouble();
        return Padding(
          // Symmetric vertical padding keeps the centered block truly centered
          // regardless of the overlaid header.
          padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              _CoverArt(track: track, api: api, size: coverSize),
              SizedBox(height: 36 * scale),
              _Details(
                  track: track,
                  mode: _NpMode.portrait,
                  centered: true,
                  scale: scale),
              const Spacer(),
            ],
          ),
        );
      },
    );
  }
}

// Title + artist, then the controller. (Volume lives in the left vertical
// slider in landscape only; square/portrait have no volume control here.)
class _Details extends StatelessWidget {
  final Track track;
  final _NpMode mode;
  final bool centered;
  final double scale;
  const _Details({
    required this.track,
    required this.mode,
    required this.centered,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        _TrackInfo(track: track, mode: mode, centered: centered, scale: scale),
        SizedBox(height: 18 * scale),
        _Controller(track: track, centered: centered, scale: scale),
      ],
    );
  }
}

class _CoverArt extends StatelessWidget {
  final Track track;
  final ApiClient api;
  final double size;
  const _CoverArt({required this.track, required this.api, required this.size});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'now-playing-cover',
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: Container(
          key: ValueKey(track.coverArtId),
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            // Soft down-right drop shadow (reference's blurred shadow layer).
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 24,
                offset: const Offset(6, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: track.coverArtId != null
                ? CachedNetworkImage(
                    imageUrl: api.coverUrl(track.coverArtId, size: 512),
                    fit: BoxFit.cover,
                  )
                : Container(
                    color: Colors.white10,
                    child: const Icon(Icons.music_note,
                        size: 96, color: Colors.white24),
                  ),
          ),
        ),
      ),
    );
  }
}

// Big black-weight title (scaled by length, like the reference) + artist row
// prefixed with a person glyph.
class _TrackInfo extends StatelessWidget {
  final Track track;
  final _NpMode mode;
  final bool centered;
  final double scale;
  const _TrackInfo({
    required this.track,
    required this.mode,
    required this.centered,
    required this.scale,
  });

  // Length-based font tiers, mirroring the reference's approach but tuned per
  // layout: the shorter the title, the bigger it gets.
  double _titleSize(int len) {
    late final List<double> t;
    switch (mode) {
      case _NpMode.landscape:
        t = const [54.0, 46.0, 40.0, 34.0];
        break;
      case _NpMode.square:
        t = const [52.0, 44.0, 38.0, 32.0];
        break;
      case _NpMode.portrait:
        t = const [42.0, 36.0, 31.0, 27.0];
        break;
    }
    if (len > 45) return t[3];
    if (len > 35) return t[2];
    if (len > 28) return t[1];
    return t[0];
  }

  @override
  Widget build(BuildContext context) {
    final titleSize = _titleSize(track.title.length) * scale;
    final artistSize = (titleSize * 0.42).clamp(13.0, 30.0);
    final artist = track.artist?.trim() ?? '';
    final hasArtist = artist.isNotEmpty;
    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Full title spanning the entire available width, scrolled horizontally
        // (marquee) when too long to fit instead of being clipped.
        SizedBox(
          width: double.infinity,
          child: MarqueeText(
            track.title,
            velocity: 30,
            textAlign: centered ? TextAlign.center : TextAlign.left,
            style: TextStyle(
              color: Colors.white,
              fontSize: titleSize,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
        ),
        // Only show the artist row when there's an artist.
        if (hasArtist) ...[
          SizedBox(height: 8 * scale),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment:
                centered ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(Icons.person, color: Colors.white70, size: artistSize),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: artistSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString();
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

// Advanced controller: [shuffle · repeat] | [prev · play · next] | [heart],
// with the progress bar beneath. Constrained to ~420px like the reference.
class _Controller extends StatelessWidget {
  final Track track;
  final bool centered;
  final double scale;
  const _Controller(
      {required this.track, required this.centered, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final favs = context.watch<FavoritesService>();
    final liked = favs.isLiked(track.id);
    final showBuffer = context.watch<SettingsService>().showLoadingIndicator &&
        player.isBuffering;

    final repeatActive = player.loopMode != LoopMode.off;
    final repeatIcon = player.loopMode == LoopMode.one
        ? Icons.repeat_one_rounded
        : Icons.repeat_rounded;

    // The play button footprint (_FlatIcon = icon + 6px padding all around). The
    // buffering spinner uses the exact same box so the controls don't shrink /
    // jump when the loading indicator flickers on and off.
    final playSize = 46 * scale;
    final playBox = playSize + 12;
    final playPause = showBuffer
        ? SizedBox(
            width: playBox,
            height: playBox,
            child: Center(
              child: SizedBox(
                width: playSize * 0.72,
                height: playSize * 0.72,
                child: const CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              ),
            ),
          )
        : _FlatIcon(
            icon: player.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            size: playSize,
            onTap: player.togglePlay,
          );

    final controls = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 420 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Left: shuffle + repeat (with the reference's active dot).
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    _ToggleIcon(
                      icon: Icons.shuffle_rounded,
                      active: player.shuffleEnabled,
                      size: 24 * scale,
                      onTap: player.toggleShuffle,
                    ),
                    _ToggleIcon(
                      icon: repeatIcon,
                      active: repeatActive,
                      size: 24 * scale,
                      onTap: player.cycleLoop,
                    ),
                  ],
                ),
              ),
              // Center: transport.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FlatIcon(
                      icon: Icons.skip_previous_rounded,
                      size: 34 * scale,
                      onTap: player.previous),
                  const SizedBox(width: 6),
                  playPause,
                  const SizedBox(width: 6),
                  _FlatIcon(
                      icon: Icons.skip_next_rounded,
                      size: 34 * scale,
                      onTap: player.next),
                ],
              ),
              // Right: heart.
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _FlatIcon(
                      icon: liked ? Icons.favorite : Icons.favorite_border,
                      size: 24 * scale,
                      color: liked ? Colors.redAccent : Colors.white,
                      onTap: () => favs.toggle(track.id),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12 * scale),
          const _ProgressBar(),
        ],
      ),
    );

    // Centered layouts center the (max-width-capped) controller; landscape
    // keeps it flush to the left of the details column.
    return Align(
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      child: controls,
    );
  }
}

// Flat, borderless icon button (reference uses transparent currentColor icons).
class _FlatIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback onTap;
  const _FlatIcon({
    required this.icon,
    required this.size,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: size * 0.8,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}

// Toggle icon with the reference's under-dot: when active it lifts slightly and
// shows a small dot beneath.
class _ToggleIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final double size;
  final VoidCallback onTap;
  const _ToggleIcon(
      {required this.icon,
      required this.active,
      required this.onTap,
      this.size = 24});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSlide(
              offset: active ? const Offset(0, -0.12) : Offset.zero,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: Icon(icon,
                  size: size, color: active ? Colors.white : Colors.white38),
            ),
            const SizedBox(height: 2),
            AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Elapsed | thin bar | duration (reference progressbar).
class _ProgressBar extends StatefulWidget {
  const _ProgressBar();

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  bool _dragging = false;
  double _dragValue = 0;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final pos = player.position;
    final dur = player.duration ?? Duration.zero;
    final maxMs = dur.inMilliseconds.toDouble();
    final progress = maxMs > 0
        ? (_dragging ? _dragValue : pos.inMilliseconds / maxMs).clamp(0.0, 1.0)
        : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            _dragging
                ? _fmt(Duration(milliseconds: (_dragValue * maxMs).round()))
                : _fmt(pos),
            style: const TextStyle(color: _fill, fontSize: 12),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 18,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: maxMs > 0
                      ? (d) => setState(() {
                            _dragging = true;
                            _dragValue =
                                (d.localPosition.dx / width).clamp(0.0, 1.0);
                          })
                      : null,
                  onHorizontalDragUpdate: maxMs > 0
                      ? (d) => setState(() => _dragValue =
                          (d.localPosition.dx / width).clamp(0.0, 1.0))
                      : null,
                  onHorizontalDragEnd: maxMs > 0
                      ? (d) {
                          player.seek(Duration(
                              milliseconds: (_dragValue * maxMs).round()));
                          setState(() => _dragging = false);
                        }
                      : null,
                  onTapUp: maxMs > 0
                      ? (d) {
                          final frac =
                              (d.localPosition.dx / width).clamp(0.0, 1.0);
                          player.seek(
                              Duration(milliseconds: (frac * maxMs).round()));
                        }
                      : null,
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 6,
                        child: Stack(
                          children: [
                            Container(
                                color: Colors.white.withValues(alpha: 0.19)),
                            FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _fill,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.8),
                                      blurRadius: 12,
                                      offset: const Offset(4, 0),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          maxMs > 0 ? _fmt(dur) : '--:--',
          style: const TextStyle(color: _fill, fontSize: 12),
        ),
      ],
    );
  }
}

// Vertical volume slider pinned to the left edge (reference VolumeController):
// icon on top, tall thin track filling from the bottom. Controls the active
// target's app-internal volume (local or remote).
class _VolumeSlider extends StatefulWidget {
  const _VolumeSlider();

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  static const double _trackHeight = 180;
  double? _dragValue;

  void _setFromLocalY(double dy, PlayerService player, {bool persist = false}) {
    final v = (1 - dy / _trackHeight).clamp(0.0, 1.0);
    setState(() => _dragValue = persist ? null : v);
    player.setVolume(v, persist: persist);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final value = (_dragValue ?? player.volume).clamp(0.0, 1.0);
    final icon = value <= 0.001
        ? Icons.volume_off_rounded
        : value < 0.5
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _fill, size: 24),
        const SizedBox(height: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) =>
              _setFromLocalY(d.localPosition.dy, player),
          onVerticalDragEnd: (d) =>
              player.setVolume(value.toDouble(), persist: true),
          onTapDown: (d) =>
              _setFromLocalY(d.localPosition.dy, player, persist: true),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 6,
              height: _trackHeight,
              child: Stack(
                children: [
                  Container(color: Colors.white.withValues(alpha: 0.19)),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: value,
                      widthFactor: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _fill,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.8),
                              blurRadius: 12,
                              offset: const Offset(4, 0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Horizontal volume slider used at the bottom of the square/portrait layouts:
// a volume icon followed by a thin track filling from the left. Constrained to
// the same ~420px as the controller so the two line up.
class _UpNextPreview extends StatefulWidget {
  final ApiClient api;
  const _UpNextPreview({required this.api});

  @override
  State<_UpNextPreview> createState() => _UpNextPreviewState();
}

class _UpNextPreviewState extends State<_UpNextPreview> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final queue = player.queue;
    final idx = player.currentIndex;
    if (idx == null || idx + 1 >= queue.length) return const SizedBox.shrink();

    final next = queue[idx + 1];
    final dur = player.duration;
    final pos = player.position;
    final show = dur != null &&
        dur.inMilliseconds > 0 &&
        pos.inMilliseconds > dur.inMilliseconds * 0.8;

    final artist = next.artist?.trim() ?? '';
    final subtitle = artist.isEmpty ? next.title : '${next.title} · $artist';
    // Reference has no background box: plain right-aligned text + a small
    // square cover, over the blurred backdrop. Soft shadows keep it legible.
    const shadows = [Shadow(color: Colors.black87, blurRadius: 8)];

    return AnimatedSlide(
      offset: show ? Offset.zero : const Offset(0.6, 0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: show ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 500),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Up next',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                        shadows: shadows,
                      )),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        height: 1.1,
                        shadows: shadows,
                      )),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 46,
                height: 46,
                child: next.coverArtId != null
                    ? CachedNetworkImage(
                        imageUrl:
                            widget.api.coverUrl(next.coverArtId, size: 128),
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: Colors.white10,
                        child: const Icon(Icons.music_note,
                            size: 22, color: Colors.white24),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
