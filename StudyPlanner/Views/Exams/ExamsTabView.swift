//
//  ExamsTabView.swift
//  StudyPlanner
//

import SwiftUI

struct ExamsTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            if store.exams.isEmpty {
                // No exam yet → go straight to the creation form.
                // Not dismissable (no Cancel button when there's nothing to go back to).
                ExamFormView(mode: .create, canCancel: false)
            } else {
                ExamDetailView()
                    .scrollDisabled(true)
            }
        }
    }
}

#Preview {
    ExamsTabView()
        .environment(AppStore(repository: LocalExamRepository()))
}
