import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Kapselt die native, datenschutzfreundliche On-Device Spracherkennung
/// für die Freihand-Ortssuche im Gelände (Apple SFSpeechRecognizer / Android SpeechRecognizer).
class VoiceSearchService {
  static final VoiceSearchService _shared = VoiceSearchService();

  final SpeechToText _speechToText;
  bool _isInitialized = false;
  bool _isAvailable = false;
  String? _lastError;

  VoiceSearchService({SpeechToText? speechToText})
      : _speechToText = speechToText ?? SpeechToText();

  static VoiceSearchService get shared => _shared;

  bool get isAvailable => _isAvailable;
  bool get isListening => _speechToText.isListening;
  String? get lastError => _lastError;

  Future<bool> get hasPermission async {
    try {
      return await _speechToText.hasPermission;
    } catch (_) {
      return false;
    }
  }

  /// Initialisiert den Spracherkennungsdienst und prüft Mikrofon-Rechte.
  Future<bool> initialize({
    ValueChanged<String>? onError,
    ValueChanged<String>? onStatus,
    bool force = false,
  }) async {
    if (_isInitialized && _isAvailable && !force) return true;
    try {
      _lastError = null;
      _isAvailable = await _speechToText.initialize(
        onError: (err) {
          final formatted = formatErrorMessage(err.errorMsg);
          _lastError = formatted;
          debugPrint('VoiceSearchService Fehler: ${err.errorMsg} ($formatted)');
          onError?.call(formatted);
        },
        onStatus: (status) {
          debugPrint('VoiceSearchService Status: $status');
          onStatus?.call(status);
        },
        options: [
          SpeechToText.androidNoBluetooth,
        ],
        debugLogging: true,
      );
      _isInitialized = true;
      return _isAvailable;
    } catch (e) {
      final formatted = formatErrorMessage(e.toString());
      _lastError = formatted;
      debugPrint('VoiceSearchService Init Exception: $e');
      _isAvailable = false;
      _isInitialized = true;
      onError?.call(formatted);
      return false;
    }
  }

  /// Startet das Zuhören mit optimierter Spracheinstellung.
  Future<void> startListening({
    required ValueChanged<String> onResult,
    VoidCallback? onListeningFinished,
    ValueChanged<String>? onError,
  }) async {
    if (!_isInitialized || !_isAvailable) {
      final ok = await initialize(onError: onError, force: true);
      if (!ok) {
        onError?.call(
          _lastError ??
              'Spracherkennung oder Mikrofon auf diesem Gerät nicht verfügbar.',
        );
        return;
      }
      // Kurze Pause, damit Android den SpeechRecognizer IPC-Binder sauber initialisieren kann
      await Future.delayed(const Duration(milliseconds: 250));
    }

    if (_speechToText.isListening) {
      await stopListening();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    String? selectedLocale;
    try {
      final locales = await _speechToText.locales();
      if (locales.isNotEmpty) {
        final deLocale = locales.firstWhere(
          (loc) => loc.localeId.toLowerCase().startsWith('de'),
          orElse: () => locales.first,
        );
        selectedLocale = deLocale.localeId;
      }
    } catch (_) {
      selectedLocale = null;
    }

    try {
      await _speechToText.listen(
        onResult: (result) {
          final recognizedWords = result.recognizedWords.trim();
          if (recognizedWords.isNotEmpty) {
            onResult(recognizedWords);
          }
          if (result.finalResult && onListeningFinished != null) {
            onListeningFinished();
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: selectedLocale,
          listenFor: const Duration(seconds: 15),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: false,
          // WICHTIG: ListenMode.dictation nutzt RecognizerIntent.LANGUAGE_MODEL_FREE_FORM.
          // ListenMode.search nutzt dagegen LANGUAGE_MODEL_WEB_SEARCH, was auf modernen
          // Android-Geräten zu 'error_server_disconnected' führt.
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      debugPrint('VoiceSearchService Listen Exception: $e');
      onError?.call('Fehler beim Starten der Audio-Aufnahme: $e');
    }
  }

  /// Stoppt die aktive Spracherkennung.
  Future<void> stopListening() async {
    try {
      if (_speechToText.isListening) {
        await _speechToText.stop();
      }
    } catch (_) {}
  }

  /// Bricht die Spracherkennung ab.
  Future<void> cancelListening() async {
    try {
      await _speechToText.cancel();
    } catch (_) {}
  }

  static String formatErrorMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('server_disconnected') ||
        lower.contains('server disconnected')) {
      return 'Sprachdienst wurde kurz getrennt. Bitte tippe erneut auf das Mikrofon.';
    }
    if (lower.contains('missingpluginexception')) {
      return 'Die App muss nach dem Hinzufügen des Sprachdienstes einmalig komplett neu gestartet werden (App beenden & "flutter run" neu starten – Hot-Reload reicht für native Android-Plugins nicht aus).';
    }
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'Mikrofon-Berechtigung verweigert. Bitte in den Android-Einstellungen erlauben.';
    }
    if (lower.contains('timeout') || lower.contains('no_match')) {
      return 'Kein Ort verstanden. Bitte sprich deutlicher oder näher ans Mikrofon.';
    }
    if (lower.contains('busy')) {
      return 'Sprachdienst ist derzeit beschäftigt. Bitte kurz warten.';
    }
    if (lower.contains('network')) {
      return 'Netzwerkfehler bei der Spracherkennung.';
    }
    if (lower.contains('notavailable') ||
        lower.contains('recognizernotavailable')) {
      return 'Spracherkennung auf diesem Android-Gerät nicht aktiv (bitte Google Speech Services prüfen).';
    }
    return 'Spracheingabe-Hinweis: $raw';
  }
}
