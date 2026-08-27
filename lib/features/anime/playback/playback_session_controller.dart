import 'dart:async';

import '../../../core/net/url_redaction.dart';
import '../../../core/source/models.dart';
import 'playback_messages.dart';
import 'playback_state.dart';
import 'player_adapter.dart';

abstract interface class PlaybackTrackProvider {
  Future<List<VideoTrack>> refresh();

  VideoTrack? matchRefreshed(
    VideoTrack current,
    List<VideoTrack> refreshed,
  );

  VideoTrack? lowerQuality(
    VideoTrack current,
    List<VideoTrack> available,
  );

  VideoTrack? alternateLine(
    VideoTrack current,
    List<VideoTrack> available,
  );
}

typedef PlaybackDelay = Future<void> Function(Duration duration);

class PlaybackSessionController {
  PlaybackSessionController({
    required PlayerAdapter player,
    required PlaybackTrackProvider tracks,
    required this.messages,
    PlaybackDelay? delay,
    this.onProgress,
    this.onPaused,
    this.stallThreshold = const Duration(seconds: 8),
    this.coldStartStallThreshold = const Duration(seconds: 24),
    this.stableResetThreshold = const Duration(seconds: 15),
    this.resumeConfirmationTimeout = const Duration(seconds: 20),
  })  : _player = player,
        _tracks = tracks,
        _delay = delay ?? Future<void>.delayed {
    _subscriptions.addAll([
      _player.playing.listen(_onPlaying),
      _player.buffering.listen(_onBuffering),
      _player.position.listen(_onPosition),
      _player.duration.listen(_onDuration),
      _player.completed.listen(_onCompleted),
      _player.errors.listen(_onError),
    ]);
  }

