//
//  CalendarDayView.swift
//  StudyPlanner
//

import SwiftUI

// MARK: - Layout helper

private struct LayoutEvent {
    let event: UserEvent
    let column: Int
    let columnCount: Int
}

private func resolveOverlaps(_ events: [UserEvent]) -> [LayoutEvent] {
    guard !events.isEmpty else { return [] }
    let sorted = events.sorted {
        if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
        return $0.endDate > $1.endDate
    }
    var columnEnds: [Date] = []
    var assignments: [(event: UserEvent, column: Int)] = []
    for event in sorted {
        if let col = columnEnds.indices.first(where: { columnEnds[$0] <= event.startDate }) {
            columnEnds[col] = event.endDate
            assignments.append((event, col))
        } else {
            columnEnds.append(event.endDate)
            assignments.append((event, columnEnds.count - 1))
        }
    }
    var result: [LayoutEvent] = []
    var groupStart = 0
    var groupMaxEnd: Date = sorted[0].endDate

    func flush(upTo end: Int) {
        let groupAssignments = Array(assignments[groupStart..<end])
        let groupColumns = (groupAssignments.map(\.column).max() ?? 0) + 1
        for a in groupAssignments {
            result.append(LayoutEvent(event: a.event, column: a.column,
                                      columnCount: groupColumns))
        }
    }
    for i in assignments.indices {
        let a = assignments[i]
        if i > groupStart && a.event.startDate >= groupMaxEnd {
            flush(upTo: i)
            groupStart  = i
            groupMaxEnd = a.event.endDate
        } else {
            if a.event.endDate > groupMaxEnd { groupMaxEnd = a.event.endDate }
        }
    }
    flush(upTo: assignments.count)
    return result
}

// MARK: - Haptics

private enum Haptics {
    static let selection  = UISelectionFeedbackGenerator()
    static let light      = UIImpactFeedbackGenerator(style: .light)
    static let success    = UINotificationFeedbackGenerator()

    static func prepareAll() {
        selection.prepare()
        light.prepare()
        success.prepare()
    }
}

// MARK: - Main view

private let screenWidth = UIScreen.main.bounds.width

struct CalendarDayView: View {
    @Environment(AppStore.self) private var store
    @Binding var selectedDate: Date

    private let hours = Array(0...24)
    private let commitThreshold: CGFloat = screenWidth * 0.35

