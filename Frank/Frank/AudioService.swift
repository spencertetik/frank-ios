import Foundation
import AVFoundation
import Observation

@Observable
@MainActor
final class AudioService: NSObject {
    var isRecording = false
    var isPlaying = false
    var isTranscribing = false
    var isGeneratingTTS = false
    var playingMessageId: String?
    var lastError: String?
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("frank_recording.m4a")
    }
    
    static let shared = AudioService()
    
    private override init() {
        super.init()
    }
    
    // MARK: - API Key
    
    var openAIKey: String {
        UserDefaults.standard.string(forKey: "openAIAPIKey").flatMap { $0.isEmpty ? nil : $0 }
            ?? Secrets.openAIKey
    }
    
    // MARK: - Recording
    
    func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("[AudioService] Session error: \(error)")
            lastError = "Mic session error: \(error.localizedDescription)"
            return
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            print("[AudioService] Recording error: \(error)")
            lastError = "Recording error: \(error.localizedDescription)"
        }
    }
    
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        isRecording = false
        guard FileManager.default.fileExists(atPath: recordingURL.path) else { return nil }
        return recordingURL
    }
    
    // MARK: - Whisper Transcription
    
    func transcribe(audioURL: URL) async -> String? {
        isTranscribing = true
        defer { isTranscribing = false }
        
        let key = openAIKey
        guard !key.isEmpty else {
            lastError = "No OpenAI API key"
            return nil
        }
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        guard let audioData = try? Data(contentsOf: audioURL) else {
            lastError = "Could not read audio file"
            return nil
        }
        
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\nContent-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[AudioService] Whisper response status: \(status)")
            if status != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[AudioService] Whisper error body: \(body)")
                lastError = "Whisper error \(status): \(body.prefix(200))"
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                return text
            }
            lastError = "Could not parse Whisper response"
        } catch {
            print("[AudioService] Transcription error: \(error)")
            lastError = "Transcription error: \(error.localizedDescription)"
        }
        return nil
    }
    
    // MARK: - TTS
    
    func speak(text: String, messageId: String) async {
        print("[AudioService] speak() called for message: \(messageId.prefix(12))...")
        print("[AudioService] text length: \(text.count), key present: \(!openAIKey.isEmpty)")
        
        // If already playing this message, stop it
        if playingMessageId == messageId && isPlaying {
            stopPlayback()
            return
        }
        
        // Stop any current playback
        stopPlayback()
        
        isGeneratingTTS = true
        playingMessageId = messageId
        lastError = nil
        
        let key = openAIKey
        guard !key.isEmpty else {
            print("[AudioService] No API key!")
            lastError = "No OpenAI API key configured"
            isGeneratingTTS = false
            playingMessageId = nil
            return
        }
        
        // Strip markdown for cleaner speech
        let cleanText = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "#", with: "")
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let payload: [String: Any] = [
            "model": "tts-1",
            "input": String(cleanText.prefix(4096)),
            "voice": "echo",
            "response_format": "mp3"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            print("[AudioService] Sending TTS request...")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[AudioService] TTS response status: \(status), data size: \(data.count) bytes")
            
            guard status == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
                print("[AudioService] TTS API error: \(errorBody)")
                lastError = "TTS error \(status): \(errorBody.prefix(200))"
                playingMessageId = nil
                isGeneratingTTS = false
                return
            }
            
            guard data.count > 100 else {
                print("[AudioService] TTS returned suspiciously small data: \(data.count) bytes")
                lastError = "TTS returned empty audio"
                playingMessageId = nil
                isGeneratingTTS = false
                return
            }
            
            isGeneratingTTS = false
            playAudioData(data, messageId: messageId)
        } catch {
            print("[AudioService] TTS network error: \(error)")
            lastError = "TTS error: \(error.localizedDescription)"
            playingMessageId = nil
            isGeneratingTTS = false
        }
    }
    
    // MARK: - Playback
    
    private func playAudioData(_ data: Data, messageId: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("frank_tts_\(messageId.prefix(8)).mp3")
        
        do {
            try data.write(to: tempURL)
            print("[AudioService] Wrote \(data.count) bytes to \(tempURL.lastPathComponent)")
        } catch {
            print("[AudioService] File write error: \(error)")
            lastError = "Could not save audio"
            playingMessageId = nil
            return
        }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            let started = audioPlayer?.play() ?? false
            print("[AudioService] Player started: \(started), duration: \(audioPlayer?.duration ?? 0)s")
            
            if started {
                isPlaying = true
            } else {
                print("[AudioService] Player.play() returned false")
                lastError = "Audio player failed to start"
                playingMessageId = nil
            }
        } catch {
            print("[AudioService] Playback error: \(error)")
            lastError = "Playback error: \(error.localizedDescription)"
            playingMessageId = nil
            isPlaying = false
        }
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playingMessageId = nil
    }
}

extension AudioService: @preconcurrency AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("[AudioService] Playback finished, success: \(flag)")
        isPlaying = false
        playingMessageId = nil
    }
}