  static const _backoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];
  static const _seekConfirmationTolerance = Duration(seconds: 3);
  static const _seekConfirmationAheadTolerance = Duration(seconds: 10);

  final PlayerAdapter _player;
  final PlaybackTrackProvider _tracks;
  final PlaybackDelay _delay;

  /// 可写:语言切换后播放页会重新灌一份,不用重建整个会话。
  PlaybackMessages messages;

  final void Function(Duration position, Duration duration)? onProgress;
  final void Function()? onPaused;
  final Duration stallThreshold;

  /// 开播(还没出过第一帧、也没有待确认的 seek)时的卡顿阈值。冷启动要串起
  /// 解析清单 → 取密钥 → 拉头几片,慢线路/私有源上 8 秒根本不够;超时就重建解码器
  /// 反而把已经预热的 HLS 会话丢掉,重来一遍更慢,最后走到「播放恢复失败」。
  /// 出过第一帧之后仍用 [stallThreshold],真死流照样能被快速发现。
  final Duration coldStartStallThreshold;
  final Duration stableResetThreshold;

  /// 断点恢复的**确认**窗口。超过它还没落到断点就认命,按当前真实位置继续 ——
  /// 否则进度条会一直停在一个视频根本没到过的时间上。
  final Duration resumeConfirmationTimeout;

  final _states = StreamController<PlaybackState>.broadcast(sync: true);
  final List<StreamSubscription<Object?>> _subscriptions = [];

  PlaybackState _state = const PlaybackState.idle();
  PlaybackState get state => _state;
  Stream<PlaybackState> get states => _states.stream;

  List<VideoTrack> _available = const [];
  VideoTrack? _selected;
  Duration _confirmedPosition = Duration.zero;
  Duration? _pendingSeekTarget;
  Duration _duration = Duration.zero;
  int? _reportedPositionSecond;
  Timer? _stallTimer;
  Timer? _stableTimer;

  /// 已经请求、但还没看到播放器真的落上去的断点。非空期间位置流里那些**在断点
  /// 之前**的取样一律不认:它们是「从头开始播了」的证据,拿它们覆盖
  /// [_confirmedPosition] 会把断点连同历史记录一起清成 0。
  Duration? _resumeTarget;
  Timer? _resumeTimer;
  bool _resumeReissued = false;
  int _generation = 0;
  int _seekGeneration = 0;
  int _recoveryRound = 0;
  bool _recovering = false;
  bool _playing = false;
  bool _startedPlaying = false;
  bool _userPaused = false;
  bool _resumeAfterSeek = false;
  bool _disposed = false;

  Duration get _recoveryPosition => _pendingSeekTarget ?? _confirmedPosition;

  Future<void> start(
    List<VideoTrack> available,
    VideoTrack selected, {
    Duration initialPosition = Duration.zero,
  }) async {
    final generation = ++_generation;
    _seekGeneration++;
    _cancelTimers();
    _recovering = false;
    _userPaused = false;
    _startedPlaying = false;
    _resumeAfterSeek = false;
    _pendingSeekTarget = null;
    _clearResume();
    _recoveryRound = 0;
    final knownDuration = _duration;
    _confirmedPosition = _resumePosition(initialPosition, knownDuration);
    _duration = Duration.zero;
    _reportedPositionSecond = null;
    _available = List.unmodifiable(available);
    _selected = selected;
    _emit(PlaybackState(
      phase: PlaybackPhase.resolving,
      position: _confirmedPosition,
      selectedTrack: selected,
    ));
    try {
      await _open(
        selected,
        generation: generation,
        resume: _confirmedPosition > Duration.zero,
      );
    } catch (error) {
      if (_isCurrent(generation)) await _recover(error, generation);
    }
  }

  void setUserPaused(bool paused) {
    _userPaused = paused;
    if (paused) {
      _resumeAfterSeek = false;
      _stallTimer?.cancel();
      unawaited(_player.pause());
    }
  }

  Future<void> seekTo(
    Duration target, {
    required bool resumeAfterSeek,
  }) async {
    if (_disposed || _selected == null) return;
    final bounded = target < Duration.zero
        ? Duration.zero
        : _duration > Duration.zero && target > _duration
            ? _duration
            : target;
    final seekGeneration = ++_seekGeneration;
    // 用户自己点了个位置,断点恢复到此为止 —— 再去追那个旧断点就是跟用户对着干。
    _clearResume();
    _pendingSeekTarget = bounded;
    _resumeAfterSeek = resumeAfterSeek;
    _stallTimer?.cancel();
    _stableTimer?.cancel();
    _emit(_state.copyWith(
      position: bounded,
      pendingSeekTarget: bounded,
      seeking: true,
    ));

    await _player.pause();
    if (_disposed || seekGeneration != _seekGeneration) return;
    await _player.seek(bounded);
  }

  void setManualQualityLocked(bool locked) {
    _emit(_state.copyWith(manualQualityLocked: locked));
  }

  Future<void> _open(
    VideoTrack track, {
    required int generation,
    required bool resume,
  }) async {
    if (!_isCurrent(generation)) return;
    _selected = track;
    final resumePosition = _recoveryPosition;
    final startAt =
        resume && resumePosition > Duration.zero ? resumePosition : Duration.zero;
    _emit(_state.copyWith(
      phase: PlaybackPhase.opening,
      position: resumePosition,
      duration: _duration,
      selectedTrack: track,
    ));
    // 断点交给播放器在打开文件的那一刻自己落上去,而不是打开之后再补一发 seek ——
    // 后者在文件还没就绪时会被静默丢掉,画面从 0 开始播。[_armResume] 是这条路
    // 万一还是没走通时的兜底。
    _armResume(startAt, generation);
    await _player.open(track, startAt: startAt);
  }

  /// 记下这次开流要落到的断点,并给它一个认命期限。
  void _armResume(Duration target, int generation) {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _resumeReissued = false;
    if (target <= Duration.zero) {
      _resumeTarget = null;
      return;
    }
    _resumeTarget = target;
    _resumeTimer = Timer(resumeConfirmationTimeout, () {
      if (_isCurrent(generation)) _clearResume();
    });
  }

  void _clearResume() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _resumeTarget = null;
    _resumeReissued = false;
  }

  /// 时长到手 = libmpv 真的把文件打开了。如果这时候还没落到断点,补发一次 seek:
  /// 此刻发出去的一定会被接受。只补一次,补不上就让 [resumeConfirmationTimeout]
  /// 去认命,免得和播放器来回拉锯。
  void _reissueResumeIfNeeded(Duration duration) {
    final target = _resumeTarget;
    if (target == null || _resumeReissued) return;
    if (duration <= Duration.zero || _pendingSeekTarget != null) return;
    if (target >= duration) {
      _clearResume();
      return;
    }
    _resumeReissued = true;
    unawaited(_player.seek(target));
  }

  void _onPlaying(bool playing) {
    if (_disposed) return;
    if (_pendingSeekTarget != null) {
      _playing = false;
      _stallTimer?.cancel();
      return;
    }
    final wasPlaying = _playing;
    _playing = playing;
    if (!playing) {
      if (wasPlaying) onPaused?.call();
      return;
    }
    _startedPlaying = true;
    _stallTimer?.cancel();
    _emit(_state.copyWith(
      phase: PlaybackPhase.playing,
      position: _confirmedPosition,
      duration: _duration,
      selectedTrack: _selected,
    ));
    _stableTimer?.cancel();
    final generation = _generation;
    _stableTimer = Timer(stableResetThreshold, () {
      if (_isCurrent(generation) && _state.phase == PlaybackPhase.playing) {
        _recoveryRound = 0;
      }
    });
  }

  void _onBuffering(bool buffering) {
    if (_disposed) return;
    final pendingSeek = _pendingSeekTarget != null;
    if (_userPaused && !pendingSeek) {
      _stallTimer?.cancel();
      return;
    }
    if (!buffering) {
      _stallTimer?.cancel();
      if (pendingSeek) return;
      if (_playing && _state.phase == PlaybackPhase.buffering) {
        _emit(_state.copyWith(
          phase: PlaybackPhase.playing,
          position: _confirmedPosition,
          duration: _duration,
          selectedTrack: _selected,
        ));
      }
      return;
    }
    _emit(_state.copyWith(
      phase: PlaybackPhase.buffering,
      position: _recoveryPosition,
      duration: _duration,
      selectedTrack: _selected,
    ));
    _stallTimer?.cancel();
    final generation = _generation;
    final coldStart = !_startedPlaying && _pendingSeekTarget == null;
    _stallTimer = Timer(coldStart ? coldStartStallThreshold : stallThreshold,
        () {
      if (_isCurrent(generation) &&
          (!_userPaused || _pendingSeekTarget != null)) {
        unawaited(_recover(StateError(messages.bufferTimeout), generation));
      }
    });
  }

  void _onPosition(Duration position) {
    if (_disposed) return;
    final pendingTarget = _pendingSeekTarget;
    if (pendingTarget != null) {
      if (position == Duration.zero && pendingTarget > Duration.zero) return;
      final delta = position - pendingTarget;
      if (delta < -_seekConfirmationTolerance ||
          delta > _seekConfirmationAheadTolerance) {
        return;
      }

      final seekGeneration = _seekGeneration;
      final shouldResume = _resumeAfterSeek;
      _confirmedPosition = position;
      _pendingSeekTarget = null;
      _resumeAfterSeek = false;
      _clearResume();
      _emit(_state.copyWith(
        position: position,
        clearPendingSeekTarget: true,
        seeking: false,
      ));
      _reportProgress(position);
      if (shouldResume) {
        unawaited(_playAfterSeekConfirmation(seekGeneration));
      }
      return;
    }

    final resumeTarget = _resumeTarget;
    if (resumeTarget != null) {
      // 还没走到断点:这一帧说明播放器是从头开始放的。既不能拿它覆盖断点,
      // 也不能报进度 —— 一报就把历史里那个真进度写成 0 了。
      if (position < resumeTarget - _seekConfirmationTolerance) return;
      _clearResume();
    }

    if (position == Duration.zero && _confirmedPosition > Duration.zero) return;

    _confirmedPosition = position;
    // 播放中的位置也要发出去,否则进度条只有在换阶段(缓冲开/停、播放暂停)时
    // 才动一下 —— 中间那段是**停着的**。
    // 整秒才发一次:mpv 大约每 100ms 报一次位置,条也就一秒挪一格,
    // 全发上去等于白搭十倍的重建。
    final advanced = _reportedPositionSecond != position.inSeconds;
    _reportProgress(position);
    if (advanced) _emit(_state.copyWith(position: position));
  }

  void _reportProgress(Duration position) {
    final second = position.inSeconds;
    if (_reportedPositionSecond == second) return;
    _reportedPositionSecond = second;
    onProgress?.call(
      Duration(seconds: second),
      Duration(seconds: _duration.inSeconds),
    );
  }

  Future<void> _playAfterSeekConfirmation(int seekGeneration) async {
    if (_disposed || seekGeneration != _seekGeneration) return;
    await _player.play();
  }

  void _onDuration(Duration duration) {
    if (_disposed) return;
    _duration = duration;
    _emit(_state.copyWith(duration: duration));
    _reissueResumeIfNeeded(duration);
  }

  void _onCompleted(bool completed) {
    if (!completed || _disposed || _pendingSeekTarget != null) return;
    _cancelTimers();
    _emit(_state.copyWith(
      phase: PlaybackPhase.idle,
      position: _confirmedPosition,
      duration: _duration,
      selectedTrack: _selected,
    ));
  }

  void _onError(Object error) {
    if (_disposed || (_userPaused && _pendingSeekTarget == null)) return;
    unawaited(_recover(error, _generation));
  }

  Future<void> _recover(Object cause, int generation) async {
    if (_recovering || !_isCurrent(generation)) return;
    final current = _selected;
    if (current == null) return;
    _recovering = true;
    _cancelTimers();
    Object lastError = cause;
    try {
      for (var round = _recoveryRound; round < _backoff.length; round++) {
        _emit(_state.copyWith(
          phase: PlaybackPhase.recovering,
          position: _recoveryPosition,
          duration: _duration,
          attempt: round + 1,
          selectedTrack: _selected,
          message: messages.recovering(round + 1, _backoff.length),
        ));
        await _delay(_backoff[round]);
        if (!_isCurrent(generation)) return;

        if (round == 0) {
          try {
            final resumePosition = _recoveryPosition;
            // 重建后的落点和开播一样要确认:确认不到就把位置流里那些「从头放」
            // 的取样挡在外面,并在时长到手时补一发 seek。
            _armResume(resumePosition, generation);
            await _player.rebuildDecoder(resumePosition);
            if (!_isCurrent(generation)) return;
            _recoveryRound = round + 1;
            return;
          } catch (error) {
            lastError = error;
            continue;
          }
        }

        final candidates = switch (round) {
          1 => <Future<VideoTrack?> Function()>[
              () async {
                final refreshed = await _tracks.refresh();
                _available = List.unmodifiable(refreshed);
                return _selected == null
                    ? null
                    : _tracks.matchRefreshed(_selected!, _available);
              },
            ],
          _ => <Future<VideoTrack?> Function()>[
              () async => _state.manualQualityLocked || _selected == null
                  ? null
                  : _tracks.lowerQuality(_selected!, _available),
              () async => _selected == null
                  ? null
                  : _tracks.alternateLine(_selected!, _available),
            ],
        };

        for (final candidate in candidates) {
          if (!_isCurrent(generation)) return;
          try {
            final track = await candidate();
            if (track == null || !_isCurrent(generation)) continue;
            await _open(track, generation: generation, resume: true);
            if (!_isCurrent(generation)) return;
            _recoveryRound = round + 1;
            return;
          } catch (error) {
            lastError = error;
          }
        }
      }
      if (_isCurrent(generation)) {
        _emit(PlaybackState(
          phase: PlaybackPhase.failed,
          position: _recoveryPosition,
          duration: _duration,
          attempt: _backoff.length,
          selectedTrack: _selected,
          manualQualityLocked: _state.manualQualityLocked,
          pendingSeekTarget: _pendingSeekTarget,
          seeking: _pendingSeekTarget != null,
          // 播放地址常带签名参数,原始异常会带出完整 URL,不能直接进 UI。
          message: messages.recoverFailed(redactUrlCredentials('$lastError')),
        ));
      }
    } finally {
      _recovering = false;
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Duration _resumePosition(Duration requested, Duration knownDuration) {
    if (requested <= Duration.zero) return Duration.zero;
    if (knownDuration > Duration.zero &&
        knownDuration - requested <= const Duration(seconds: 10)) {
      return Duration.zero;
    }
    return requested;
  }

  void _emit(PlaybackState next) {
    if (_disposed) return;
    _state = next;
    _states.add(next);
  }

  void _cancelTimers() {
    _stallTimer?.cancel();
    _stableTimer?.cancel();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _seekGeneration++;
    _cancelTimers();
    _clearResume();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _states.close();
    await _player.dispose();
  }
}
