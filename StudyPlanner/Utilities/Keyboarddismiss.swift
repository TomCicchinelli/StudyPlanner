//
//  Keyboarddismiss.swift
//  StudyPlanner
//
//  Created by Cicchinelli Tommaso on 22/05/2026.
//

//
//  KeyboardDismiss.swift
//  StudyPlanner
//
//  Apply .dismissKeyboardOnTap() to any view to make tapping
//  outside a text field close the keyboard.
//

import SwiftUI
import UIKit

extension View {
    func dismissKeyboardOnTap() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded {
                // Only resign if the first responder is not a text input field itself.
                // This prevents dismissing the keyboard when the user taps inside
                // a text field to reposition the cursor.
                guard let scene = UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                      let window = scene.windows.first(where: \.isKeyWindow),
                      let responder = window.firstResponder else { return }
                let isTextInput = responder is UITextField || responder is UITextView
                if !isTextInput {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            }
        )
    }
}

// MARK: - UIWindow firstResponder helper

private extension UIWindow {
    var firstResponder: UIResponder? {
        return findFirstResponder(in: self)
    }

    private func findFirstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let responder = findFirstResponder(in: subview) { return responder }
        }
        return nil
    }
}
