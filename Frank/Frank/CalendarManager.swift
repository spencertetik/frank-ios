import EventKit
import Foundation
import Observation

@Observable
@MainActor
final class CalendarManager {
    var upcomingEvents: [CalendarEvent] = []
    var authorizationStatus: EKAuthorizationStatus = .notDetermined
    var calendars: [CalendarInfo] = []
    var excludedCalendarIds: Set<String> = []

    private let store = EKEventStore()
    private static let excludedKey = "CalendarManager.excludedCalendarIds"
    private static let hasLaunchedKey = "CalendarManager.hasLaunchedBefore"

    struct CalendarEvent: Identifiable {
        let id: String
        let title: String
        let startDate: Date
        let endDate: Date
        let calendarName: String
        let calendarColor: CGColor?
        let isAllDay: Bool
        let location: String?
        let notes: String?
        let url: URL?
        let attendees: [String] // display names or emails
        let organizer: String?

        var timeString: String {
            if isAllDay { return "All day" }
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: startDate)
        }

        var timeRangeString: String {
            if isAllDay { return "All day" }
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
        }

        var relativeDay: String {
            let cal = Calendar.current
            if cal.isDateInToday(startDate) { return "Today" }
            if cal.isDateInTomorrow(startDate) { return "Tomorrow" }
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: startDate)
        }

        var minutesUntil: Int {
            Int(startDate.timeIntervalSinceNow / 60)
        }
    }

    struct CalendarInfo: Identifiable {
        let id: String
        let title: String
        let source: String
        let color: CGColor?
    }

    init() {
        loadExcludedCalendarIds()
    }

    // MARK: - Persistence

    private func loadExcludedCalendarIds() {
        if let saved = UserDefaults.standard.array(forKey: Self.excludedKey) as? [String] {
            excludedCalendarIds = Set(saved)
        }
    }

    func saveExcludedCalendarIds() {
        UserDefaults.standard.set(Array(excludedCalendarIds), forKey: Self.excludedKey)
        fetchEvents()
    }

    func toggleCalendar(_ id: String) {
        if excludedCalendarIds.contains(id) {
            excludedCalendarIds.remove(id)
        } else {
            excludedCalendarIds.insert(id)
        }
        saveExcludedCalendarIds()
    }

    func isCalendarEnabled(_ id: String) -> Bool {
        !excludedCalendarIds.contains(id)
    }

    // MARK: - Access

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            if granted {
                loadCalendars()
                applyDefaultExclusions()
                fetchEvents()
            }
        } catch {
            print("Calendar access error: \(error)")
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }

    func checkAccess() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if authorizationStatus == .fullAccess {
            loadCalendars()
            applyDefaultExclusions()
            fetchEvents()
        }
    }

    // MARK: - Data

    func loadCalendars() {
        let ekCalendars = store.calendars(for: .event)
        calendars = ekCalendars.map { cal in
            CalendarInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                source: cal.source.title,
                color: cal.cgColor
            )
        }
    }

    private func applyDefaultExclusions() {
        let hasLaunched = UserDefaults.standard.bool(forKey: Self.hasLaunchedKey)
        guard !hasLaunched else { return }
        UserDefaults.standard.set(true, forKey: Self.hasLaunchedKey)

        let defaultExcluded = ["Birthdays", "US Holidays", "Holidays", "Other"]
        let ekCalendars = store.calendars(for: .event)
        for cal in ekCalendars {
            if defaultExcluded.contains(where: { cal.title.localizedCaseInsensitiveContains($0) }) {
                excludedCalendarIds.insert(cal.calendarIdentifier)
            }
        }
        saveExcludedCalendarIds()
    }

    func fetchEvents() {
        guard authorizationStatus == .fullAccess else { return }

        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: now)!

        // Build filtered calendar list
        let allCalendars = store.calendars(for: .event)
        let filteredCalendars = allCalendars.filter { !excludedCalendarIds.contains($0.calendarIdentifier) }
        guard !filteredCalendars.isEmpty else {
            upcomingEvents = []
            return
        }

        let predicate = store.predicateForEvents(withStart: now, end: endDate, calendars: filteredCalendars)
        let ekEvents = store.events(matching: predicate)

        upcomingEvents = ekEvents
            .sorted { $0.startDate < $1.startDate }
            .prefix(30)
            .map { event in
                CalendarEvent(
                    id: event.eventIdentifier,
                    title: event.title ?? "Untitled",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    calendarName: event.calendar.title,
                    calendarColor: event.calendar.cgColor,
                    isAllDay: event.isAllDay,
                    location: event.location,
                    notes: event.notes,
                    url: event.url,
                    attendees: event.attendees?.compactMap { $0.name ?? ($0.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")) } ?? [],
                    organizer: event.organizer?.name ?? (event.organizer?.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""))
                )
            }
        
        syncToWidgets()
        syncToMissionControl()
    }

    /// Sync events to Mission Control dashboard
    private func syncToMissionControl() {
        let formatter = ISO8601DateFormatter()
        let events = upcomingEvents.map { event -> [String: Any] in
            [
                "title": event.title,
                "start": event.isAllDay ? "All Day" : formatter.string(from: event.startDate),
                "end": event.isAllDay ? "" : formatter.string(from: event.endDate),
                "calendar": event.calendarName,
                "isAllDay": event.isAllDay,
                "location": event.location ?? ""
            ]
        }

        let useTailscale = UserDefaults.standard.bool(forKey: "useTailscale")
        let localHost = UserDefaults.standard.string(forKey: "gatewayHost") ?? "192.168.1.197"
        let tailscaleHost = UserDefaults.standard.string(forKey: "gatewayHostTailscale") ?? "100.118.254.15"
        let host = useTailscale ? tailscaleHost : localHost
        guard let url = URL(string: "http://\(host):3002/api/calendar"),
              let body = try? JSONSerialization.data(withJSONObject: ["events": events]) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        URLSession.shared.dataTask(with: request).resume()
    }

    /// Sync events to App Groups shared storage for widgets
    private func syncToWidgets() {
        let formatter = ISO8601DateFormatter()
        let events = upcomingEvents.prefix(5).map { event -> [String: String] in
            [
                "title": event.title,
                "start": formatter.string(from: event.startDate),
                "calendar": event.calendarName
            ]
        }
        SharedState.updateEvents(events)
    }
    
    /// Sync events to the gateway so Frank can see your calendar
    func syncToGateway(_ gateway: GatewayClient) {
        guard !upcomingEvents.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let syncEvents = upcomingEvents.map { event in
            GatewayClient.CalendarSyncEvent(
                title: event.title,
                start: event.isAllDay ? "All Day" : formatter.string(from: event.startDate),
                end: event.isAllDay ? "" : formatter.string(from: event.endDate),
                calendar: event.calendarName,
                isAllDay: event.isAllDay,
                location: event.location
            )
        }

        gateway.syncCalendar(events: syncEvents)
    }

    /// Get events happening in the next N minutes (for notifications/alerts)
    func eventsComingSoon(withinMinutes minutes: Int = 30) -> [CalendarEvent] {
        upcomingEvents.filter { event in
            let mins = event.minutesUntil
            return mins > 0 && mins <= minutes
        }
    }

    /// Get today's events only
    var todayEvents: [CalendarEvent] {
        upcomingEvents.filter { Calendar.current.isDateInToday($0.startDate) }
    }
}
