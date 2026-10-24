import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../../domain/acoustics/pcm_source.dart';
import 'pcm16_decoder.dart';

/// The phone microphone, as a stream of raw 16-bit samples.
class MicrophonePcmSource implements PcmSource {
  MicrophonePcmSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final Pcm16Decoder _decoder = Pcm16Decoder();
  StreamSubscription<Uint8List>? _subscription;
  StreamController<Int16List>? _output;

  @override
  int get sampleRate => 48000;

  @override
  Future<bool> ensurePermission() => _recorder.hasPermission();

  @override
  Future<Stream<Int16List>> start() async {
    await stop();
    _decoder.reset();
    final bytes = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        androidConfig: const AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceRecognition,
        ),
      ),
    );
    final output = StreamController<Int16List>();
    _output = output;
    _subscription = bytes.listen(
      (chunk) => output.add(_decoder.convert(chunk)),
      onError: output.addError,
      onDone: output.close,
    );
    return output.stream;
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _output?.close();
    _output = null;
    if (await _recorder.isRecording()) await _recorder.stop();
  }
}
