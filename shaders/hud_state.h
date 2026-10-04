#ifndef TT_HUD_STATE_H
#define TT_HUD_STATE_H

// Shared by the C renderer and GLSL shaders. These are the bit assignments in
// TTPushConstants.state, not tuning values. Keep both sides on this same layout.
#define TT_HUD_PAUSED 1
#define TT_HUD_GAME_OVER 2
#define TT_HUD_TITLE 4
#define TT_HUD_HAS_REPLAY 8
#define TT_HUD_GOD_MODE 16
#define TT_HUD_PAUSE_OVERLAY 32
#define TT_HUD_SETTINGS 64
#define TT_HUD_REPLAY_LIBRARY 128
#define TT_HUD_FPS_VISIBLE 256

// FPS occupies ten bits above the flags. The HUD displays up to three digits.
#define TT_HUD_FPS_SHIFT 10
#define TT_HUD_FPS_MASK 1023
#define TT_HUD_FPS_MAX_DISPLAY 999

// Title selection IDs carried by remaining_time_ms when TT_HUD_TITLE is set.
// Matches runtime/menu.v; the replay library uses its own overlay payload.
#define TT_MENU_NORMAL 0
#define TT_MENU_HARD 1
#define TT_MENU_EXTREME 2
#define TT_MENU_SETTINGS 3
#define TT_MENU_HELP 4
#define TT_MENU_TUNE 5
#define TT_MENU_EXIT 6
#define TT_MENU_REPLAYS 7

#endif
