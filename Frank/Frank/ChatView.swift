import SwiftUI
import UIKit
import Combine
import PhotosUI
import AVFoundation

struct ChatView: View {
    var scrollTrigger: Int = 0
    
    @Environment(GatewayClient.self) private var gateway
    @State private var draft = ""
    @FocusState private var isFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var showImageSource = false
    @State private var showCamera = false
    @State private var audioService = AudioService.shared
    @State private var micPulse = false
    @State private var autoSpeak = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if gateway.messages.isEmpty && !gateway.isThinking {
                    emptyState
                } else {
                    messageList
                }
                
                Divider()
                
                inputBar
            }
            .navigationTitle("Chat")
            .background(Theme.bgPrimary)
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .top) {
                if let error = audioService.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 50)
                        .onTapGesture { audioService.lastError = nil }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut, value: audioService.lastError)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    connectionIndicator
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "message")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("What can I help with?")
                .font(.headline)
                .foregroundStyle(.secondary)
            suggestionChips
            Spacer()
        }
    }
    
    private var suggestionChips: some View {
        FlowLayout(spacing: 8) {
            SuggestionChip(text: "Morning Report", icon: "sun.max", speakerEnabled: true) {
                gateway.sendChat("Give me my morning report")
            } speakerAction: {
                autoSpeak = true
                gateway.sendChat("Give me my morning report")
            }
            SuggestionChip(text: "Check Email", icon: "envelope", speakerEnabled: true) {
                gateway.sendChat("Check my email")
            } speakerAction: {
                autoSpeak = true
                gateway.sendChat("Check my email")
            }
            SuggestionChip(text: "Weather", icon: "cloud.sun", speakerEnabled: true) {
                gateway.sendChat("What's the weather in Perry, OK?")
            } speakerAction: {
                autoSpeak = true
                gateway.sendChat("What's the weather in Perry, OK?")
            }
            SuggestionChip(text: "Calendar", icon: "calendar", speakerEnabled: true) {
                gateway.sendChat("What's on my calendar today?")
            } speakerAction: {
                autoSpeak = true
                gateway.sendChat("What's on my calendar today?")
            }
            SuggestionChip(text: "Project Status", icon: "folder", speakerEnabled: true) {
                gateway.sendChat("Give me a project status update")
            } speakerAction: {
                autoSpeak = true
                gateway.sendChat("Give me a project status update")
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Message List (fixed scroll)
    
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groupMessagesByDate(gateway.messages), id: \.date) { group in
                        DateSeparatorView(date: group.date)
                        ForEach(group.messages) { message in
                            ChatBubble(message: message, audioService: audioService)
                                .id(message.id)
                        }
                    }
                    
                    // Thinking indicator with live preview
                    if gateway.isThinking {
                        ThinkingBubble(text: gateway.thinkingText)
                            .id("thinking")
                    }
                    
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .onAppear {
                scrollToBottom(proxy)
            }
            .onChange(of: scrollTrigger) {
                scrollToBottom(proxy)
            }
            .onChange(of: gateway.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    scrollToBottom(proxy)
                }
                // Auto-speak last assistant message when it's done streaming
                if autoSpeak, let last = gateway.messages.last, !last.isFromUser, !last.isStreaming, !last.text.isEmpty {
                    autoSpeak = false
                    Task { await audioService.speak(text: last.text, messageId: last.id) }
                }
            }
            .onChange(of: gateway.isThinking) {
                withAnimation(.easeOut(duration: 0.2)) {
                    scrollToBottom(proxy)
                }
                // Auto-speak when thinking ends (response finalized)
                if !gateway.isThinking && autoSpeak, let last = gateway.messages.last, !last.isFromUser, !last.text.isEmpty {
                    autoSpeak = false
                    Task { await audioService.speak(text: last.text, messageId: last.id) }
                }
            }
            .onChange(of: gateway.thinkingText) {
                scrollToBottom(proxy)
            }
            .refreshable {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                gateway.reloadHistory()
            }
        }
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        // Delay slightly to ensure layout is complete after tab switch or new messages
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            // Pending image preview
            if let img = pendingImage {
                HStack {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    VStack(alignment: .leading) {
                        Text("Image attached")
                            .font(.caption.weight(.medium))
                        Text("\(Int(img.size.width))×\(Int(img.size.height))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation { pendingImage = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04))
            }
            
            HStack(spacing: 12) {
                // Image attachment button
                Menu {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    
                    // Photo library handled by PhotosPicker below
                } label: {
                    Image(systemName: pendingImage != nil ? "photo.fill" : "photo")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(pendingImage != nil ? Theme.accent : .white.opacity(0.5))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .overlay {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Color.clear
                    }
                    .labelsHidden()
                }
                
                TextField("Message Frank...", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .onSubmit { send() }
                
                // Mic button
                Button {
                    Task { await toggleRecording() }
                } label: {
                    Image(systemName: audioService.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(audioService.isRecording ? .red : .white.opacity(0.5))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(audioService.isRecording ? .red.opacity(0.15) : .white.opacity(0.08))
                        )
                        .overlay(
                            Circle()
                                .stroke(.red, lineWidth: audioService.isRecording ? 2 : 0)
                                .scaleEffect(micPulse ? 1.3 : 1.0)
                                .opacity(micPulse ? 0 : 1)
                                .animation(audioService.isRecording ? .easeInOut(duration: 0.8).repeatForever(autoreverses: false) : .default, value: micPulse)
                        )
                }
                .onChange(of: audioService.isRecording) {
                    micPulse = audioService.isRecording
                }
                
                if audioService.isTranscribing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 36, height: 36)
                }
                
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSend ? .white : .white.opacity(0.3))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(canSend ? Theme.accent : .white.opacity(0.08))
                        )
                }
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.2), value: canSend)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(Theme.bgSecondary.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .onChange(of: selectedPhoto) {
            Task {
                if let item = selectedPhoto,
                   let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    withAnimation { pendingImage = image }
                }
                selectedPhoto = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { image in
                if let image {
                    withAnimation { pendingImage = image }
                }
            }
        }
    }
    
    private var connectionIndicator: some View {
        Circle()
            .fill(gateway.isConnected ? .green : .red)
            .frame(width: 8, height: 8)
    }
    
    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = pendingImage != nil
        return (hasText || hasImage) && gateway.isConnected
    }
    
    private func toggleRecording() async {
        if audioService.isRecording {
            guard let url = audioService.stopRecording() else { return }
            if let text = await audioService.transcribe(audioURL: url) {
                draft += (draft.isEmpty ? "" : " ") + text
            }
        } else {
            let granted = await audioService.requestMicPermission()
            guard granted else { return }
            audioService.startRecording()
        }
    }
    
    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || pendingImage != nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        if let image = pendingImage {
            gateway.sendChatWithImage(text: text.isEmpty ? "What's in this image?" : text, image: image)
            withAnimation { pendingImage = nil }
        } else {
            gateway.sendChat(text)
        }
        draft = ""
    }
    
    // MARK: - Grouping
    
    private func groupMessagesByDate(_ messages: [GatewayClient.ChatMessage]) -> [MessageGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: messages) { calendar.startOfDay(for: $0.timestamp) }
        return grouped.map { MessageGroup(date: $0.key, messages: $0.value.sorted { $0.timestamp < $1.timestamp }) }
            .sorted { $0.date < $1.date }
    }
}

