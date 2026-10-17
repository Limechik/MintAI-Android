import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// Озвучка через VoxSynth (формантный синтез русской речи, GPL-3.0).
typedef _SynthC = Int32 Function(Pointer<Uint32>, Int32, Float, Float, Float,
    Int32, Pointer<Pointer<Int16>>);
typedef _SynthD = int Function(
    Pointer<Uint32>, int, double, double, double, int, Pointer<Pointer<Int16>>);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);

const _rate = 22050;

/// Синтез в отдельном изоляте: текст -> WAV (16 бит, моно, 22050 Гц).
Uint8List _synth(String text, double speed, double pitch, double formant) {
  final lib = DynamicLibrary.open('libvoxsynth.so');
  final synth = lib.lookupFunction<_SynthC, _SynthD>('vox_synth');
  final free = lib.lookupFunction<_FreeC, _FreeD>('vox_free');

  final clean = text
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'[*_#`>~|\[\]()]'), ' ')
      .toLowerCase();
  final runes = clean.runes.toList();
  if (runes.isEmpty) return Uint8List(0);

  final inp = calloc<Uint32>(runes.length);
  for (var i = 0; i < runes.length; i++) {
    inp[i] = runes[i];
  }
  final out = calloc<Pointer<Int16>>();
  final n = synth(inp, runes.length, speed, pitch, formant, _rate, out);
  calloc.free(inp);
  if (n <= 0) {
    calloc.free(out);
    return Uint8List(0);
  }

  final dataLen = n * 2;
  final wav = Uint8List(44 + dataLen);
  final bd = ByteData.view(wav.buffer);
  void tag(int off, String s) {
    for (var i = 0; i < 4; i++) {
      bd.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bd.setUint32(4, 36 + dataLen, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little); // PCM
  bd.setUint16(22, 1, Endian.little); // моно
  bd.setUint32(24, _rate, Endian.little);
  bd.setUint32(28, _rate * 2, Endian.little);
  bd.setUint16(32, 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bd.setUint32(40, dataLen, Endian.little);
  wav.setRange(44, 44 + dataLen, out.value.cast<Uint8>().asTypedList(dataLen));

  free(out.value.cast<Void>());
  calloc.free(out);
  return wav;
}

class Vox {
  /// Объект, который сейчас озвучивается (для иконки «стоп»).
  static final ValueNotifier<Object?> current = ValueNotifier(null);
  static AudioPlayer? _player;

  static bool get supported => Platform.isAndroid;

  static AudioPlayer get _p =>
      _player ??= AudioPlayer()..onPlayerComplete.listen((_) => current.value = null);

  static Future<void> speak(Object id, String text,
      {bool female = true, double speed = 1.0}) async {
    await stop();
    current.value = id;
    try {
      final wav = await Isolate.run(
          () => _synth(text, speed, female ? 1.7 : 1.0, female ? 1.15 : 1.0));
      if (wav.length <= 44) {
        current.value = null;
        return;
      }
      await _p.play(BytesSource(wav, mimeType: 'audio/wav'));
    } catch (e) {
      current.value = null;
      rethrow;
    }
  }

  static Future<void> stop() async {
    current.value = null;
    await _player?.stop();
  }
}
