import '../../../core/source/models.dart';

enum PlaybackPhase {
  idle,
  resolving,
  opening,
  playing,
  buffering,
  recovering,
  failed,
}

class PlaybackState {
  const PlaybackState({
    required this.phase,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.message,
    this.attempt = 0,
    this.selectedTrack,
    this.manualQualityLocked = false,
    this.pendingSeekTarget,
    this.seeking = false,
  });

  const PlaybackState.idle() : this(phase: PlaybackPhase.idle);

  final PlaybackPhase phase;
  final Duration position;
  final Duration duration;

  /// 缓冲末端在片子里的位置。进度条后面那条白条画到这儿。
  final Duration buffered;

  final String? message;
  final int attempt;
  final VideoTrack? selectedTrack;
  final bool manualQualityLocked;
  final Duration? pendingSeekTarget;
  final bool seeking;

  PlaybackState copyWith({
    PlaybackPhase? phase,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    String? message,
    int? attempt,
    VideoTrack? selectedTrack,
    bool? manualQualityLocked,
    Duration? pendingSeekTarget,
    bool clearPendingSeekTarget = false,
    bool? seeking,
  }) =>
      PlaybackState(
        phase: phase ?? this.phase,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        buffered: buffered ?? this.buffered,
        message: message,
        attempt: attempt ?? this.attempt,
        selectedTrack: selectedTrack ?? this.selectedTrack,
        manualQualityLocked: manualQualityLocked ?? this.manualQualityLocked,
        pendingSeekTarget: clearPendingSeekTarget
            ? null
            : pendingSeekTarget ?? this.pendingSeekTarget,
        seeking: seeking ?? this.seeking,
      );
}
