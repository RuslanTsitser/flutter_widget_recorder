// FlutterWidgetRecorderPlugin.swift
import Flutter
import UIKit
import AVFoundation
import CoreMedia
import CoreImage

public class FlutterWidgetRecorderPlugin: NSObject, FlutterPlugin {
    // MARK: — properties
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var videoOutputURL: URL?
    private var isRecording = false
    private var pixelWidth = 0
    private var pixelHeight = 0
    // original frame dims before alignment
    private var frameWidth = 0
    private var frameHeight = 0
    private var firstTimestamp: CMTime?
    private let ciContext = CIContext()

    // MARK: — registration
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_widget_recorder",
            binaryMessenger: registrar.messenger()
        )
        let instance = FlutterWidgetRecorderPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: — handler
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startRecording":
            guard let args = call.arguments as? [String: Any],
                  let name       = args["name"] as? String,
                  let width      = args["width"] as? Int,
                  let height     = args["height"] as? Int,
                  let pixelRatio = args["pixelRatio"] as? Double
            else {
                return result(FlutterError(code: "INVALID_ARGS", message: "Expected name, width, height, pixelRatio", details: nil))
            }
            // compute physical dims
            let unW = Int(Double(width) * pixelRatio)
            let unH = Int(Double(height) * pixelRatio)
            frameWidth = unW; frameHeight = unH
            // align to 16
            pixelWidth  = ((unW + 15)/16)*16
            pixelHeight = ((unH + 15)/16)*16
            startRecording(name: name, result: result)

        case "pushFrame":
            guard let args     = call.arguments as? [String: Any],
                  let data     = args["pixels"] as? FlutterStandardTypedData,
                  let tsMillis = args["timestampMs"] as? Int64
            else {
                return result(FlutterError(code: "INVALID_ARGS", message: "Expected pixels, timestampMs", details: nil))
            }
            let timestamp = CMTimeMake(value: tsMillis, timescale: 1000)
            pushFrame(rawData: data.data, timestamp: timestamp, result: result)

        case "stopRecording":
            stopRecording(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: — startRecording
    private func startRecording(name: String, result: @escaping FlutterResult) {
        guard !isRecording else {
            return result(FlutterError(code: "ALREADY_RECORDING", message: "Recording already in progress", details: nil))
        }
        isRecording = true; firstTimestamp = nil

        // prepare file
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outURL = docs.appendingPathComponent("\(name).mp4")
        videoOutputURL = outURL
        if FileManager.default.fileExists(atPath: outURL.path) {
            try? FileManager.default.removeItem(at: outURL)
        }

        // create writer
        do {
            videoWriter = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        } catch {
            isRecording = false
            return result(FlutterError(code: "WRITER_ERROR", message: "Cannot create AVAssetWriter", details: error.localizedDescription))
        }
        videoWriter?.shouldOptimizeForNetworkUse = true

        // H264 settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        guard let writer = videoWriter, writer.canAdd(input) else {
            isRecording = false
            return result(FlutterError(code: "INPUT_ERROR", message: "Cannot add input", details: nil))
        }
        writer.add(input); videoWriterInput = input

        // adaptor for YUV420 (NV12)
        let yuvAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: pixelWidth,
            kCVPixelBufferHeightKey as String: pixelHeight
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: yuvAttrs)

        // start
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        result(true)
    }

    // MARK: — pushFrame
    private func pushFrame(rawData: Data, timestamp: CMTime, result: @escaping FlutterResult) {
        guard isRecording,
              let writer  = videoWriter,
              let input   = videoWriterInput,
              let adaptor = pixelBufferAdaptor
        else {
            return result(FlutterError(code: "NOT_READY", message: "Not initialized", details: nil))
        }
        if writer.status == .failed {
            let err = writer.error?.localizedDescription ?? "Unknown"
            return result(FlutterError(code: "WRITER_FAILED", message: "Writer failed: \(err)", details: nil))
        }

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                // timestamp
                var pts = CMTime.zero
                if let first = self.firstTimestamp {
                    pts = CMTimeSubtract(timestamp, first)
                } else {
                    self.firstTimestamp = timestamp
                }

                // BGRA pixel buffer
                var bgraBuf: CVPixelBuffer?
                let bgraAttrs: [String: Any] = [
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                    kCVPixelBufferWidthKey as String: self.pixelWidth,
                    kCVPixelBufferHeightKey as String: self.pixelHeight,
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                CVPixelBufferCreate(kCFAllocatorDefault, self.pixelWidth, self.pixelHeight,
                                     kCVPixelFormatType_32BGRA, bgraAttrs as CFDictionary, &bgraBuf)
                guard let bgra = bgraBuf else { return }
                CVPixelBufferLockBaseAddress(bgra, [])
                let dst = CVPixelBufferGetBaseAddress(bgra)!
                let dstStride = CVPixelBufferGetBytesPerRow(bgra)
                rawData.withUnsafeBytes { srcPtr in
                    let base = srcPtr.bindMemory(to: UInt8.self).baseAddress!
                    for row in 0..<self.frameHeight {
                        let d = dst.advanced(by: row*dstStride)
                        let s = base.advanced(by: row*self.frameWidth*4)
                        memcpy(d, s, self.frameWidth*4)
                    }
                }
                CVPixelBufferUnlockBaseAddress(bgra, [])

                // create YUV buffer from pool
                guard let pool = adaptor.pixelBufferPool else { return }
                var yuvBuf: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &yuvBuf)
                guard let yuv = yuvBuf else { return }

                // convert via CoreImage
                let ciImage = CIImage(cvPixelBuffer: bgra)
                self.ciContext.render(ciImage, to: yuv)

                // append
                if writer.status == .writing && input.isReadyForMoreMediaData {
                    let ok = adaptor.append(yuv, withPresentationTime: pts)
                    DispatchQueue.main.async { result(ok) }
                } else {
                    DispatchQueue.main.async { result(false) }
                }
            }
        }
    }

    // MARK: — stopRecording
    private func stopRecording(result: @escaping FlutterResult) {
        guard isRecording, let writer = videoWriter, let input = videoWriterInput else {
            return result(FlutterError(code: "NOT_RECORDING", message: "No recording in progress", details: nil))
        }
        isRecording = false
        input.markAsFinished()
        writer.finishWriting { [weak self] in
            DispatchQueue.main.async {
                if let err = writer.error {
                    result(FlutterError(code: "FINISH_ERR", message: "Finish failed", details: err.localizedDescription))
                } else {
                    result(self?.videoOutputURL?.path)
                }
            }
            self?.videoWriter = nil
            self?.videoWriterInput = nil
            self?.pixelBufferAdaptor = nil
            self?.firstTimestamp = nil
        }
    }
}

