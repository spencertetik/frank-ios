import SwiftUI
import UIKit

struct QuickCommandDetailView: View {
    let commandType: QuickCommandCache.CommandType
    @Environment(QuickCommandCache.self) private var cache
    @Environment(GatewayClient.self) private var gateway
    @State private var audioService = AudioService.shared
    
    private var result: QuickCommandCache.CachedResult? {
        cache.result(for: commandType)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                header
                
                // Content
                if let result {
                    if result.isLoading {
                        loadingView
                    } else {
                        contentCard(result.content)
                    }
                } else {
                    emptyView
                }
            }
            .padding()
        }
        .navigationTitle(commandType.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // Speaker button
                    Button {
                        if let content = result?.content, !content.isEmpty {
                            Task { await audioService.speak(text: content, messageId: "qc-\(commandType.rawValue)") }
                        }
                    } label: {
                        if audioService.isGeneratingTTS && audioService.playingMessageId == "qc-\(commandType.rawValue)" {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: audioService.playingMessageId == "qc-\(commandType.rawValue)" && audioService.isPlaying ? "speaker.wave.2.fill" : "speaker.wave.2")
                                .foregroundStyle(audioService.playingMessageId == "qc-\(commandType.rawValue)" ? Theme.accent : .secondary)
                        }
                    }
                    .disabled(result?.content == nil || result?.isLoading == true)
                    
                    // Refresh button
                    Button(action: refresh) {
                        if result?.isLoading == true {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(result?.isLoading == true || !gateway.isConnected)
                }
            }
        }
        .refreshable { refresh() }
        .onAppear {
            // Auto-fetch if no data or stale
            if result == nil || cache.isStale(commandType) {
                refresh()
            }
        }
    }
    
    private var header: some View {
        HStack {
            Text(commandType.emoji)
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(commandType.title)
                    .font(.title3.weight(.semibold))
                Text("Updated \(cache.lastUpdated(commandType))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if cache.isStale(commandType) && result?.isLoading != true {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(Theme.accent)
                    .font(.caption)
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            ProgressView()
            Text("Fetching \(commandType.title.lowercased())...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            Image(systemName: commandType.icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No data yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Refresh", action: refresh)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!gateway.isConnected)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func contentCard(_ content: String) -> some View {
        Group {
            if let md = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(md)
                    .textSelection(.enabled)
            } else {
                Text(content)
                    .textSelection(.enabled)
            }
        }
        .font(.body)
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func refresh() {
        guard gateway.isConnected else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        cache.fetch(commandType, gateway: gateway)
    }
}