    // ── Transition state ──────────────────────────────────────────────────
    // offset: live position of the current+peek pair during drag & animation.
    // peekDate: the adjacent day/week being shown alongside the current one.
    // direction: +1 = peek is to the right (going back), -1 = peek is to left (going forward).
    @State private var dayOffset:  CGFloat = 0
    @State private var weekOffset: CGFloat = 0
    @State private var peekDayDate:  Date? = nil
    @State private var peekWeekDate: Date? = nil
    @State private var dayDirection:  CGFloat = 1
    @State private var weekDirection: CGFloat = 1

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            weekStripLayer
            Divider().opacity(0.4)
            timelineLayer
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { Haptics.prepareAll() }
    }

    // MARK: - Week strip layer

    @ViewBuilder
    private var weekStripLayer: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                WeekStripView(selectedDate: $selectedDate)
                    .frame(width: w)
                    .offset(x: weekOffset)

                if let peekDate = peekWeekDate {
                    WeekStripView(selectedDate: .constant(peekDate))
                        .frame(width: w)
                        .offset(x: weekOffset + weekDirection * w)
                }
            }
            .clipped()
        }
        .frame(height: 74)
        .background(Color(.systemBackground))
        .gesture(weekSwipeGesture)
    }

    // MARK: - Timeline layer

    @ViewBuilder
    private var timelineLayer: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .leading) {
                        TimelineView(
                            hours: hours,
                            selectedDate: selectedDate,
                            scheduledBlocks: store.scheduledBlocks(on: selectedDate),
                            userEvents: store.userEvents(on: selectedDate)
                        )
                        .frame(width: w)
                        .offset(x: dayOffset)
                        .id(selectedDate)
                        .animation(nil, value: selectedDate)

                        if let peekDate = peekDayDate {
                            TimelineView(
                                hours: hours,
                                selectedDate: peekDate,
                                scheduledBlocks: store.scheduledBlocks(on: peekDate),
                                userEvents: store.userEvents(on: peekDate)
                            )
                            .frame(width: w)
                            .offset(x: dayOffset + dayDirection * w)
                            .allowsHitTesting(false)
                            .id(peekDate)
                            .animation(nil, value: peekDate)
                        }
                    }
                    .frame(height: CGFloat(hours.count) * 56 + 8)
                }
                .scrollDisabled(dayOffset != 0)
                .clipped()
                .onAppear { proxy.scrollTo(7, anchor: .top) }
                .simultaneousGesture(daySwipeGesture)
            }
        }
    }

    // MARK: - Gestures

    private var weekSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let h = abs(value.translation.width)
                let v = abs(value.translation.height)
                guard h > v * 1.2 else { return }
                let tx = value.translation.width
                if peekWeekDate == nil {
                    // Swiping left (tx < 0) → go forward (+7), peek comes from right (+1*w)
                    // Swiping right (tx > 0) → go back (-7), peek comes from left (-1*w)
                    weekDirection = tx < 0 ? 1 : -1
                    let delta = tx < 0 ? 7 : -7
                    peekWeekDate = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate)
                }
                weekOffset = tx
            }
            .onEnded { value in
                let h = abs(value.translation.width)
                let v = abs(value.translation.height)
                if h > v * 1.5, h > commitThreshold, let next = peekWeekDate {
                    Haptics.selection.selectionChanged()
                    withAnimation(.easeOut(duration: 0.22)) {
                        weekOffset = value.translation.width < 0 ? -screenWidth : screenWidth
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        selectedDate = next
                        peekWeekDate = nil
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { weekOffset = 0 }
                    }
                } else {
                    if peekWeekDate != nil { Haptics.light.impactOccurred() }
                    withAnimation(.easeOut(duration: 0.22)) {
                        weekOffset = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        peekWeekDate = nil
                    }
                }
            }
    }

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let h = abs(value.translation.width)
                let v = abs(value.translation.height)
                guard h > v * 1.2 else { return }
                let tx = value.translation.width
                if peekDayDate == nil {
                    dayDirection = tx < 0 ? 1 : -1
                    let delta = tx < 0 ? 1 : -1
                    peekDayDate = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate)
                }
                dayOffset = tx
            }
            .onEnded { value in
                let h = abs(value.translation.width)
                let v = abs(value.translation.height)
                if h > v * 1.5, h > commitThreshold, let next = peekDayDate {
                    Haptics.selection.selectionChanged()
                    let target: CGFloat = value.translation.width < 0 ? -screenWidth : screenWidth
                    withAnimation(.easeOut(duration: 0.22)) {
                        dayOffset = target
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        // Swap date first, then snap offset to 0 without animation.
                        // The content is now identical to what was peeking, so
                        // the instant reset is invisible to the user.
                        selectedDate = next
                        peekDayDate  = nil
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { dayOffset = 0 }
                    }
                } else {
                    if peekDayDate != nil { Haptics.light.impactOccurred() }
                    withAnimation(.easeOut(duration: 0.22)) {
                        dayOffset = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        peekDayDate = nil
                    }
                }
            }
    }
}

// MARK: - Week strip

private struct WeekStripView: View {
    @Binding var selectedDate: Date

