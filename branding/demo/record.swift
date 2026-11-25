// Films only one app's windows with ScreenCaptureKit (no other apps, no notifications).
// Usage: swift record.swift <bundle id> <out.mov> <go marker to create> <stop marker to wait for> [max seconds]
import Foundation
import ScreenCaptureKit
import AppKit
import AVFoundation

let args = CommandLine.arguments
let bundleID = args[1], outURL = URL(fileURLWithPath: args[2]), goMarker = args[3], stopMarker = args[4]
let maxSeconds = args.count > 5 ? Double(args[5])! : 180

final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    var writer: AVAssetWriter!
    var input: AVAssetWriterInput!
    var started = false
    var frames = 0
    let queue = DispatchQueue(label: "rec")

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: sb.presentationTimeStamp)
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(sb); frames += 1 }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { print("stream stopped: \(error)") }
}

let rec = Recorder()
_ = NSApplication.shared // connects to the window server (needed for window captures)
let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let app = content.applications.first(where: { $0.bundleIdentifier == bundleID }) else { print("app not running"); exit(1) }
        let wins = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleID && $0.frame.width > 800 && $0.frame.height > 300 }
        guard let win = wins.max(by: { $0.frame.width < $1.frame.width }) else { print("no window"); exit(1) }
        // One window, captured directly: works even if it's on another desktop or covered by other apps.
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let scale: CGFloat = 2
        let cfg = SCStreamConfiguration()
        cfg.width = Int(win.frame.width * scale)
        cfg.height = Int(win.frame.height * scale)
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.showsCursor = false
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.queueDepth = 8
        cfg.backgroundColor = CGColor.black
        _ = app
        try? FileManager.default.removeItem(at: outURL)
        rec.writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
        rec.input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: cfg.width, AVVideoHeightKey: cfg.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 24_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        ])
        rec.input.expectsMediaDataInRealTime = true
        rec.writer.add(rec.input)
        let stream = SCStream(filter: filter, configuration: cfg, delegate: rec)
        try stream.addStreamOutput(rec, type: .screen, sampleHandlerQueue: rec.queue)
        try await stream.startCapture()
        print("recording \(cfg.width)x\(cfg.height) px")
        try await Task.sleep(nanoseconds: 300_000_000)
        FileManager.default.createFile(atPath: goMarker, contents: Data())
        let end = Date().addingTimeInterval(maxSeconds)
        while !FileManager.default.fileExists(atPath: stopMarker) && Date() < end { try await Task.sleep(nanoseconds: 100_000_000) }
        try await Task.sleep(nanoseconds: 600_000_000)
        try await stream.stopCapture()
        rec.input.markAsFinished()
        await rec.writer.finishWriting()
        print("saved \(outURL.path) (\(rec.frames) frames)")
    } catch { print("error: \(error)") }
    sem.signal()
}
sem.wait()
