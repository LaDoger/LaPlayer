import Foundation

/// Losslessly trims an MP3 file to a time range by locating MPEG frame boundaries and
/// copying the compressed frame bytes directly — no decode/re-encode step. This sidesteps
/// the fact that macOS ships no MP3 encoder: since each frame is independently decodable,
/// a frame-aligned byte slice is a valid, lossless MP3 file on its own.
enum MP3Trimmer {
    struct TrimError: Error {
        let message: String
    }

    private struct Frame {
        let offset: Int
        let length: Int
        let startTime: Double
    }

    static func trim(sourceURL: URL, start: Double, end: Double, to destinationURL: URL) throws {
        let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        let frames = parseFrames(data)
        guard !frames.isEmpty else {
            throw TrimError(message: "No MPEG audio frames found")
        }

        let startIndex = nearestFrameIndex(frames, to: start)
        var endIndex = nearestFrameIndex(frames, to: end)
        if endIndex <= startIndex {
            endIndex = min(startIndex + 1, frames.count)
        }

        let startOffset = frames[startIndex].offset
        let endOffset = endIndex < frames.count ? frames[endIndex].offset : data.count
        guard endOffset > startOffset else {
            throw TrimError(message: "Trim range is empty")
        }

        try data.subdata(in: startOffset..<endOffset).write(to: destinationURL)
    }

    // MARK: - Frame scanning

    private static let mpeg1BitrateKbps = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, -1]
    private static let mpeg2BitrateKbps = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, -1]
    private static let mpeg1SampleRates = [44100, 48000, 32000, -1]
    private static let mpeg2SampleRates = [22050, 24000, 16000, -1]
    private static let mpeg25SampleRates = [11025, 12000, 8000, -1]

    private static func parseFrames(_ data: Data) -> [Frame] {
        var frames: [Frame] = []
        var time: Double = 0
        let count = data.count
        var offset = id3v2HeaderSize(data)

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)

            func header(at o: Int) -> (frameLength: Int, samples: Int, sampleRate: Int)? {
                guard o + 4 <= count else { return nil }
                let b1 = bytes[o + 1], b2 = bytes[o + 2]
                guard bytes[o] == 0xFF, (b1 & 0xE0) == 0xE0 else { return nil }

                let versionBits = (b1 >> 3) & 0x03
                let layerBits = (b1 >> 1) & 0x03
                guard layerBits == 0x01 else { return nil } // MPEG Layer III only

                let bitrateIndex = Int((b2 >> 4) & 0x0F)
                let sampleRateIndex = Int((b2 >> 2) & 0x03)
                let padding = Int((b2 >> 1) & 0x01)
                guard bitrateIndex != 0, bitrateIndex != 15, sampleRateIndex != 3 else { return nil }

                let isMPEG1 = versionBits == 0x03
                let sampleRate = isMPEG1
                    ? mpeg1SampleRates[sampleRateIndex]
                    : (versionBits == 0x02 ? mpeg2SampleRates[sampleRateIndex] : mpeg25SampleRates[sampleRateIndex])
                guard sampleRate > 0 else { return nil }

                let bitrateKbps = isMPEG1 ? mpeg1BitrateKbps[bitrateIndex] : mpeg2BitrateKbps[bitrateIndex]
                guard bitrateKbps > 0 else { return nil }

                let coefficient = isMPEG1 ? 144 : 72
                let frameLength = (coefficient * bitrateKbps * 1000) / sampleRate + padding
                guard frameLength > 0 else { return nil }
                let samples = isMPEG1 ? 1152 : 576
                return (frameLength, samples, sampleRate)
            }

            // The ID3v2 tag's declared size is sometimes slightly off; scan a little further
            // forward for the first byte sequence that parses as a valid frame header.
            let searchLimit = min(offset + 8192, count)
            var searchStart = offset
            var foundStart = false
            while searchStart < searchLimit {
                if header(at: searchStart) != nil {
                    offset = searchStart
                    foundStart = true
                    break
                }
                searchStart += 1
            }
            guard foundStart else { return }

            while let h = header(at: offset) {
                frames.append(Frame(offset: offset, length: h.frameLength, startTime: time))
                time += Double(h.samples) / Double(h.sampleRate)
                offset += h.frameLength
            }
        }

        return frames
    }

    private static func nearestFrameIndex(_ frames: [Frame], to time: Double) -> Int {
        var lo = 0
        var hi = frames.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if frames[mid].startTime <= time { lo = mid } else { hi = mid - 1 }
        }
        if lo + 1 < frames.count {
            let current = frames[lo].startTime
            let next = frames[lo + 1].startTime
            if abs(next - time) < abs(current - time) { return lo + 1 }
        }
        return lo
    }

    private static func id3v2HeaderSize(_ data: Data) -> Int {
        guard data.count >= 10 else { return 0 }
        let bytes = [UInt8](data.prefix(10))
        guard bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else { return 0 } // "ID3"
        let hasFooter = (bytes[5] & 0x10) != 0
        let size = (Int(bytes[6] & 0x7F) << 21) | (Int(bytes[7] & 0x7F) << 14)
            | (Int(bytes[8] & 0x7F) << 7) | Int(bytes[9] & 0x7F)
        return 10 + size + (hasFooter ? 10 : 0)
    }
}
