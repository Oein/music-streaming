package com.example.musicplayer

// audio_service (used by just_audio_background) requires the host Activity to
// extend AudioServiceActivity so it exposes the correct FlutterEngine to the
// background playback service. Using the default FlutterActivity makes
// JustAudioBackground.init() fail and all playback breaks.
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity()
