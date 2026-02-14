import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Int? = 0
    @State private var chatScrollTrigger = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(GatewayClient.self) private var gateway
    
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - iPad Layout (NavigationSplitView)
    
    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: 0) {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent")
                }
                .tag(0)
                
                NavigationLink(value: 1) {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(1)
                
                NavigationLink(value: 2) {
                    Label("Chat", systemImage: "message")
                }
                .tag(2)
                
                NavigationLink(value: 3) {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
            }
            .navigationTitle("Frank")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                // Connection status banner (iPad)
                if !gateway.isConnected {
                    connectionStatusBanner
                }
                
                Group {
                    switch selectedTab {
                    case 0:
                        DashboardView()
                    case 1:
                        CalendarView()
                    case 2:
                        ChatView(scrollTrigger: chatScrollTrigger)
                    case 3:
                        SettingsView()
                    default:
                        DashboardView()
                    }
                }
                .navigationBarTitleDisplayMode(.large)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedTab) {
            if selectedTab == 2 {
                chatScrollTrigger += 1
            }
        }
    }
    
    // MARK: - iPhone Layout (TabView)
    
    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            // Connection status banner (iPhone)
            if !gateway.isConnected {
                connectionStatusBanner
            }
            
            TabView(selection: Binding(get: { selectedTab ?? 0 }, set: { selectedTab = $0 })) {
                DashboardView()
                    .tag(0)
                    .tabItem {
                        Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent")
                    }
                
                CalendarView()
                    .tag(1)
                    .tabItem {
                        Label("Calendar", systemImage: "calendar")
                    }
                
                ChatView(scrollTrigger: chatScrollTrigger)
                    .tag(2)
                    .tabItem {
                        Label("Chat", systemImage: "message")
                    }
                
                SettingsView()
                    .tag(3)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .onChange(of: selectedTab) {
                if selectedTab == 2 {
                    chatScrollTrigger += 1
                }
            }
        }
    }
    
    // MARK: - Connection Status Banner
    
    private var connectionStatusBanner: some View {
        Button(action: {
            gateway.reconnectIfNeeded()
            // Add haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        }) {
            HStack(spacing: Theme.paddingMedium) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .semibold))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection Lost")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text("Tap to reconnect")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.white)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding()
            .background(Theme.error)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: gateway.isConnected)
    }
}

// MARK: - Tab Switching Helper

extension ContentView {
    func switchToTab(_ tabIndex: Int) {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedTab = tabIndex
        }
        
        // Trigger chat scroll if switching to chat
        if tabIndex == 2 {
            chatScrollTrigger += 1
        }
        
        // Add haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}

#Preview {
    ContentView()
        .environment(FrankStatusModel())
        .environment(GatewayClient())
        .environment(CalendarManager())
}