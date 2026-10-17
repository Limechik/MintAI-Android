// Тонкая C-обёртка над VoxSynth для вызова из Dart через dart:ffi.
#include <stdlib.h>
#include "FormantCore.h"
#include "Phonemes.h"

// Возвращает число сэмплов (16-бит моно PCM) или 0 при ошибке. *out освобождать через vox_free.
// pitch — множитель основного тона, formant — множитель формант (женский голос: ~1.7 / ~1.15).
int32_t vox_synth(const uint32_t *text, int32_t n, float speed, float pitch,
                  float formant, int32_t rate, int16_t **out) {
    *out = NULL;
    if (n <= 0) return 0;
    size_t segCap = 8 * (size_t)n + 16;
    FCSegment *segs = calloc(segCap, sizeof(FCSegment));
    if (!segs) return 0;
    size_t ns = PHTextToSegments(text, (size_t)n, segs, segCap, speed > 0 ? speed : 1.0f);
    for (size_t i = 0; i < ns; i++) {
        segs[i].f0 *= pitch;
        segs[i].f1 *= formant; segs[i].f2 *= formant; segs[i].f3 *= formant;
    }
    size_t cap = FCTotalSamples(segs, ns, (float)rate) + 100;
    int16_t *pcm = calloc(cap, sizeof(int16_t));
    if (!pcm) { free(segs); return 0; }
    size_t samples = FCRender(segs, ns, pcm, cap, (float)rate);
    free(segs);
    *out = pcm;
    return (int32_t)samples;
}

void vox_free(void *p) { free(p); }
