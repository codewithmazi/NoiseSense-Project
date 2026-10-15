import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../../domain/acoustics/pcm_source.dart';
import 'pcm16_decoder.dart';

/// The phone microphone, as a stream of raw 16-bit samples.
///
/// The configuration is what makes the numbers usable as measurements. A
/// phone's default recording path is tuned for calls: automatic gain control
/// raises quiet rooms and lowers loud streets, and noise suppression removes
/// steady sounds such as traffic. Both would destroy the quantity being
/// measured. So:
///
/// * the `VOICE_RECOGNITION` source is requested. The Android 10 CDD
///   (s. 5.4.2) requires devices to disable noise reduction and automatic gain
///   control by default on that source, and it is the source the CDD's
///   sensitivity figure, used for the nominal calibration, is specified for.
///   `UNPROCESSED` was considered and rejected: support for it is optional, so
///   it cannot be relied on.
/// * `autoGain`, `noiseSuppress` and `echoCancel` are also turned off
///   explicitly, so the plugin does not add the processing back.
/// * 48 kHz mono PCM. The CDD requires 48 kHz capture without up-sampling,
///   and the A-weighting filter needs a rate above 24.4 kHz.
///
/// These settings ask; they cannot verify. A manufacturer that ignores the CDD
/// would still return processed audio, which is one reason experiment M6
/// measures the device's actual response.
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
