/* CI compile probe: validates the vendored implementation with each host C compiler. */
#include "audio_bridge.h"

int main(void) {
    return tt_audio_effect_channel(TT_EFFECT_BOSS_DEST) == 4 &&
           TT_MUSIC_FADE_MS == 1280 ? 0 : 1;
}