    private var weekDays: [Date] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: selectedDate)
        let daysFromMonday = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: selectedDate)!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                Button {
                    Haptics.light.impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) { selectedDate = day }
                } label: {
                    VStack(spacing: 5) {
                        Text(shortLabel(for: day))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        ZStack {
                            Circle()
                                .fill(isSelected(day) ? Color.appAccent : Color.clear)
                                .frame(width: 34, height: 34)
                            if isToday(day) && !isSelected(day) {
                                Circle()
                                    .stroke(Color.appAccent, lineWidth: 1.5)
                                    .frame(width: 34, height: 34)
                            }
                            Text("\(Calendar.current.component(.day, from: day))")
                                .font(.system(size: 16, weight: isToday(day) ? .bold : .regular))
                                .foregroundStyle(isSelected(day) ? Color.white : Color.primary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.15), value: isSelected(day))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private func isSelected(_ d: Date) -> Bool { Calendar.current.isDate(d, inSameDayAs: selectedDate) }
    private func isToday(_ d: Date) -> Bool { Calendar.current.isDateInToday(d) }
    private func shortLabel(for date: Date) -> String {
        ["S","M","T","W","T","F","S"][Calendar.current.component(.weekday, from: date) - 1]
    }
}

// MARK: - Timeline

private struct TimelineView: View {
    let hours: [Int]
    let selectedDate: Date
    let scheduledBlocks: [ScheduledBlock]
    let userEvents: [UserEvent]

    private let hourHeight: CGFloat = 56
    private let labelWidth: CGFloat = 48
    private let gutter:     CGFloat = 2

    @State private var editingEvent: UserEvent? = nil
    // Ticks every minute to keep the now-line current.
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var layoutEvents: [LayoutEvent] { resolveOverlaps(userEvents) }
    private var canvasHeight: CGFloat { CGFloat(hours.count) * hourHeight }
    private var trackWidth: CGFloat {
        UIScreen.main.bounds.width - 20 - labelWidth - 4 - 10
    }

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    // Fractional hour of current time (e.g. 14.5 = 2:30 PM).
    private var nowFrac: Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0
    }

    // Y position of the now-line within the canvas.
    private var nowY: CGFloat {
        let origin = Double(hours.first ?? 0)
        return CGFloat(nowFrac - origin) * hourHeight + 8  // +8 for .padding(.top, 8)
    }

    // Short time string shown on the left of the now-line e.g. "2:34"
    private var nowLabel: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let h = c.hour ?? 0
        let m = c.minute ?? 0
        let hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d", hour12, m)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {

            // ── Hour grid ─────────────────────────────────────────────────
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { hour in
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 0.5)
                            .padding(.leading, labelWidth)
                        Text(hourLabel(hour))
                            .font(.system(size: 11))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .frame(width: labelWidth - 6, alignment: .trailing)
                            .offset(y: -7)
                    }
                    .frame(height: hourHeight, alignment: .top)
                    .id(hour)
                }
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 0.5)
                    .padding(.leading, labelWidth)
            }

            // ── Scheduled study blocks ────────────────────────────────────
            ForEach(scheduledBlocks) { block in
                blockView(
                    title: "Study",
                    subtitle: durationLabel(block.duration),
                    start: block.date, end: block.endDate,
                    accent: Color.appAccent, bg: Color.appAccentSoft,
                    dashed: false,
                    xOffset: labelWidth + 4, width: trackWidth
                )
                .allowsHitTesting(false)
            }

            // ── User events ───────────────────────────────────────────────
            ForEach(layoutEvents, id: \.event.id) { le in
                let colW = (trackWidth - gutter * CGFloat(le.columnCount - 1)) / CGFloat(le.columnCount)
                let xOff = labelWidth + 4 + CGFloat(le.column) * (colW + gutter)
                blockView(
                    title: le.event.title,
                    subtitle: le.event.notes.isEmpty ? nil : le.event.notes,
                    start: le.event.startDate, end: le.event.endDate,
                    accent: le.event.eventColor.swiftUIColor,
                    bg: le.event.eventColor.swiftUIColor.opacity(0.10),
                    dashed: false,
                    xOffset: xOff, width: colW
                )
                .onTapGesture {
                    Haptics.light.impactOccurred()
                    editingEvent = le.event
                }
            }

            // ── Now line (today only) ─────────────────────────────────────
            if isToday {
                HStack(alignment: .center, spacing: 0) {
                    // Current time label in place of the hour label
                    Text(nowLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .frame(width: labelWidth - 6, alignment: .trailing)

                    // Red line across the full track
                    Rectangle()
                        .fill(Color.red.opacity(0.85))
                        .frame(height: 1.5)
                        .padding(.leading, 4)
                        .padding(.trailing, 10)
                }
                .offset(y: nowY)
                .allowsHitTesting(false)
            }
        }
        .frame(height: canvasHeight)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .sheet(item: $editingEvent) { event in EventEditSheet(event: event, occurrenceDay: selectedDate) }
        .onReceive(timer) { now = $0 }
    }

    @ViewBuilder
    private func blockView(
        title: String, subtitle: String?,
        start: Date, end: Date,
        accent: Color, bg: Color, dashed: Bool,
        xOffset: CGFloat, width: CGFloat
    ) -> some View {
        let origin  = Double(hours.first ?? 0)
        let startFr = frac(start)
        let endFr   = frac(end)
        let topY    = CGFloat(startFr - origin) * hourHeight
        let blockH  = max(hourHeight * 0.38, CGFloat(endFr - startFr) * hourHeight)

        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent).lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(accent.opacity(0.75)).lineLimit(1)
                }
            }
            .padding(.leading, 7).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width, height: blockH, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 7).fill(bg))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(accent.opacity(dashed ? 0.5 : 0.2),
                        style: dashed ? StrokeStyle(lineWidth: 1, dash: [4, 3])
                                      : StrokeStyle(lineWidth: 0.5))
        )
        .offset(x: xOffset, y: topY)
    }

    private func frac(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0:  return "12 AM"
        case 12: return "12 PM"
        default:
            let suffix = hour >= 12 ? "PM" : "AM"
            return "\(hour > 12 ? hour - 12 : hour) \(suffix)"
        }
    }

    private func durationLabel(_ h: Double) -> String {
        h.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(h))h" : String(format: "%.1fh", h)
    }
}

