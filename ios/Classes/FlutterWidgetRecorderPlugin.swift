import Flutter
import UIKit
import AVFoundation
import CoreMedia

public class FlutterWidgetRecorderPlugin: NSObject, FlutterPlugin {
    // MARK: — свойства
    var videoWriter: AVAssetWriter?
    var videoWriterInput: AVAssetWriterInput?
    var videoOutputURL: URL?
    var isRecording = false
    var firstTimestamp: CMTime?
    var expectedWidth: Int = 0
    var expectedHeight: Int = 0

    // MARK: — регистрация плагина
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_widget_recorder", binaryMessenger: registrar.messenger())
        let instance = FlutterWidgetRecorderPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: — обработка вызовов из Flutter
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startRecording":
            guard let args = call.arguments as? [String: Any],
                  let name = args["name"] as? String,
                  let width = args["width"] as? Int,
                  let height = args["height"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected name/width/height", details: nil))
                return
            }
            startRecording(videoName: name, width: width, height: height, result: result)

        case "pushFrame":
            guard let args = call.arguments as? [String: Any],
                  let pixels = args["pixels"] as? FlutterStandardTypedData,
                  let width = args["width"] as? Int,
                  let height = args["height"] as? Int,
                  let timestampMs = args["timestampMs"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected pixels/width/height/timestampMs", details: nil))
                return
            }
            let ts = CMTimeMake(value: timestampMs, timescale: 1000)
            pushFrame(pixels.data, width: width, height: height, timestamp: ts, result: result)

        case "stopRecording":
            stopRecording(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: — startRecording: инициализация AVAssetWriter
    func startRecording(videoName: String, width: Int, height: Int, result: @escaping FlutterResult) {
        guard !isRecording else {
            result(FlutterError(code: "ALREADY_RECORDING", message: "Recording already in progress", details: nil))
            return
        }
        isRecording = true
        expectedWidth = width
        expectedHeight = height

        let docsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let outputURL = URL(fileURLWithPath: docsPath).appendingPathComponent("\(videoName).mp4")
        videoOutputURL = outputURL
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        do {
            videoWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            result(FlutterError(code: "WRITER_ERROR", message: "Cannot create AVAssetWriter", details: error.localizedDescription))
            return
        }

        // Здесь убираем ключ kCVPixelBufferPixelFormatTypeKey
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: expectedWidth,
            AVVideoHeightKey: expectedHeight
            // ← НЕ указываем пиксельный формат здесь
        ]
        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput?.expectsMediaDataInRealTime = true

        if let vInput = videoWriterInput, videoWriter!.canAdd(vInput) {
            videoWriter!.add(vInput)
        } else {
            result(FlutterError(code: "INPUT_ERROR", message: "Cannot add videoInput to writer", details: nil))
            return
        }

        result(true)
    }


    // MARK: — pushFrame: преобразуем RGBA → CVPixelBuffer → CMSampleBuffer → AVAssetWriterInput.append(...)
    func pushFrame(_ rawData: Data, width: Int, height: Int, timestamp: CMTime, result: @escaping FlutterResult) {
        guard isRecording else {
            result(FlutterError(code: "NOT_RECORDING", message: "Recording is not started", details: nil))
            return
        }
        // Проверяем, что размеры совпадают с теми, что мы ждали
        guard width == expectedWidth, height == expectedHeight else {
            result(FlutterError(code: "SIZE_MISMATCH", message: "Frame size differs from initialized size", details: nil))
            return
        }

        // 1) Создадим CVPixelBuffer из rawData (RGBA из Flutter; AVAssetWriter ожидает BGRA)
        //    Чтобы получить BGRA, можно либо настроить pixelBufferFormat в RepaintBoundary (но там всегда RGBA),
        //    либо скопировать байты и аккуратно поменять порядок каналов. Упрощённо здесь считаем, что Flutter присылает BGRA.
        //    Если он шлёт именно RGBA, нужно перед отправкой поменять порядок байтов (R<->B). Ниже пример без конвертации.
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let status = CVPixelBufferCreateWithBytes(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            UnsafeMutableRawPointer(mutating: (rawData as NSData).bytes),
            width * 4,
            nil,
            nil,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pxBuffer = pixelBuffer else {
            result(FlutterError(code: "PIXELBUFFER_ERROR", message: "Failed to create CVPixelBuffer", details: "\(status)"))
            return
        }

        // 2) Создадим CMVideoFormatDescription для CVPixelBuffer
        var formatDesc: CMVideoFormatDescription?
        let fmtStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pxBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard fmtStatus == noErr, let fmtDesc = formatDesc else {
            result(FlutterError(code: "FORMAT_DESC_ERROR", message: "Failed to create format description", details: "\(fmtStatus)"))
            return
        }

        // 3) Создадим CMSampleBuffer из CVPixelBuffer и установим тайминг
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: timestamp,
            decodeTimeStamp: CMTime.invalid
        )
        let sbStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pxBuffer,
            formatDescription: fmtDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        guard sbStatus == noErr, let cmsb = sampleBuffer else {
            result(FlutterError(code: "SAMPLEBUFFER_ERROR", message: "Failed to create CMSampleBuffer", details: "\(sbStatus)"))
            return
        }

        // 4) Если это первый кадр — запускаем сессию записи
        guard let writer = videoWriter, let vInput = videoWriterInput else {
            result(FlutterError(code: "WRITER_NOT_READY", message: "AVAssetWriter not initialized", details: nil))
            return
        }
        if writer.status == .unknown {
            firstTimestamp = timestamp
            writer.startWriting()
            writer.startSession(atSourceTime: timestamp)
        }

        // 5) Добавляем кадр, если вход готов принять данные
        if writer.status == .writing && vInput.isReadyForMoreMediaData {
            let appended = vInput.append(cmsb)
            if !appended {
                // Можно логировать ошибку: vInput.error?.localizedDescription
                result(FlutterError(code: "APPEND_FAILED", message: "Cannot append sample buffer", details: "no details"))
            } else {
                result(true)
            }
        } else {
            result(false) // Writer не готов, кадр пропускаем
        }
    }

    // MARK: — stopRecording: закрытие записи и возврат пути к файлу
    func stopRecording(result: @escaping FlutterResult) {
        guard isRecording else {
            result(FlutterError(code: "NOT_RECORDING", message: "Recording not in progress", details: nil))
            return
        }
        isRecording = false

        guard let writer = videoWriter, let vInput = videoWriterInput else {
            result(FlutterError(code: "WRITER_NOT_READY", message: "AVAssetWriter not initialized", details: nil))
            return
        }

        // Сообщаем, что больше не будет данных
        vInput.markAsFinished()

        writer.finishWriting { [weak self] in
            guard let self = self else { return }
            if let err = writer.error {
                result(FlutterError(code: "FINISH_ERROR", message: "Error finishing writing", details: err.localizedDescription))
            } else {
                // Возвращаем путь к готовому файлу
                result(self.videoOutputURL?.path)
            }
            // Обнуляем состояния
            self.videoWriter = nil
            self.videoWriterInput = nil
            self.firstTimestamp = nil
        }
    }
}
