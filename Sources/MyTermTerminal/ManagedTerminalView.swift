import AppKit
import Foundation
import SwiftTerm

public final class ManagedTerminalView: LocalProcessTerminalView {
    public var unseenOutputChanged: ((Bool) -> Void)?
    public private(set) var isFollowingOutput = true
    private var isReceivingData = false
    private var scrollEventsDuringData = 0
    private var lastKnownBottomRow = 0
    private var anchoredNormalRow = 0
    private var transcriptRecorder: TranscriptRecorder?

    // SwiftTerm already implements NSTextInputClient, but a plain NSView is
    // otherwise exposed as a container. Voice-input tools discover editable
    // destinations through the accessibility role and focus contract.
    public override func isAccessibilityElement() -> Bool {
        true
    }

    public override func accessibilityRole() -> NSAccessibility.Role? {
        .textArea
    }

    public override func accessibilityLabel() -> String? {
        "Terminal input"
    }

    public override func accessibilityHelp() -> String? {
        "Type or dictate a command into the focused terminal."
    }

    public override func accessibilityPlaceholderValue() -> String? {
        "Type a command"
    }

    public override func isAccessibilityFocused() -> Bool {
        window?.firstResponder === self
    }

    public override func setAccessibilityFocused(_ accessibilityFocused: Bool) {
        if accessibilityFocused {
            window?.makeFirstResponder(self)
        } else if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    public override func accessibilityValue() -> Any? {
        getSelection() ?? ""
    }

    public override func accessibilitySelectedText() -> String? {
        getSelection() ?? ""
    }

    public override func setAccessibilitySelectedText(_ accessibilitySelectedText: String?) {
        insertAccessibilityText(accessibilitySelectedText)
    }

    public override func accessibilitySelectedTextRange() -> NSRange {
        let length = (getSelection() ?? "").utf16.count
        return NSRange(location: 0, length: length)
    }

    public override func accessibilityNumberOfCharacters() -> Int {
        (getSelection() ?? "").utf16.count
    }

    public override func accessibilityVisibleCharacterRange() -> NSRange {
        accessibilitySelectedTextRange()
    }

    private func insertAccessibilityText(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    public func configureTranscript(
        directory: URL,
        title: String,
        failureHandler: @escaping TranscriptRecorder.FailureHandler
    ) throws {
        transcriptRecorder?.close()
        transcriptRecorder = try TranscriptRecorder(
            directory: directory,
            title: title,
            failureHandler: failureHandler
        )
    }

    public func closeTranscript(completion: (() -> Void)? = nil) {
        transcriptRecorder?.close(completion: completion)
        transcriptRecorder = nil
    }

    public override func dataReceived(slice: ArraySlice<UInt8>) {
        transcriptRecorder?.append(Data(slice))
        let wasAlternateBuffer = terminal.isCurrentBufferAlternate
        let shouldPreserveViewport = !isFollowingOutput
        let previousRow = wasAlternateBuffer ? anchoredNormalRow : terminal.buffer.yDisp
        let previousBottomRow = lastKnownBottomRow

        isReceivingData = true
        scrollEventsDuringData = 0
        super.dataReceived(slice: slice)

        let isAlternateBuffer = terminal.isCurrentBufferAlternate
        let observedRow = terminal.buffer.yDisp
        let latestBottomRow =
            (!isFollowingOutput && scrollEventsDuringData == 0)
            ? previousBottomRow
            : observedRow
        if shouldPreserveViewport && !isAlternateBuffer {
            let bufferGrowth = max(0, latestBottomRow - previousBottomRow)
            let trimmedLines = max(0, scrollEventsDuringData - bufferGrowth)
            let anchoredRow = max(0, previousRow - trimmedLines)
            scrollTo(row: min(anchoredRow, latestBottomRow), notifyAccessibility: false)
            anchoredNormalRow = terminal.buffer.yDisp
        }
        if !isAlternateBuffer {
            lastKnownBottomRow = latestBottomRow
        }
        isReceivingData = false

        if shouldPreserveViewport && !isAlternateBuffer {
            isFollowingOutput = false
            unseenOutputChanged?(true)
        }
    }

    public override func scrolled(source: TerminalView, position: Double) {
        super.scrolled(source: source, position: position)
        guard !isReceivingData else { return }
        updateFollowState()
    }

    public override func scrolled(source: Terminal, yDisp: Int) {
        if isReceivingData && !terminal.isCurrentBufferAlternate {
            scrollEventsDuringData += 1
        }
        super.scrolled(source: source, yDisp: yDisp)
    }

    public func noteUserScrolled() {
        updateFollowState()
    }

    private func updateFollowState() {
        guard !terminal.isCurrentBufferAlternate else { return }
        let isNowFollowing = !canScroll || scrollPosition >= 0.999
        anchoredNormalRow = terminal.buffer.yDisp
        guard isNowFollowing != isFollowingOutput else { return }
        isFollowingOutput = isNowFollowing
        if isNowFollowing {
            lastKnownBottomRow = terminal.buffer.yDisp
            unseenOutputChanged?(false)
        }
    }

    public func jumpToLatest() {
        scroll(toPosition: 1)
        isFollowingOutput = true
        lastKnownBottomRow = terminal.buffer.yDisp
        unseenOutputChanged?(false)
    }
}
