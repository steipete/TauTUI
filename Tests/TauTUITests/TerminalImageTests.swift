import Foundation
import Testing
@testable import TauTUI

@Suite("TerminalImage")
struct TerminalImageTests {
    @Test
    func detectCapabilities_kittyAndITerm2() {
        let kitty = TerminalImage.detectCapabilities(env: ["TERM_PROGRAM": "kitty"])
        #expect(kitty.images == .kitty)

        let iterm = TerminalImage.detectCapabilities(env: ["TERM_PROGRAM": "iTerm.app"])
        #expect(iterm.images == .iterm2)
    }

    @Test
    func encodeKitty_chunksLargePayload() {
        let payload = String(repeating: "A", count: 9000)
        let encoded = TerminalImage.encodeKitty(base64Data: payload, columns: 10, rows: 2, imageId: 7)
        #expect(encoded.contains("\u{001B}_G"))
        #expect(encoded.contains("m=1"))
        #expect(encoded.contains("m=0"))
        #expect(encoded.contains("c=10"))
        #expect(encoded.contains("r=2"))
        #expect(encoded.contains("i=7"))
    }

    @Test
    func imageDimensions_pngGifWebpJpeg() {
        // 1x1 PNG
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/fK0AAAAASUVORK5CYII="
        let pngDims = TerminalImage.getPngDimensions(base64Data: png)
        #expect(pngDims?.widthPx == 1)
        #expect(pngDims?.heightPx == 1)

        // 1x1 GIF
        let gif = "R0lGODdhAQABAIAAAP///////ywAAAAAAQABAAACAkQBADs="
        let gifDims = TerminalImage.getGifDimensions(base64Data: gif)
        #expect(gifDims?.widthPx == 1)
        #expect(gifDims?.heightPx == 1)

        // Minimal WebP VP8X (10x20)
        var webpBytes = [UInt8](repeating: 0, count: 30)
        webpBytes[0...3] = [0x52, 0x49, 0x46, 0x46] // RIFF
        webpBytes[8...11] = [0x57, 0x45, 0x42, 0x50] // WEBP
        webpBytes[12...15] = [0x56, 0x50, 0x38, 0x58] // VP8X
        // widthMinus1=9 (10px), heightMinus1=19 (20px)
        webpBytes[24] = 9
        webpBytes[25] = 0
        webpBytes[26] = 0
        webpBytes[27] = 19
        webpBytes[28] = 0
        webpBytes[29] = 0
        let webp = Data(webpBytes).base64EncodedString()
        let webpDims = TerminalImage.getWebpDimensions(base64Data: webp)
        #expect(webpDims?.widthPx == 10)
        #expect(webpDims?.heightPx == 20)

        // Minimal JPEG SOF0 (32x16)
        let jpegBytes: [UInt8] = [
            0xFF, 0xD8, // SOI
            0xFF, 0xC0, // SOF0
            0x00, 0x11, // length
            0x08, // precision
            0x00, 0x10, // height = 16
            0x00, 0x20, // width = 32
            0x03,
            0x01, 0x11, 0x00,
            0x02, 0x11, 0x00,
            0x03, 0x11, 0x00,
        ]
        let jpeg = Data(jpegBytes).base64EncodedString()
        let jpegDims = TerminalImage.getJpegDimensions(base64Data: jpeg)
        #expect(jpegDims?.widthPx == 32)
        #expect(jpegDims?.heightPx == 16)
    }
}

