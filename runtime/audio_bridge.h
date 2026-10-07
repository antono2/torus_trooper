// Owns the miniaudio engine and game sound assets behind the V audio interface.
// Supports a null backend for tests without an audio device.
#ifndef TT_AUDIO_BRIDGE_H
#define TT_AUDIO_BRIDGE_H

/* Thin C ownership layer around vendored miniaudio 0.11.25. */
#if defined(_WIN32) && defined(TT_TINYC) && !defined(INITGUID)
#define INITGUID
#endif
#define MA_NO_ENCODING
#define MA_NO_FLAC
#define MA_NO_MP3
#define MA_NO_GENERATION
#define MINIAUDIO_IMPLEMENTATION
#include "../thirdparty/miniaudio/miniaudio.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TT_EFFECT_COUNT 10
#define TT_MUSIC_COUNT 4
#define TT_EFFECT_CHANNELS 8
#define TT_MUSIC_FADE_MS 1280

typedef enum TTEffect {
    TT_EFFECT_SHOT,
    TT_EFFECT_CHARGE,
    TT_EFFECT_CHARGE_SHOT,
    TT_EFFECT_HIT,
    TT_EFFECT_SMALL_DEST,
    TT_EFFECT_MIDDLE_DEST,
    TT_EFFECT_BOSS_DEST,
    TT_EFFECT_MYSHIP_DEST,
    TT_EFFECT_EXTEND,
    TT_EFFECT_TIMEUP_BEEP
} TTEffect;

static const char *tt_effect_files[TT_EFFECT_COUNT] = {
    "shot.wav", "charge.wav", "charge_shot.wav", "hit.wav",
    "small_dest.wav", "middle_dest.wav", "boss_dest.wav",
    "myship_dest.wav", "extend.wav", "timeup_beep.wav"
};

/* Effects sharing a channel intentionally interrupt each other. */
static const int tt_effect_channels[TT_EFFECT_COUNT] = {0, 1, 1, 2, 3, 4, 4, 5, 6, 7};

typedef struct TTAudio {
    ma_context context;
    ma_engine engine;
    ma_sound effects[TT_EFFECT_COUNT];
    ma_sound music[TT_MUSIC_COUNT];
    bool context_initialized;
    bool engine_initialized;
    bool effect_initialized[TT_EFFECT_COUNT];
    bool music_initialized[TT_MUSIC_COUNT];
    int current_music;
    char error[512];
} TTAudio;

static void tt_audio_destroy(TTAudio *audio);

static void tt_audio_set_result_error(TTAudio *audio, const char *operation,
                                      const char *path, ma_result result) {
    snprintf(audio->error, sizeof(audio->error), "%s%s%s failed: %s (%d)",
             operation, path ? " " : "", path ? path : "",
             ma_result_description(result), result);
}

static bool tt_audio_path(char *destination, size_t size, const char *root,
                          const char *directory, const char *file) {
    int written = snprintf(destination, size, "%s/%s/%s", root, directory, file);
    return written > 0 && (size_t)written < size;
}

static TTAudio *tt_audio_create(const char *asset_root, bool null_backend) {
    TTAudio *audio = (TTAudio *)calloc(1, sizeof(*audio));
    if (!audio)
        return NULL;
    audio->current_music = -1;

    const char *forced_failure = getenv("TT_AUDIO_FORCE_INIT_FAILURE");
    if (forced_failure && forced_failure[0] && strcmp(forced_failure, "0") != 0) {
        snprintf(audio->error, sizeof(audio->error), "audio initialization forced to fail");
        return audio;
    }

    ma_engine_config engine_config = ma_engine_config_init();
    if (null_backend) {
        ma_backend backend = ma_backend_null;
        ma_result result = ma_context_init(&backend, 1, NULL, &audio->context);
        if (result != MA_SUCCESS) {
            tt_audio_set_result_error(audio, "initializing null audio context", NULL, result);
            return audio;
        }
        audio->context_initialized = true;
        engine_config.pContext = &audio->context;
    }

    ma_result result = ma_engine_init(&engine_config, &audio->engine);
    if (result != MA_SUCCESS) {
        tt_audio_set_result_error(audio, "initializing audio device", NULL, result);
        return audio;
    }
    audio->engine_initialized = true;

    char path[1024];
    for (int i = 0; i < TT_EFFECT_COUNT; ++i) {
        if (!tt_audio_path(path, sizeof(path), asset_root, "sounds/chunks", tt_effect_files[i])) {
            snprintf(audio->error, sizeof(audio->error), "audio asset path is too long");
            return audio;
        }
        result = ma_sound_init_from_file(&audio->engine, path,
            MA_SOUND_FLAG_DECODE | MA_SOUND_FLAG_NO_SPATIALIZATION, NULL, NULL,
            &audio->effects[i]);
        if (result != MA_SUCCESS) {
            tt_audio_set_result_error(audio, "preloading effect", path, result);
            return audio;
        }
        audio->effect_initialized[i] = true;
    }

    for (int i = 0; i < TT_MUSIC_COUNT; ++i) {
        char filename[16];
        snprintf(filename, sizeof(filename), "tt%d.wav", i + 1);
        if (!tt_audio_path(path, sizeof(path), asset_root, "sounds/musics", filename)) {
            snprintf(audio->error, sizeof(audio->error), "audio asset path is too long");
            return audio;
        }
        /* Decode music while the loading screen is still active. Streaming
           four PCM files from removable storage caused the first gameplay
           seconds to block on USB reads and report single-digit frame rates. */
        result = ma_sound_init_from_file(&audio->engine, path,
            MA_SOUND_FLAG_DECODE | MA_SOUND_FLAG_NO_SPATIALIZATION, NULL, NULL,
            &audio->music[i]);
        if (result != MA_SUCCESS) {
            tt_audio_set_result_error(audio, "preloading music", path, result);
            return audio;
        }
        ma_sound_set_looping(&audio->music[i], MA_TRUE);
        audio->music_initialized[i] = true;
    }
    return audio;
}

