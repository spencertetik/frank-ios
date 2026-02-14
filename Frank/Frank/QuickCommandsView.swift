import SwiftUI

/// Quick command buttons for common Frank interactions with caching
struct QuickCommandsView: View {
    @Environment(GatewayClient.self) private var gateway
    @Environment(QuickCommandCache.self) private var cache
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var selectedTab: Int
    
    // Grid configuration based on device
    private var gridColumns: [GridItem] {
        let columnCount = horizontalSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Theme.paddingMedium), count: columnCount)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMedium) {
            // Section header
            HStack {
                Text("Quick Commands")
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)
                
                Spacer()
                
                if !gateway.isConnected {
                    Text("Offline")
                        .font(.caption)
                        .foregroundColor(Theme.error)
                        .padding(.horizontal, Theme.paddingSmall)
                        .padding(.vertical, 2)
                        .background(Theme.error.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            
            // Commands grid
            LazyVGrid(columns: gridColumns, spacing: Theme.paddingMedium) {
                ForEach(QuickCommandCache.CommandType.allCases, id: \.self) { commandType in
                    CachedQuickCommandButton(commandType: commandType)
                }
            }
        }
    }
}

// MARK: - Cached Quick Command Button

struct CachedQuickCommandButton: View {
    let commandType: QuickCommandCache.CommandType
    @State private var isPressed = false
    @Environment(GatewayClient.self) private var gateway
    @Environment(QuickCommandCache.self) private var cache
    
    private var lastUpdated: String {
        cache.lastUpdated(commandType)
    }
    
    private var isStale: Bool {
        cache.isStale(commandType)
    }
    
    private var isLoading: Bool {
        cache.result(for: commandType)?.isLoading == true
    }
    
    var body: some View {
        NavigationLink(destination: QuickCommandDetailView(commandType: commandType)) {
            VStack(spacing: Theme.paddingSmall) {
                // Top row with emoji and stale indicator
                HStack {
                    Image(systemName: commandType.icon)
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                    
                    Spacer()
                    
                    // Show stale indicator or loading spinner
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if isStale && cache.result(for: commandType) != nil {
                        Circle()
                            .fill(Theme.warning)
                            .frame(width: 6, height: 6)
                    }
                }
                
                // Command title
                Text(commandType.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                // Last updated time
                if cache.result(for: commandType) != nil {
                    Text(lastUpdated)
                        .font(.caption2)
                        .foregroundColor(isStale ? Theme.warning : Theme.textTertiary)
                        .lineLimit(1)
                } else {
                    Text("Tap to fetch")
                        .font(.caption2)
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.paddingMedium)
            .padding(.horizontal, Theme.paddingSmall)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                    .fill(Theme.cardBackground)
                    .shadow(
                        color: Theme.cardShadow.color,
                        radius: isPressed ? 2 : Theme.cardShadow.radius,
                        x: Theme.cardShadow.x,
                        y: isPressed ? 1 : Theme.cardShadow.y
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0) {
            // Do nothing on release
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScrollView {
            VStack(spacing: Theme.paddingXLarge) {
                QuickCommandsView(selectedTab: .constant(0))
                    .padding()
            }
        }
        .background(Theme.background)
    }
    .environment(GatewayClient())
    .environment(QuickCommandCache())
}