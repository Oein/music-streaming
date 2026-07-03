// Non-web stub: native platforms use audio_service for OS media controls.
void initMediaSession({
  required void Function() onPlay,
  required void Function() onPause,
  required void Function() onNext,
  required void Function() onPrevious,
  required void Function(Duration position) onSeek,
}) {}

void setMediaMetadata({
  required String title,
  String? artist,
  String? album,
  String? artworkUrl,
}) {}

void setMediaPlaybackState({required bool playing}) {}

void setMediaPositionState({
  Duration? duration,
  required Duration position,
  double speed = 1.0,
}) {}