static bool tt_audio_is_ready(const TTAudio *audio) {
    if (!audio || !audio->engine_initialized || audio->error[0])
        return false;
    for (int i = 0; i < TT_EFFECT_COUNT; ++i)
        if (!audio->effect_initialized[i]) return false;
    for (int i = 0; i < TT_MUSIC_COUNT; ++i)
        if (!audio->music_initialized[i]) return false;
    return true;
}

static const char *tt_audio_last_error(const TTAudio *audio) {
    if (!audio)
        return "out of memory while creating audio runtime";
    return audio->error;
}

static int tt_audio_effect_channel(int effect) {
    return effect >= 0 && effect < TT_EFFECT_COUNT ? tt_effect_channels[effect] : -1;
}

static bool tt_audio_play_effect(TTAudio *audio, int effect) {
    if (!tt_audio_is_ready(audio) || effect < 0 || effect >= TT_EFFECT_COUNT)
        return false;
    int channel = tt_effect_channels[effect];
    for (int i = 0; i < TT_EFFECT_COUNT; ++i) {
        if (tt_effect_channels[i] == channel) {
            ma_sound_stop(&audio->effects[i]);
            ma_sound_seek_to_pcm_frame(&audio->effects[i], 0);
        }
    }
    ma_result result = ma_sound_start(&audio->effects[effect]);
    if (result != MA_SUCCESS) {
        tt_audio_set_result_error(audio, "playing effect", tt_effect_files[effect], result);
        return false;
    }
    return true;
}

static bool tt_audio_play_music(TTAudio *audio, int track) {
    if (!tt_audio_is_ready(audio) || track < 0 || track >= TT_MUSIC_COUNT)
        return false;
    if (audio->current_music >= 0) {
        ma_sound_stop(&audio->music[audio->current_music]);
        ma_sound_seek_to_pcm_frame(&audio->music[audio->current_music], 0);
    }
    ma_sound *music = &audio->music[track];
    ma_sound_set_stop_time_in_milliseconds(music, ~(ma_uint64)0);
    ma_sound_set_volume(music, 1.0f);
    ma_sound_set_fade_in_milliseconds(music, 1.0f, 1.0f, 0);
    ma_sound_seek_to_pcm_frame(music, 0);
    ma_result result = ma_sound_start(music);
    if (result != MA_SUCCESS) {
        tt_audio_set_result_error(audio, "playing music", NULL, result);
        return false;
    }
    audio->current_music = track;
    return true;
}

static void tt_audio_fade_music(TTAudio *audio) {
    if (!tt_audio_is_ready(audio) || audio->current_music < 0)
        return;
    ma_sound *music = &audio->music[audio->current_music];
    ma_uint64 now = ma_engine_get_time_in_milliseconds(&audio->engine);
    ma_sound_set_fade_in_milliseconds(music, -1.0f, 0.0f, TT_MUSIC_FADE_MS);
    ma_sound_set_stop_time_in_milliseconds(music, now + TT_MUSIC_FADE_MS);
}

static void tt_audio_halt_music(TTAudio *audio) {
    if (!audio || audio->current_music < 0)
        return;
    ma_sound_stop(&audio->music[audio->current_music]);
    ma_sound_seek_to_pcm_frame(&audio->music[audio->current_music], 0);
    audio->current_music = -1;
}

static void tt_audio_set_paused(TTAudio *audio, bool paused) {
    if (!tt_audio_is_ready(audio))
        return;
    if (paused)
        ma_engine_stop(&audio->engine);
    else
        ma_engine_start(&audio->engine);
}

static void tt_audio_set_volume(TTAudio *audio, float volume) {
    if (!tt_audio_is_ready(audio))
        return;
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    ma_engine_set_volume(&audio->engine, volume);
}

static void tt_audio_destroy(TTAudio *audio) {
    if (!audio)
        return;
    if (audio->engine_initialized) {
        tt_audio_halt_music(audio);
        for (int i = 0; i < TT_EFFECT_COUNT; ++i)
            if (audio->effect_initialized[i]) ma_sound_uninit(&audio->effects[i]);
        for (int i = 0; i < TT_MUSIC_COUNT; ++i)
            if (audio->music_initialized[i]) ma_sound_uninit(&audio->music[i]);
        ma_engine_uninit(&audio->engine);
    }
    if (audio->context_initialized)
        ma_context_uninit(&audio->context);
    free(audio);
}

#endif
