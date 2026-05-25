//
//  ExamDetailView.swift
//  StudyPlanner
//

import SwiftUI

private let kScreenWidth: CGFloat = UIScreen.main.bounds.width

struct ExamDetailView: View {
    @Environment(AppStore.self) private var store
    @State private var isEditing        = false
    @State private var logInput: String = ""
    @State private var browsingDate: Date = Date()
    @State private var showLoggedConfirmation = false
    @State private var showDatePicker   = false
    @FocusState private var inputFocused: Bool

    // ── Day swipe state ───────────────────────────────────────────────────
    @State private var dayOffset:     CGFloat = 0
    @State private var peekDate:      Date?   = nil
    @State private var dragDirection: CGFloat = 1
    @State private var logOffset:     CGFloat = 0   // independent offset for the log section

    private let commitThreshold: CGFloat = kScreenWidth * 0.30
    private var today: Date { Date().startOfDay }

    var body: some View {
        Group {
            if let exam = store.focusedExam {
                content(for: exam)
                    .onAppear {
                        browsingDate = today
                        prefillLogInput(for: exam)
                    }
                    .onChange(of: browsingDate) { _, _ in
                        prefillLogInput(for: exam)
                    }
            }
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
        .scrollDisabled(true)
        .navigationTitle(store.focusedExam?.name ?? "Exam")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isEditing = true
                } label: {
                    Text("Edit")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.appAccentSoft, in: Capsule())
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let exam = store.focusedExam { ExamFormView(mode: .edit(exam)) }
        }
        .sheet(isPresented: $showDatePicker) {
            if let exam = store.focusedExam {
                DatePickerSheet(
                    selected: $browsingDate,
                    earliest: creationDay(for: exam),
                    latest: today
                )
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for exam: Exam) -> some View {
        let earliest        = min(today, creationDay(for: exam))
        let isBrowsingToday = Calendar.current.isDate(browsingDate, inSameDayAs: today)
        let isAtEarliest    = Calendar.current.isDate(browsingDate, inSameDayAs: earliest)
        let overflow        = store.planOverflowsExam
        let progress        = StudyPlanCalculator.progress(for: exam)
        let isComplete      = progress >= 1.0 && !overflow
        let glowColor       = overflow ? Color.red : isComplete ? Color.examGreen : Color.appAccent

        GeometryReader { geo in
            VStack(spacing: 0) {

                // ── Hero — always compact ─────────────────────────────────
                hero(exam: exam, progress: progress, overflow: overflow,
                     isComplete: isComplete, glowColor: glowColor, geo: geo)

                // ── Day carousel ──────────────────────────────────────────
                dayCarousel(earliest: earliest, isBrowsingToday: isBrowsingToday,
                            isAtEarliest: isAtEarliest, glowColor: glowColor, geo: geo)

                Divider().opacity(isComplete ? 0 : 0.4)

                // ── Bottom area — scrollable so everything always fits ─────
                ScrollView {
                    VStack(spacing: 0) {
                        if overflow {
                            overflowBanner(glowColor: glowColor)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if !isComplete {
                            logSection(exam: exam, isBrowsingToday: isBrowsingToday, glowColor: glowColor)
                                .offset(x: logOffset)
                        } else {
                            CompletionSection(exam: exam, accentColor: glowColor)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .clipped()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 15, coordinateSpace: .local)
                        .onChanged { value in
                            let h = abs(value.translation.width)
                            let v = abs(value.translation.height)
                            guard h > v * 2 else { return }
                            let tx = value.translation.width
                            if peekDate == nil {
                                let goingBack = tx > 0
                                if goingBack && isAtEarliest     { return }
                                if !goingBack && isBrowsingToday { return }
                                let delta = goingBack ? -1 : 1
                                if let candidate = Calendar.current.date(byAdding: .day, value: delta, to: browsingDate) {
                                    peekDate      = max(earliest.startOfDay, min(today, candidate.startOfDay))
                                    dragDirection = goingBack ? -1 : 1
                                }
                            }
                            // Move both carousel label and log section together
                            dayOffset = tx
                            logOffset = tx
                        }
                        .onEnded { value in
                            let h = abs(value.translation.width)
                            let v = abs(value.translation.height)
                            if h > v * 2, h > commitThreshold, let next = peekDate {
                                UISelectionFeedbackGenerator().selectionChanged()
                                let target: CGFloat = value.translation.width < 0 ? -kScreenWidth : kScreenWidth
                                withAnimation(.interpolatingSpring(stiffness: 300, damping: 35)) {
                                    dayOffset = target
                                    logOffset = target
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) {
                                    browsingDate = next
                                    dayOffset = 0
                                    logOffset = 0
                                    peekDate = nil
                                }
                            } else {
                                if peekDate != nil {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                withAnimation(.interpolatingSpring(stiffness: 300, damping: 35)) {
                                    dayOffset = 0
                                    logOffset = 0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { peekDate = nil }
                            }
                        }
                )
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private func hero(exam: Exam, progress: Double, overflow: Bool,
                      isComplete: Bool, glowColor: Color, geo: GeometryProxy) -> some View {
        let gradient: LinearGradient = {
            if overflow {
                return LinearGradient(colors: [Color.red.opacity(0.20), Color.red.opacity(0)],
                                      startPoint: .top, endPoint: .bottom)
            } else if isComplete {
                return LinearGradient(colors: [Color.examGreen.opacity(0.22), Color.examGreen.opacity(0)],
                                      startPoint: .top, endPoint: .bottom)
            } else {
                return LinearGradient(colors: [Color.appAccent.opacity(0.18), Color.appAccent.opacity(0)],
                                      startPoint: .top, endPoint: .bottom)
            }
        }()

        ZStack {
            gradient.ignoresSafeArea(edges: .top)
                .animation(.easeOut(duration: 0.5), value: overflow)
                .animation(.easeOut(duration: 0.5), value: isComplete)

            VStack(spacing: 8) {
                Spacer(minLength: 0)

                ProgressRing(
                    progress: progress,
                    lineWidth: 13,
                    diameter: geo.size.height * 0.26,
                    overflowWarning: overflow
                )
                .shadow(color: glowColor.opacity(0.28), radius: 24, y: 8)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatted(exam.completedAmount))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("/ \(formatted(exam.totalAmount)) \(exam.unit.unitNoun)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Stats row — always the same, exam date only
                HStack(spacing: 0) {
                    statCell(label: "Exam date",
                             value: DateFormatters.dayMonth.string(from: exam.date))
                    if overflow {
                        Rectangle()
                            .fill(Color.dividerColor)
                            .frame(width: 1, height: 32)
                        statCell(label: "Expected",
                                 value: expectedCompletionString(for: exam))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

                Spacer(minLength: 0)
            }
        }
        .frame(height: geo.size.height * 0.48)
        .animation(.easeOut(duration: 0.25), value: overflow)
    }

    // MARK: - Day carousel

    @ViewBuilder
    private func dayCarousel(earliest: Date, isBrowsingToday: Bool,
                              isAtEarliest: Bool, glowColor: Color, geo: GeometryProxy) -> some View {
        ZStack {
            ZStack {
                dateLabel(date: browsingDate, isToday: isBrowsingToday)
                    .offset(x: dayOffset)
                if let peek = peekDate {
                    dateLabel(date: peek, isToday: Calendar.current.isDate(peek, inSameDayAs: today))
                        .offset(x: dayOffset + dragDirection * kScreenWidth)
                        .allowsHitTesting(false)
                }
            }
            .clipped()

            HStack {
                if !isAtEarliest {
                    navButton(systemName: "chevron.left") { stepDay(by: -1, earliest: earliest) }
                } else {
                    Color.clear.frame(width: 34, height: 34)
                }
                Spacer()
                if !isBrowsingToday {
                    navButton(systemName: "chevron.right") { stepDay(by: 1, earliest: earliest) }
                } else {
                    Color.clear.frame(width: 34, height: 34)
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: geo.size.height * 0.09)
        .background(glowColor.opacity(0.04))
        .gesture(
            DragGesture(minimumDistance: 15, coordinateSpace: .local)
                .onChanged { value in
                    let h = abs(value.translation.width)
                    let v = abs(value.translation.height)
                    guard h > v * 1.5 else { return }
                    let tx = value.translation.width
                    if peekDate == nil {
                        let goingBack = tx > 0
                        if goingBack && isAtEarliest     { return }
                        if !goingBack && isBrowsingToday { return }
                        let delta = goingBack ? -1 : 1
                        if let candidate = Calendar.current.date(byAdding: .day, value: delta, to: browsingDate) {
                            peekDate      = max(earliest.startOfDay, min(today, candidate.startOfDay))
                            dragDirection = goingBack ? -1 : 1
                        }
                    }
                    dayOffset = tx
                }
                .onEnded { value in
                    let h = abs(value.translation.width)
                    let v = abs(value.translation.height)
                    if h > v * 1.5, h > commitThreshold, let next = peekDate {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.interpolatingSpring(stiffness: 300, damping: 35)) {
                            dayOffset = value.translation.width < 0 ? -kScreenWidth : kScreenWidth
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) {
                            browsingDate = next; dayOffset = 0; peekDate = nil
                        }
                    } else {
                        if peekDate != nil {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        withAnimation(.interpolatingSpring(stiffness: 300, damping: 35)) { dayOffset = 0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { peekDate = nil }
                    }
                }
        )
    }

    // MARK: - Overflow banner (compact, horizontally scrolling chips)

    @ViewBuilder
    private func overflowBanner(glowColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red)
                Text("Not enough time — try one of these:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.red)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    suggestionChip(icon: "clock.arrow.2.circlepath",
                                   label: "Extend hours",
                                   action: { isEditing = true })
                    suggestionChip(icon: "calendar.badge.plus",
                                   label: "Move exam date",
                                   action: { isEditing = true })
                    suggestionChip(icon: "square.and.pencil",
                                   label: "Log more today",
                                   action: nil)
                    suggestionChip(icon: "xmark.circle",
                                   label: "Free calendar",
                                   action: nil)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .background(Color.red.opacity(0.04))
    }

    private func suggestionChip(icon: String, label: String, action: (() -> Void)?) -> some View {
        let chip = HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.red)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )

        if let action {
            return AnyView(Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            } label: { chip }.buttonStyle(.plain))
        } else {
            return AnyView(chip)
        }
    }

    // MARK: - Log section

    @ViewBuilder
    private func logSection(exam: Exam, isBrowsingToday: Bool, glowColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                HStack(spacing: 5) {
                    if !isBrowsingToday {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    Text(exam.unit == .pages ? "Pages studied" : "Hours studied")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.5)
                }
                Spacer()
                if let logged = store.loggedAmount(examID: exam.id, on: browsingDate) {
                    Text("Logged: \(formatted(logged)) \(exam.unit.unitNoun)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.examGreen)
                } else if let planned = plannedForDay(exam: exam) {
                    Text("Planned: \(formatted(planned)) \(exam.unit.unitNoun)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Input + submit
            HStack(spacing: 10) {
                HStack {
                    TextField(exam.unit == .pages ? "e.g. 20" : "e.g. 3",
                              text: $logInput)
                        .keyboardType(.decimalPad)
                        .focused($inputFocused)
                        .font(.system(size: 17))
                        .onSubmit { submitLog(for: exam) }
                    Text(exam.unit.unitNoun)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(inputIsValid ? glowColor : Color(.systemGray4),
                                lineWidth: inputIsValid ? 1.5 : 1)
                )
                .animation(.easeOut(duration: 0.15), value: inputIsValid)

                Button { submitLog(for: exam) } label: {
                    ZStack {
                        if showLoggedConfirmation {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(inputIsValid ? glowColor : Color(.systemGray4))
                    )
                    .animation(.easeOut(duration: 0.15), value: inputIsValid)
                }
                .disabled(!inputIsValid)
            }

            // "Log planned" shortcut
            if store.loggedAmount(examID: exam.id, on: browsingDate) == nil,
               let planned = plannedForDay(exam: exam) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    logInput = formatted(planned)
                    submitLog(for: exam)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars").font(.system(size: 12))
                        Text("Log \(formatted(planned)) \(exam.unit.unitNoun)")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(glowColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(glowColor.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            isBrowsingToday ? Color.clear : Color.orange.opacity(0.04)
        )
        .animation(.easeOut(duration: 0.25), value: isBrowsingToday)
    }

    // MARK: - Date label

    private func dateLabel(date: Date, isToday: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showDatePicker = true
        } label: {
            VStack(spacing: 2) {
                Text(isToday ? "Today" : "Past day")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
                HStack(spacing: 5) {
                    Text(DateFormatters.dayMonth.string(from: date))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subviews

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
    }

    private func navButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 34, height: 34)
                .background(Color.appAccentSoft, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func creationDay(for exam: Exam) -> Date {
        store.logsForExam(id: exam.id).map({ $0.date.startOfDay }).min() ?? today
    }

    private func stepDay(by delta: Int, earliest: Date) {
        guard let next = Calendar.current.date(byAdding: .day, value: delta, to: browsingDate) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        browsingDate = max(earliest, min(today, next.startOfDay))
    }

    private func plannedForDay(exam: Exam) -> Double? {
        guard let hours = store.plannedHours(examID: exam.id, on: browsingDate),
              hours > 0 else { return nil }
        switch exam.unit {
        case .hours: return hours
        case .pages: return hours * exam.pagesPerHour
        }
    }

    private func prefillLogInput(for exam: Exam) {
        if let logged = store.loggedAmount(examID: exam.id, on: browsingDate) {
            logInput = formatted(logged)
        } else {
            logInput = ""
        }
    }

    private var inputIsValid: Bool {
        let cleaned = logInput.trimmingCharacters(in: .whitespaces)
                              .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned) else { return false }
        return value >= 0 && value <= 24
    }

    private var parsedAmount: Double? {
        let cleaned = logInput.trimmingCharacters(in: .whitespaces)
                              .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0, value <= 24 else { return nil }
        return value
    }

    private func submitLog(for exam: Exam) {
        guard let amount = parsedAmount else { return }
        store.logStudy(amount: amount, on: browsingDate)
        inputFocused = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.3)) { showLoggedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.3)) { showLoggedConfirmation = false }
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func expectedCompletionString(for exam: Exam) -> String {
        if let date = StudyPlanCalculator.expectedCompletionDate(for: exam) {
            return DateFormatters.dayMonth.string(from: date)
        }
        return "—"
    }
}

// MARK: - Completion section

private struct CompletionSection: View {
    let exam: Exam
    let accentColor: Color

    @State private var appeared  = false
    @State private var showDots  = false

    private let colors: [Color] = [.examGreen, .appAccent, .yellow, .orange, .pink, .teal]

    private struct Particle: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let color: Color
        let delay: Double
    }

    private var particles: [Particle] {
        (0..<22).map { i in
            let angle  = Double(i) / 22.0 * 2 * .pi
            let radius = CGFloat(40 + (i % 5) * 18)
            return Particle(
                id:    i,
                x:     cos(angle) * radius + CGFloat((i % 3) - 1) * 12,
                y:     sin(angle) * radius * 0.5 + CGFloat((i % 3) - 1) * 8,
                size:  CGFloat(4 + (i % 4) * 2),
                color: colors[i % colors.count],
                delay: Double(i) * 0.018
            )
        }
    }

    var body: some View {
        ZStack {
            accentColor.opacity(0.05)

            ForEach(particles) { p in
                Circle()
                    .fill(p.color.opacity(0.75))
                    .frame(width: p.size, height: p.size)
                    .offset(x: p.x, y: p.y)
                    .opacity(showDots ? 1 : 0)
                    .scaleEffect(showDots ? 1 : 0.1)
                    .animation(.easeOut(duration: 0.5).delay(p.delay), value: showDots)
            }

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.examGreen.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(Color.examGreen.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 72, height: 72)
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.examGreen)
                }
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)

                VStack(spacing: 6) {
                    Text("All done!")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.examGreen)
                    Text("You've covered everything for \(exam.name)")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Exam on \(DateFormatters.dayMonth.string(from: exam.date)) — you're ready 🎓")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.examGreen.opacity(0.8))
                        .padding(.top, 2)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.05)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showDots = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeIn(duration: 0.4)) { showDots = false }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - Date picker sheet

private struct DatePickerSheet: View {
    @Binding var selected: Date
    let earliest: Date
    let latest: Date

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Date = Date()

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("", selection: $draft, in: earliest...latest,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Color.appAccent)
                    .padding(.horizontal, 8)
                Spacer()
            }
            .navigationTitle("Jump to date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.appAccent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Go") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selected = draft.startOfDay
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                }
            }
            .onAppear { draft = selected }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack { ExamDetailView() }
        .environment(AppStore.preview)
}