// MARK: - Thinking Bubble (collapsible thinking → final)

struct ThinkingBubble: View {
    let text: String
    @State private var isExpanded = true
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Frank")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                
                // Thinking header — always visible
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        ThinkingDots()
                        Text("Thinking...")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                
                // Expandable thinking content
                if isExpanded && !text.isEmpty {
                    Text(text.suffix(500))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            
            Spacer(minLength: 60)
        }
    }
}

struct ThinkingDots: View {
    @State private var phase = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 5, height: 5)
                    .opacity(phase == i ? 1.0 : 0.3)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: GatewayClient.ChatMessage
    var audioService: AudioService
    
    private static let markdownOptions = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .full
    )
    
    var body: some View {
        HStack {
            if message.isFromUser { Spacer(minLength: 60) }
            
            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
                if !message.isFromUser {
                    HStack(spacing: 6) {
                        Text("Frank")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        
                        // Speaker button for assistant messages
                        Button {
                            Task { await audioService.speak(text: message.text, messageId: message.id) }
                        } label: {
                            Group {
                                if audioService.isGeneratingTTS && audioService.playingMessageId == message.id {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: audioService.playingMessageId == message.id && audioService.isPlaying ? "speaker.wave.2.fill" : "speaker.wave.2")
                                }
                            }
                            .font(.caption)
                            .frame(width: 20, height: 20)
                            .foregroundStyle(audioService.playingMessageId == message.id ? Theme.accent : .white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                bubbleContent
                    .contextMenu {
                        Button { UIPasteboard.general.string = message.text } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        ShareLink(item: message.text) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        if !message.isFromUser {
                            Button {
                                Task { await audioService.speak(text: message.text, messageId: message.id) }
                            } label: {
                                Label("Read Aloud", systemImage: "speaker.wave.2")
                            }
                        }
                    }
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            if !message.isFromUser { Spacer(minLength: 60) }
        }
    }
    
    private var bubbleContent: some View {
        VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 6) {
            // Image attachment
            if let imgData = message.imageData, let uiImage = UIImage(data: imgData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Text
            if !message.text.isEmpty {
                Group {
                    if let attributed = try? AttributedString(markdown: message.text, options: Self.markdownOptions) {
                        Text(attributed)
                    } else {
                        Text(message.text)
                    }
                }
                .multilineTextAlignment(message.isFromUser ? .trailing : .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            message.isFromUser ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.06)),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            message.isFromUser ? nil : RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .foregroundStyle(message.isFromUser ? .white : .primary)
    }
}

// MARK: - Supporting Views

struct MessageGroup {
    let date: Date
    let messages: [GatewayClient.ChatMessage]
}

struct DateSeparatorView: View {
    let date: Date
    
    private var dateText: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
    
    var body: some View {
        HStack {
            VStack { Divider() }
            Text(dateText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            VStack { Divider() }
        }
        .padding(.vertical, 8)
    }
}

struct SuggestionChip: View {
    let text: String
    let icon: String
    var speakerEnabled: Bool = false
    let action: () -> Void
    var speakerAction: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.caption)
                    Text(text).font(.subheadline)
                }
                .padding(.leading, 14)
                .padding(.trailing, speakerEnabled ? 8 : 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            
            if speakerEnabled {
                Button {
                    speakerAction?()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .padding(.trailing, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.thinMaterial, in: Capsule())
        .foregroundStyle(Theme.accent)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (i, pos) in result.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxW = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            positions.append(CGPoint(x: x, y: y))
            rowH = max(rowH, s.height)
            x += s.width + spacing
        }
        return (CGSize(width: maxW, height: y + rowH), positions)
    }
}

struct StreamingIndicator: View {
    @State private var animate = false
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.accent).frame(width: 6, height: 6)
                .scaleEffect(animate ? 1.3 : 0.8)
                .opacity(animate ? 0.2 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: animate)
            Text("typing…").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 2)
        .onAppear { animate = true }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            parent.completion(image)
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.completion(nil)
            parent.dismiss()
        }
    }
}
