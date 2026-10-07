// V interface to the native audio engine, including effect/music playback and failure reporting.
module runtime

#flag linux -ldl

#flag linux -lpthread

#flag linux -lm

#flag darwin -framework CoreAudio

#flag darwin -framework AudioToolbox

#flag darwin -framework AudioUnit

#flag darwin -framework CoreFoundation

$if windows {
	#flag -lole32
	$if tinyc {
		#flag -DTT_TINYC
	} $else {
		#flag -luuid
	}
	#flag -lwinmm
}

#include "audio_bridge.h"

@[typedef]
struct C.TTAudio {}

fn C.tt_audio_create(asset_root &char, null_backend bool) &C.TTAudio

fn C.tt_audio_destroy(audio &C.TTAudio)

fn C.tt_audio_is_ready(audio &C.TTAudio) bool

fn C.tt_audio_last_error(audio &C.TTAudio) &char

fn C.tt_audio_effect_channel(effect int) int

fn C.tt_audio_play_effect(audio &C.TTAudio, effect int) bool

fn C.tt_audio_play_music(audio &C.TTAudio, track int) bool

fn C.tt_audio_fade_music(audio &C.TTAudio)

fn C.tt_audio_halt_music(audio &C.TTAudio)

fn C.tt_audio_set_paused(audio &C.TTAudio, paused bool)

fn C.tt_audio_set_volume(audio &C.TTAudio, volume f32)

pub const music_fade_ms = 1280
pub const effect_count = 10
pub const effect_channel_count = 8

pub enum Effect {
	shot
	charge
	charge_shot
	hit
	small_dest
	middle_dest
	boss_dest
	myship_dest
	extend
	timeup_beep
}

pub struct AudioConfig {
pub:
	asset_root   string = '.'
	null_backend bool
}

@[heap]
pub struct Audio {
mut:
	handle &C.TTAudio = unsafe { nil }
}

pub fn new_audio(config AudioConfig) !&Audio {
	handle := C.tt_audio_create(config.asset_root.str, config.null_backend)
	if isnil(handle) {
		return error('out of memory while creating audio runtime')
	}
	if !C.tt_audio_is_ready(handle) {
		message := unsafe { C.tt_audio_last_error(handle).vstring() }.clone()
		C.tt_audio_destroy(handle)
		return error(message)
	}
	return &Audio{ handle: handle }
}

pub fn effect_channel(effect Effect) int {
	return C.tt_audio_effect_channel(int(effect))
}

pub fn (mut audio Audio) play_effect(effect Effect) bool {
	return !isnil(audio.handle) && C.tt_audio_play_effect(audio.handle, int(effect))
}

pub fn (mut audio Audio) play_music(track int) bool {
	return !isnil(audio.handle) && C.tt_audio_play_music(audio.handle, track)
}

pub fn (mut audio Audio) fade_music() {
	if !isnil(audio.handle) {
		C.tt_audio_fade_music(audio.handle)
	}
}

pub fn (mut audio Audio) halt_music() {
	if !isnil(audio.handle) {
		C.tt_audio_halt_music(audio.handle)
	}
}

pub fn (mut audio Audio) set_paused(paused bool) {
	if !isnil(audio.handle) {
		C.tt_audio_set_paused(audio.handle, paused)
	}
}

pub fn (mut audio Audio) set_volume(volume f32) {
	if !isnil(audio.handle) {
		C.tt_audio_set_volume(audio.handle, volume)
	}
}

pub fn (mut audio Audio) shutdown() {
	if !isnil(audio.handle) {
		C.tt_audio_destroy(audio.handle)
		audio.handle = unsafe { nil }
	}
}
