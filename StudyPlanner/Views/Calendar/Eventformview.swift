//
//  EventFormView.swift
//  StudyPlanner
//

import SwiftUI

struct EventFormView: View {
    enum Mode {
        case create(defaultDate: Date)
        case edit(UserEvent)
    }

    let mode: Mode
    /// Optional callback — when set, called instead of store.saveUserEvent.
    var onSave: ((UserEvent) -> Void)? = nil

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var repeatFrequency: RepeatFrequency = .never
    @State private var eventColor: EventColor = .preset(.red)
    @State private var notes: String = ""

    /// Tracks the previous start day independently of onChange firing frequency,
    /// preventing the end-date day-shift from applying twice in one gesture.
    @State private var lastStartDay: Date = Calendar.current.startOfDay(for: Date())

    @State private var showColorPicker     = false
    @State private var showValidationErrors = false

    private var isEditing: Bool { if case .edit = mode { return true }; return false }
    private var editingID: UUID? { if case let .edit(e) = mode { return e.id }; return nil }
    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && endDate > startDate
    }

    private var validationErrors: [String] {
        var errors: [String] = []
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Event name is required")
        }
        if endDate <= startDate {
            errors.append("End time must be after start time")
        }
        return errors
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // ── Name ──────────────────────────────────────────────
                    card(invalid: showValidationErrors && title.trimmingCharacters(in: .whitespaces).isEmpty) {
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Event name")
                            TextField("Enter event name", text: $title)
                                .font(.system(size: 16))
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                    !title.isEmpty ? Color.appAccent.opacity(0.5) : Color(.systemGray4), lineWidth: 1))
                        }
                    }

                    // ── Start / End ───────────────────────────────────────
                    card(invalid: showValidationErrors && endDate <= startDate) {
                        VStack(spacing: 0) {
                            HStack {
                                fieldLabel("Start")
                                Spacer()
                                DatePicker("", selection: $startDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                                    .tint(Color.appAccent)
                                    .onChange(of: startDate) { _, new in
                                        // Use lastStartDay to guard against double-fires from
                                        // the split date/time pickers.
                                        let cal = Calendar.current
                                        let newDay = cal.startOfDay(for: new)
                                        guard newDay != lastStartDay else { return }
                                        lastStartDay = newDay

                                        // Transplant the end's time-of-day onto the new start date,
                                        // so end lands on the same day as the new start (not +1).
                                        let endComponents = cal.dateComponents([.hour, .minute], from: endDate)
                                        if let relocated = cal.date(bySettingHour: endComponents.hour ?? 0,
                                                                    minute: endComponents.minute ?? 0,
                                                                    second: 0, of: newDay) {
                                            // If end would be at or before new start, snap to start + 1h.
                                            endDate = relocated > new ? relocated : new.addingTimeInterval(3600)
                                        }
                                    }
                                DatePicker("", selection: $startDate, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                                    .tint(Color.appAccent)
                                    .onChange(of: startDate) { _, new in if endDate <= new { endDate = new.addingTimeInterval(3600) } }
                            }

                            Divider().opacity(0.5).padding(.vertical, 10)

                            HStack {
                                fieldLabel("End")
                                Spacer()
                                DatePicker("", selection: $endDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                                    .tint(Color.appAccent)
                                DatePicker("", selection: $endDate, in: startDate.addingTimeInterval(60)..., displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                                    .tint(Color.appAccent)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    // ── Repeat + Color ────────────────────────────────────
                    card {
                        VStack(spacing: 0) {
                            HStack {
                                fieldLabel("Repeat")
                                Spacer()
                                Menu {
                                    ForEach(RepeatFrequency.allCases) { freq in
                                        Button(freq.rawValue) { repeatFrequency = freq }
                                    }
                                } label: {
                                    pill(text: repeatFrequency.rawValue, chevron: true) {}
                                }
                                .tint(Color.appAccent)
                                .buttonStyle(.plain)
                            }

                            Divider().opacity(0.5).padding(.vertical, 10)

                            // Color row — tapping opens the full picker sheet.
                            Button { showColorPicker = true } label: {
                                HStack {
                                    fieldLabel("Color")
                                    Spacer()
                                    HStack(spacing: 7) {
                                        Circle()
                                            .fill(eventColor.swiftUIColor)
                                            .frame(width: 18, height: 18)
                                        Text(eventColor.displayName)
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(.primary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // ── Notes ─────────────────────────────────────────────
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Notes")
                            TextField("Add notes...", text: $notes, axis: .vertical)
                                .lineLimit(4, reservesSpace: true)
                                .font(.system(size: 15))
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 1))
                        }
                    }

                    // ── Validation errors ────────────────────────────────
                    if showValidationErrors && !validationErrors.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(validationErrors, id: \.self) { error in
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(Color.red)
                                        .font(.system(size: 13))
                                    Text(error)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.red)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.08))
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if isEditing {
                        Button(role: .destructive) {
                            if let id = editingID { store.deleteUserEvent(id: id) }
                            dismiss()
                        } label: {
                            Label("Delete event", systemImage: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.7), lineWidth: 1))
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 2).padding(.bottom, 8)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.immediately)
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                )
            }
            .navigationTitle(isEditing ? "Edit event" : "New event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if isValid { save() }
                        else { withAnimation { showValidationErrors = true } }
                    } label: {
                        Text(isEditing ? "Save" : "Add")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }
            .onAppear(perform: prefill)
            .sheet(isPresented: $showColorPicker) {
                ColorPickerSheet(selection: $eventColor)
            }
        }
        .tint(Color.appAccent)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func card<Content: View>(invalid: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(invalid ? Color.red : Color.clear, lineWidth: 1.5)
            )
            .animation(.easeOut(duration: 0.2), value: invalid)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func pill(text: String, chevron: Bool = false, action: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.system(size: 15, weight: .regular))
            if chevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
    }

    // MARK: - Logic

    private func prefill() {
        switch mode {
        case let .create(defaultDate):
            startDate = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: defaultDate) ?? defaultDate
            endDate   = startDate.addingTimeInterval(7200)
        case let .edit(event):
            title           = event.title
            startDate       = event.startDate
            endDate         = event.endDate
            repeatFrequency = event.repeatFrequency
            eventColor      = event.eventColor
            notes           = event.notes
        }
        // Sync lastStartDay so the first onChange delta is computed correctly.
        lastStartDay = Calendar.current.startOfDay(for: startDate)
    }

    private func save() {
        guard isValid else { return }
        let event = UserEvent(
            id: editingID ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            startDate: startDate, endDate: endDate,
            repeatFrequency: repeatFrequency,
            eventColor: eventColor, notes: notes
        )
        if let onSave {
            // Caller handles saving (e.g. for repeat scope selection).
            onSave(event)
        } else {
            store.saveUserEvent(event)
        }
        dismiss()
    }
}