// MARK: - Event detail / edit / delete sheet

private struct EventEditSheet: View {
    let event: UserEvent
    let occurrenceDay: Date

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showEditChoice   = false
    @State private var showDeleteChoice = false
    @State private var showEditForm     = false
    @State private var editScope: EditScope = .thisOnly

    enum EditScope { case thisOnly, thisAndFuture }

    private var isRepeating: Bool { event.repeatFrequency != .never }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Circle().fill(event.eventColor.swiftUIColor).frame(width: 10, height: 10)
                        Text(event.title).font(.title3.weight(.bold))
                    }
                    Divider().opacity(0.5)
                    row(icon: "calendar",
                        text: event.startDate.formatted(date: .long, time: .omitted))
                    row(icon: "clock",
                        text: "\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))")
                    if isRepeating { row(icon: "arrow.clockwise", text: event.repeatFrequency.rawValue) }
                    if !event.notes.isEmpty { row(icon: "note.text", text: event.notes) }
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
                .padding()

                Spacer()

                VStack(spacing: 10) {
                    Button {
                        Haptics.light.impactOccurred()
                        if isRepeating { showEditChoice = true }
                        else { editScope = .thisOnly; showEditForm = true }
                    } label: {
                        Label("Edit event", systemImage: "pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.appAccent))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    Button(role: .destructive) {
                        Haptics.light.impactOccurred()
                        if isRepeating { showDeleteChoice = true }
                        else { store.deleteUserEvent(id: event.id); dismiss() }
                    } label: {
                        Label("Delete event", systemImage: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.7), lineWidth: 1))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            }
            .navigationTitle("Event details").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.appAccent)
                }
            }
            .confirmationDialog("Edit recurring event",
                                isPresented: $showEditChoice, titleVisibility: .visible) {
                Button("This event only") { editScope = .thisOnly; showEditForm = true }
                Button("This and all future events") { editScope = .thisAndFuture; showEditForm = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Do you want to edit just this occurrence or this and all future ones?")
            }
            .confirmationDialog("Delete recurring event",
                                isPresented: $showDeleteChoice, titleVisibility: .visible) {
                Button("This event only", role: .destructive) {
                    store.deleteOccurrence(event, on: occurrenceDay); dismiss()
                }
                Button("This and all future events", role: .destructive) {
                    store.deleteThisAndFuture(event, from: occurrenceDay); dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Do you want to delete just this occurrence or this and all future ones?")
            }
            .sheet(isPresented: $showEditForm) {
                EventFormView(
                    mode: .edit(event),
                    onSave: { edited in
                        switch editScope {
                        case .thisOnly:
                            if isRepeating {
                                store.updateOccurrence(edited, originalSeries: event, on: occurrenceDay)
                            } else {
                                store.saveUserEvent(edited)
                            }
                        case .thisAndFuture:
                            store.updateThisAndFuture(edited, originalSeries: event, from: occurrenceDay)
                        }
                        dismiss()
                    }
                )
            }
        }
    }

    private func row(icon: String, text: String) -> some View {
        Label(text, systemImage: icon).font(.subheadline).foregroundStyle(.secondary)
    }
}

#Preview {
    CalendarDayView(selectedDate: .constant(Date()))
        .environment(AppStore(repository: LocalExamRepository()))
}
