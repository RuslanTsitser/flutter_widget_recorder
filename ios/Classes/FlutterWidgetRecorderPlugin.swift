import Flutter
import UIKit
import AVFoundation
import CoreMedia

public class FlutterWidgetRecorderPlugin: NSObject, FlutterPlugin {
    var videoWriter: AVAssetWriter?
    var videoWriterInput: AVAssetWriterInput?
    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    var videoOutputURL: URL?
    var isRecording = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_widget_recorder",
            binaryMessenger: registrar.messenger()
        )
        let instance = FlutterWidgetRecorderPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startRecording":
            guard let args = call.arguments as? [String: Any],
                  let name = args["name"] as? String,
                  let width = args["width"] as? Int,
                  let height = args["height"] as? Int else {
                return result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "Expected name/width/height",
                    details: nil
                ))
            }
            startRecording(name: name, width: width, height: height, result: result)

        case "pushFrame":
            guard let args = call.arguments as? [String: Any],
                  let pixels = args["pixels"] as? FlutterStandardTypedData,
                  let width = args["width"] as? Int,
                  let height = args["height"] as? Int,
                  let tsMs = args["timestampMs"] as? Int64 else {
                return result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "Expected pixels/width/height/timestampMs",
                    details: nil
                ))
            }
            let ts = CMTimeMake(value: tsMs, timescale: 1000)
            pushFrame(pixels.data, width: width, height: height, timestamp: ts, result: result)

        case "stopRecording":
            stopRecording(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func startRecording(name: String, width: Int, height: Int, result: @escaping FlutterResult) {
        guard !isRecording else {
            return result(FlutterError(code: "ALREADY_RECORDING", message: "Already recording", details: nil))
        }
        isRecording = true

        // Файл .mov в Documents
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let url = URL(fileURLWithPath: docs).appendingPathComponent("\(name).mov")
        videoOutputURL = url
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        // Создаём writer
        do {
            videoWriter = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            isRecording = false
            return result(FlutterError(code: "WRITER_ERROR", message: "Cannot create writer", details: error.localizedDescription))
        }
        videoWriter!.shouldOptimizeForNetworkUse = true

        // Минимальные настройки видео
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        guard let writer = videoWriter, writer.canAdd(input) else {
            isRecording = false
            return result(FlutterError(code: "INPUT_ERROR", message: "Cannot add input", details: nil))
        }
        writer.add(input)
        videoWriterInput = input

        // PixelBufferAdaptor: указываем BGRA
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                                 sourcePixelBufferAttributes: attrs)

        // Сразу стартуем запись
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        result(true)
    }

    func pushFrame(_ rawData: Data,
                   width: Int,
                   height: Int,
                   timestamp: CMTime,
                   result: @escaping FlutterResult) {
        guard isRecording,
              let writer = videoWriter,
              let input = videoWriterInput,
              let adaptor = pixelBufferAdaptor else {
            return result(FlutterError(code: "NOT_READY", message: "Not initialized", details: nil))
        }
        if writer.status == .failed {
            let err = writer.error?.localizedDescription ?? "Unknown"
            return result(FlutterError(code: "WRITER_FAILED", message: "Writer failed: \(err)", details: nil))
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // RGBA → BGRA
            var bgra = rawData
            bgra.withUnsafeMutableBytes { buf in
                let p = buf.bindMemory(to: UInt8.self)
                for i in stride(from: 0, to: p.count, by: 4) {
                    let r = p[i]
                    p[i]     = p[i+2]
                    p[i+2]   = r
                }
            }

            // Создаём CVPixelBuffer и копируем
            var pxOpt: CVPixelBuffer?
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                             width, height,
                                             kCVPixelFormatType_32BGRA,
                                             attrs as CFDictionary,
                                             &pxOpt)
            guard status == kCVReturnSuccess, let px = pxOpt else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "PIXEL_ERR", message: "Cannot alloc pixelBuffer", details: "\(status)"))
                }
                return
            }
            CVPixelBufferLockBaseAddress(px, [])
            if let dst = CVPixelBufferGetBaseAddress(px) {
                bgra.withUnsafeBytes { src in
                    memcpy(dst, src.baseAddress!, width * height * 4)
                }
            }
            CVPixelBufferUnlockBaseAddress(px, [])

            // Append через адаптор
            if writer.status == .writing && input.isReadyForMoreMediaData {
                let ok = adaptor.append(px, withPresentationTime: timestamp)
                DispatchQueue.main.async {
                    if ok { result(true) }
                    else {
                        let e = writer.error?.localizedDescription
                        result(FlutterError(code: "APPEND_ERR", message: "Append failed", details: e))
                    }
                }
            } else {
                DispatchQueue.main.async { result(false) }
            }
        }
    }

    func stopRecording(result: @escaping FlutterResult) {
        guard isRecording,
              let writer = videoWriter,
              let input = videoWriterInput else {
            return result(FlutterError(code: "NOT_RECORDING", message: "No recording", details: nil))
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
        }
    }
}
