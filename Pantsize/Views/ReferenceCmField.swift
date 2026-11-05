import SwiftUI
import UIKit

/// UIKit テキストフィールド（編集中は SwiftUI 側を更新しない → カーソル・削除が正常）。
struct DecimalCmTextField: UIViewRepresentable {
    var text: String
    var placeholder: String
    var appendDecimalSignal: Int
    var focusRequestToken: Int
    var dismissSignal: Int
    var onFocusChange: (Bool) -> Void
    var onCommit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFocusChange: onFocusChange, onCommit: onCommit)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .decimalPad
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.textAlignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        field.placeholder = placeholder
        field.text = text
        field.borderStyle = .none
        field.backgroundColor = .clear
        context.coordinator.field = field
        context.coordinator.lastAppendSignal = appendDecimalSignal
        context.coordinator.lastFocusToken = focusRequestToken
        context.coordinator.lastDismissSignal = dismissSignal
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.onFocusChange = onFocusChange
        context.coordinator.onCommit = onCommit

        if !context.coordinator.isEditing, uiView.text != text {
            uiView.text = text
        }

        if context.coordinator.lastAppendSignal != appendDecimalSignal {
            context.coordinator.lastAppendSignal = appendDecimalSignal
            context.coordinator.insertDecimalPoint()
        }

        if context.coordinator.lastDismissSignal != dismissSignal {
            context.coordinator.lastDismissSignal = dismissSignal
            uiView.resignFirstResponder()
        } else if context.coordinator.lastFocusToken != focusRequestToken {
            context.coordinator.lastFocusToken = focusRequestToken
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        weak var field: UITextField?
        var isEditing = false
        var lastAppendSignal = 0
        var lastFocusToken = 0
        var lastDismissSignal = 0
        var onFocusChange: (Bool) -> Void
        var onCommit: (String) -> Void

        init(onFocusChange: @escaping (Bool) -> Void, onCommit: @escaping (String) -> Void) {
            self.onFocusChange = onFocusChange
            self.onCommit = onCommit
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isEditing = true
            onFocusChange(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isEditing = false
            onFocusChange(false)
            let cleaned = MeasurementScale.sanitizeDecimalInput(textField.text ?? "")
            textField.text = cleaned
            onCommit(cleaned)
        }

        func insertDecimalPoint() {
            guard let field, field.isFirstResponder else { return }
            let current = field.text ?? ""
            guard !current.contains(".") else { return }

            if let selected = field.selectedTextRange {
                field.replace(selected, withText: ".")
            } else {
                field.text = current + "."
            }
        }
    }
}
