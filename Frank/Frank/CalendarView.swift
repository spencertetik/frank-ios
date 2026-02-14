import SwiftUI
import EventKit

struct CalendarView: View {
    @Environment(CalendarManager.self) private var calendarManager
    @State private var searchText = ""
    @State private var showFilterSheet = false

    private var filteredEvents: [CalendarManager.CalendarEvent] {
        if searchText.isEmpty { return calendarManager.upcomingEvents }
        return calendarManager.upcomingEvents.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if calendarManager.authorizationStatus != .fullAccess {
                    accessPrompt
                } else if filteredEvents.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Upcoming Events" : "No Results",
                        systemImage: searchText.isEmpty ? "calendar" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Nothing scheduled for the next 7 days." : "No events matching \"\(searchText)\".")
                    )
                } else {
                    eventsList
                }
            }
            .navigationTitle("Calendar")
            .searchable(text: $searchText, prompt: "Search events")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if calendarManager.authorizationStatus == .fullAccess {
                        HStack(spacing: 12) {
                            Button {
                                showFilterSheet = true
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                            }
                            Button {
                                calendarManager.fetchEvents()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                CalendarFilterSheet(calendarManager: calendarManager)
            }
            .task {
                if calendarManager.authorizationStatus == .fullAccess {
                    calendarManager.fetchEvents()
                }
            }
        }
    }

    // MARK: - Components

    private var accessPrompt: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)

            Text("Calendar Access")
                .font(.title2.weight(.bold))

            Text("Grant access to see events from all your calendars — including work accounts synced to your phone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Task {
                    await calendarManager.requestAccess()
                }
            } label: {
                Text("Grant Access")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    @State private var expandedEventId: String?
    
    private var eventsList: some View {
        List {
            ForEach(groupedEvents, id: \.key) { day, events in
                Section {
                    ForEach(events) { event in
                        EventRow(
                            event: event,
                            isExpanded: expandedEventId == event.id,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    expandedEventId = expandedEventId == event.id ? nil : event.id
                                }
                            }
                        )
                    }
                } header: {
                    Text(day)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var groupedEvents: [(key: String, value: [CalendarManager.CalendarEvent])] {
        Dictionary(grouping: filteredEvents) { $0.relativeDay }
            .sorted { a, b in
                guard let aFirst = a.value.first, let bFirst = b.value.first else { return false }
                return aFirst.startDate < bFirst.startDate
            }
    }
}

// MARK: - Event Row (expandable)

struct EventRow: View {
    let event: CalendarManager.CalendarEvent
    let isExpanded: Bool
    let onTap: () -> Void
    
    private var color: Color {
        if let cg = event.calendarColor { return Color(cgColor: cg) }
        return Theme.accent
    }
    
    /// Extract meeting URL from event URL, location, or notes
    private var meetingURL: URL? {
        // Check event URL first
        if let url = event.url { return url }
        // Check location for URLs
        if let loc = event.location, let url = extractURL(from: loc) { return url }
        // Check notes for URLs
        if let notes = event.notes, let url = extractURL(from: notes) { return url }
        return nil
    }
    
    private func extractURL(from text: String) -> URL? {
        let patterns = ["https://meet.google.com", "https://zoom.us", "https://teams.microsoft.com", "https://"]
        for pattern in patterns {
            if let range = text.range(of: pattern) {
                let urlStart = text[range.lowerBound...]
                let urlString = String(urlStart.prefix(while: { !$0.isWhitespace && $0 != ">" && $0 != "\"" }))
                if let url = URL(string: urlString) { return url }
            }
        }
        return nil
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Main row (always visible)
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 4, height: isExpanded ? 44 : 36)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.body.weight(.medium))
                            .lineLimit(isExpanded ? 3 : 1)
                        HStack(spacing: 4) {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text(event.calendarName)
                            Text("·")
                            Text(event.timeString)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if event.isAllDay {
                        Text("All Day")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(color.opacity(0.15), in: Capsule())
                            .foregroundStyle(color)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                // Expanded detail card
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider().padding(.vertical, 6)
                        
                        // Time range
                        if !event.isAllDay {
                            detailRow(icon: "clock", text: event.timeRangeString)
                        }
                        
                        // Location
                        if let location = event.location, !location.isEmpty {
                            detailRow(icon: "mappin.and.ellipse", text: location)
                        }
                        
                        // Meeting link
                        if let url = meetingURL {
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: meetingIcon(for: url))
                                        .font(.subheadline)
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(.blue, in: RoundedRectangle(cornerRadius: 6))
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Join Meeting")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.blue)
                                        Text(url.host ?? url.absoluteString)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                .padding(10)
                                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        
                        // Organizer
                        if let organizer = event.organizer, !organizer.isEmpty {
                            detailRow(icon: "person", text: "Organized by \(organizer)")
                        }
                        
                        // Attendees
                        if !event.attendees.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.2")
                                        .font(.caption)
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 20)
                                    Text("\(event.attendees.count) attendee\(event.attendees.count == 1 ? "" : "s")")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(event.attendees.prefix(5), id: \.self) { name in
                                    Text("  · \(name)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if event.attendees.count > 5 {
                                    Text("  + \(event.attendees.count - 5) more")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        
                        // Notes
                        if let notes = event.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "note.text")
                                        .font(.caption)
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 20)
                                    Text("Notes")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(6)
                            }
                        }
                        
                        // Calendar name
                        detailRow(icon: "calendar", text: event.calendarName)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private func meetingIcon(for url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.contains("meet.google") { return "video" }
        if host.contains("zoom") { return "video" }
        if host.contains("teams") { return "video" }
        return "link"
    }
}

// MARK: - Filter Sheet

struct CalendarFilterSheet: View {
    @Bindable var calendarManager: CalendarManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(calendarManager.calendars) { cal in
                    Button {
                        calendarManager.toggleCalendar(cal.id)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(cal.color != nil ? Color(cgColor: cal.color!) : Theme.accent)
                                .frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cal.title)
                                    .font(.body)
                                Text(cal.source)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: calendarManager.isCalendarEnabled(cal.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(calendarManager.isCalendarEnabled(cal.id) ? Color(cgColor: cal.color ?? CGColor(red: 1, green: 0.6, blue: 0, alpha: 1)) : .secondary)
                                .font(.title3)
                        }
                    }
                    .tint(.primary)
                }
            }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
