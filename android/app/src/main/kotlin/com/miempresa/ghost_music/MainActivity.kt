package com.miempresa.ghost_music

import com.ryanheise.audioservice.AudioServiceActivity

/// Hereda de AudioServiceActivity para compartir el FlutterEngine con el
/// servicio de audio en segundo plano (requerido por audio_service).
class MainActivity : AudioServiceActivity()
