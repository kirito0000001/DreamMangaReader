import '../../../core/source/models.dart';
import 'subtitle_option.dart';

abstract interface class PlayerAdapter {
  Stream<bool> get playing;
  Stream<bool> get buffering;
  Stream<Duration> get position;
  Stream<Duration> get duration;

  /// 已经缓冲到片子的哪个时间点 —— 绝对位置,和 [duration] 同一把尺子,
  /// 可以直接画成进度条后面那条白条。
  Stream<Duration> get buffer;

  Stream<bool> get completed;
  Stream<Object> get errors;

  /// 流里**自带**的字幕轨道,换集/换线路后会重发。源另给的外挂字幕不走这条,
  /// 由播放页从 [VideoTrack.subtitles] 合进同一份列表。
  Stream<List<SubtitleOption>> get subtitles;

  /// 打开一条流。
  ///
  /// [startAt] > 0 时要求**从这个位置开机**,而不是打开之后再 seek 过去:libmpv 的
  /// loadfile 是异步的,open() 返回时文件常常还没真正打开,紧跟着发过去的 seek 会被
  /// 静默丢掉 —— 画面从 0 开始播,断点就这么没了。
  Future<void> open(VideoTrack track, {Duration startAt = Duration.zero});
  Future<void> rebuildDecoder(Duration resumePosition);
  Future<void> seek(Duration position);
  Future<void> play();
  Future<void> pause();
  Future<void> setRate(double rate);

  /// 0–100,跟 media_kit 一致。这是**应用内**音量,不动系统音量。
  Future<void> setVolume(double volume);

  Future<void> setSubtitle(SubtitleOption option);
  Future<void> dispose();
}
