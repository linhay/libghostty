//
//  TerminalTextInputHandler@AppKit.swift
//  libghostty-spm
//
//  Created by Lakr233 on 2026/3/16.
//

#if canImport(AppKit) && !canImport(UIKit)
    import AppKit
    import GhosttyKit

    @MainActor
    final class TerminalTextInputHandler: NSObject {
        private weak var view: AppTerminalView?
        private var markedTextState = TerminalMarkedTextState()
        private var accumulatedTexts: [String]?
        private var handledTextCommand = false

        var hasMarkedText: Bool {
            markedTextState.hasMarkedText
        }

        init(view: AppTerminalView) {
            self.view = view
            super.init()
        }

        func startCollectingText() {
            accumulatedTexts = []
            handledTextCommand = false
        }

        func finishCollectingText() -> [String]? {
            defer { accumulatedTexts = nil }
            guard let texts = accumulatedTexts, !texts.isEmpty else { return nil }
            return texts
        }

        func consumeHandledTextCommand() -> Bool {
            defer { handledTextCommand = false }
            return handledTextCommand
        }

        // MARK: - Text Input

        func insertText(_ string: Any) {
            let text: String
            if let attrStr = string as? NSAttributedString {
                text = attrStr.string
            } else if let str = string as? String {
                text = str
            } else {
                return
            }

            markedTextState.clear()
            view?.surface?.preedit("")

            if accumulatedTexts != nil {
                accumulatedTexts?.append(text)
            } else {
                view?.surface?.sendText(text)
            }
        }

        func setMarkedText(
            _ string: Any,
            selectedRange: NSRange
        ) {
            let text: String
            if let attrStr = string as? NSAttributedString {
                text = attrStr.string
            } else if let str = string as? String {
                text = str
            } else {
                return
            }

            markedTextState.setMarkedText(text, selectedRange: selectedRange)

            if text.isEmpty {
                view?.surface?.preedit("")
            } else {
                view?.surface?.preedit(text)
            }
        }

        func unmarkText() {
            markedTextState.clear()
            view?.surface?.preedit("")
        }

        func currentSelectedRange() -> NSRange {
            markedTextState.currentSelectedRange
        }

        func markedRange() -> NSRange {
            markedTextState.markedRange
        }

        func attributedSubstring(
            forProposedRange range: NSRange,
            actualRange: NSRangePointer?
        ) -> NSAttributedString? {
            guard markedTextState.hasMarkedText else {
                actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
                return nil
            }

            let length = markedTextState.documentLength
            let location = min(max(range.location, 0), length)
            let end = min(max(range.location + range.length, location), length)
            let clampedRange = NSRange(location: location, length: end - location)
            actualRange?.pointee = clampedRange

            guard let text = markedTextState.text(in: clampedRange) else {
                return nil
            }
            return NSAttributedString(string: text)
        }

        func handleCommand(_ selector: Selector) {
            if hasMarkedText {
                switch selector {
                case #selector(NSResponder.deleteBackward(_:)):
                    deleteBackward()
                case #selector(NSResponder.cancelOperation(_:)):
                    unmarkText()
                default:
                    break
                }
                return
            }

            guard handleUnmarkedCommand(selector) else { return }
            handledTextCommand = true
        }

        private func deleteBackward() {
            guard markedTextState.deleteBackward() else { return }
            view?.surface?.preedit(markedTextState.text ?? "")
            handledTextCommand = true
        }

        private func handleUnmarkedCommand(_ selector: Selector) -> Bool {
            guard let view, let surface = view.surface else { return false }

            // For exec backend, rely on physical key events instead of the
            // text-command fallback path to avoid fragmented escape sequences
            // (for example "[C" for right arrow in shell line editor).
            if case .exec = view.configuration.backend {
                return false
            }

            switch selector {
            case #selector(NSResponder.deleteBackward(_:)):
                surface.sendText("\u{7F}")
                return true
            case #selector(NSResponder.deleteForward(_:)):
                surface.sendText("\u{1B}[3~")
                return true
            case #selector(NSResponder.moveLeft(_:)):
                surface.sendText("\u{1B}[D")
                return true
            case #selector(NSResponder.moveRight(_:)):
                surface.sendText("\u{1B}[C")
                return true
            case #selector(NSResponder.moveUp(_:)):
                surface.sendText("\u{1B}[A")
                return true
            case #selector(NSResponder.moveDown(_:)):
                surface.sendText("\u{1B}[B")
                return true
            case #selector(NSResponder.moveToBeginningOfLine(_:)):
                surface.sendText("\u{1B}[H")
                return true
            case #selector(NSResponder.moveToEndOfLine(_:)):
                surface.sendText("\u{1B}[F")
                return true
            default:
                return false
            }
        }
    }
#endif
