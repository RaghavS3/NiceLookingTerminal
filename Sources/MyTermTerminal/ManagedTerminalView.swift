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
