// Checks effect-channel assignments, null-backend lifetime, and audio initialization failures.
module runtime

import os

fn test_expected_effect_channel_assignments_are_preserved() {
	expected := [0, 1, 1, 2, 3, 4, 4, 5, 6, 7]
	for index, channel in expected {
		effect := unsafe { Effect(index) }
		assert effect_channel(effect) == channel
	}
	assert effect_count == 10
	assert effect_channel_count == 8
	assert music_fade_ms == 1280
}

fn test_audio_lifecycle_with_null_backend() {
	mut audio := new_audio(AudioConfig{
		asset_root: @VMODROOT
		null_backend: true
	}) or { panic(err) }
	assert audio.play_music(0)
	assert audio.play_effect(.shot)
	audio.set_volume(0.25)
	audio.set_volume(-1)
	audio.set_volume(2)
	audio.set_paused(true)
	audio.set_paused(false)
	audio.fade_music()
	audio.halt_music()
	audio.shutdown()
	// Shutdown is explicitly idempotent for partial startup and defer blocks.
	audio.shutdown()
}

fn test_missing_assets_return_an_error() {
	new_audio(AudioConfig{
		asset_root: os.join_path(os.temp_dir(), 'torus-trooper-assets-that-do-not-exist')
		null_backend: true
	}) or {
		assert err.msg().contains('preloading effect')
		return
	}
	assert false
}

fn test_forced_device_failure_returns_an_error() {
	os.setenv('TT_AUDIO_FORCE_INIT_FAILURE', '1', true)
	defer {
		os.unsetenv('TT_AUDIO_FORCE_INIT_FAILURE')
	}
	new_audio(AudioConfig{ asset_root: @VMODROOT, null_backend: true }) or {
		assert err.msg().contains('forced to fail')
		return
	}
	assert false
}