// MARK: - Colour picker sheet

struct ColorPickerSheet: View {
    @Binding var selection: EventColor
    @Environment(\.dismiss) private var dismiss

    // Custom colour state — driven by SwiftUI's native ColorPicker.
    @State private var customColor: Color = .red
    @State private var showingCustomPicker = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // ── Preset swatches ───────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Presets")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .kerning(0.5)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(EventColor.Preset.allCases) { preset in
                                let ec = EventColor.preset(preset)
                                colorSwatch(color: preset.swiftUIColor,
                                            label: preset.rawValue,
                                            isSelected: selection == ec) {
                                    selection = ec
                                }
                            }
                        }
                    }

                    Divider()

                    // ── Custom colour ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Custom")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .kerning(0.5)
                            .padding(.horizontal, 4)

                        HStack(spacing: 16) {
                            // Native colour wheel picker.
                            ColorPicker("", selection: $customColor, supportsOpacity: false)
                                .labelsHidden()
                                .onChange(of: customColor) { _, newColor in
                                    if let hex = newColor.hexString {
                                        selection = .custom(hex: hex)
                                    }
                                }

                            // Preview of the selected custom colour.
                            if case let .custom(hex) = selection {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(Color(hex: hex) ?? .gray)
                                        .frame(width: 36, height: 36)
                                        .shadow(color: (Color(hex: hex) ?? .gray).opacity(0.4), radius: 4)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Custom colour")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("#\(hex.uppercased())")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.appAccent)
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                            } else {
                                Text("Tap the colour wheel to pick a custom colour")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Choose colour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                }
            }
            .onAppear {
                // Sync wheel to current custom colour if any.
                if case let .custom(hex) = selection, let c = Color(hex: hex) {
                    customColor = c
                }
            }
        }
    }

    @ViewBuilder
    private func colorSwatch(color: Color, label: String,
                              isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 44, height: 44)
                        .shadow(color: color.opacity(0.4), radius: 4)

                    if isSelected {
                        Circle()
                            .stroke(Color.white, lineWidth: 2.5)
                            .frame(width: 44, height: 44)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    EventFormView(mode: .create(defaultDate: Date()))
        .environment(AppStore(repository: LocalExamRepository()))
}
