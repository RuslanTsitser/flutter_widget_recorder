package com.tsitser.flutter_widget_recorder

import android.content.Context
import android.media.*
import android.os.Build
import android.os.Environment
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

/** FlutterWidgetRecorderPlugin */
class FlutterWidgetRecorderPlugin: FlutterPlugin, MethodCallHandler {
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private var mediaCodec: MediaCodec? = null
    private var mediaMuxer: MediaMuxer? = null
    private var videoTrackIndex = -1
    private var isRecording = AtomicBoolean(false)
    private var outputFile: File? = null
    private var firstTimestamp: Long = 0
    private var pixelWidth = 0
    private var pixelHeight = 0
    private var frameWidth = 0
    private var frameHeight = 0
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_widget_recorder")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startRecording" -> {
                val name = call.argument<String>("name")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                val pixelRatio = call.argument<Double>("pixelRatio")

                if (name == null || width == null || height == null || pixelRatio == null) {
                    result.error("INVALID_ARGS", "Expected name, width, height, pixelRatio", null)
                    return
                }

                // Вычисляем физические размеры
                val unW = (width * pixelRatio).toInt()
                val unH = (height * pixelRatio).toInt()
                frameWidth = unW
                frameHeight = unH
                // Выравниваем по 16
                pixelWidth = ((unW + 15) / 16) * 16
                pixelHeight = ((unH + 15) / 16) * 16

                startRecording(name, result)
            }
            "pushFrame" -> {
                val pixels = call.argument<ByteArray>("pixels")
                val timestampMs = call.argument<Long>("timestampMs")

                if (pixels == null || timestampMs == null) {
                    result.error("INVALID_ARGS", "Expected pixels, timestampMs", null)
                    return
                }

                pushFrame(pixels, timestampMs, result)
            }
            "stopRecording" -> {
                stopRecording(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun startRecording(name: String, result: Result) {
        if (isRecording.get()) {
            result.error("ALREADY_RECORDING", "Recording already in progress", null)
            return
        }

        try {
            // Создаем файл для записи во внутренней памяти приложения
            outputFile = File(context.filesDir, "$name.mp4")
            
            // Удаляем существующий файл, если он есть
            if (outputFile?.exists() == true) {
                outputFile?.delete()
            }

            // Создаем MediaCodec для кодирования H.264
            val mimeType = MediaFormat.MIMETYPE_VIDEO_AVC
            mediaCodec = MediaCodec.createEncoderByType(mimeType)
            
            val format = MediaFormat.createVideoFormat(mimeType, pixelWidth, pixelHeight)
            format.setInteger(MediaFormat.KEY_BIT_RATE, 2_000_000)
            format.setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar)
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            format.setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
            
            mediaCodec?.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            mediaCodec?.start()

            // Создаем MediaMuxer для записи в MP4
            mediaMuxer = MediaMuxer(outputFile?.absolutePath ?: "", MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            videoTrackIndex = -1
            isRecording.set(true)
            firstTimestamp = 0

            result.success(true)
        } catch (e: Exception) {
            Log.e("FlutterWidgetRecorder", "Error starting recording", e)
            result.error("START_ERROR", "Failed to start recording: ${e.message}", null)
            cleanup()
        }
    }

    private fun pushFrame(pixels: ByteArray, timestampMs: Long, result: Result) {
        if (!isRecording.get()) {
            result.error("NOT_RECORDING", "Not recording", null)
            return
        }

        try {
            val codec = mediaCodec ?: throw IllegalStateException("MediaCodec not initialized")
            val muxer = mediaMuxer ?: throw IllegalStateException("MediaMuxer not initialized")

            // Устанавливаем первый timestamp
            if (firstTimestamp == 0L) {
                firstTimestamp = timestampMs
            }

            // Конвертируем RGBA в NV12 (YUV420SemiPlanar)
            val yuvData = convertRGBAtoNV12(pixels, frameWidth, frameHeight)

            // Получаем буфер для кодирования
            val inputBufferIndex = codec.dequeueInputBuffer(10000)
            if (inputBufferIndex >= 0) {
                val inputBuffer = codec.getInputBuffer(inputBufferIndex)
                inputBuffer?.clear()
                inputBuffer?.put(yuvData)
                
                val presentationTimeUs = (timestampMs - firstTimestamp) * 1000
                codec.queueInputBuffer(inputBufferIndex, 0, yuvData.size, presentationTimeUs, 0)
            }

            // Получаем закодированные данные
            val bufferInfo = MediaCodec.BufferInfo()
            var outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 10000)
            
            while (outputBufferIndex >= 0) {
                if (videoTrackIndex < 0) {
                    val format = codec.outputFormat
                    videoTrackIndex = muxer.addTrack(format)
                    muxer.start()
                }

                val outputBuffer = codec.getOutputBuffer(outputBufferIndex)
                if (outputBuffer != null) {
                    muxer.writeSampleData(videoTrackIndex, outputBuffer, bufferInfo)
                }
                
                codec.releaseOutputBuffer(outputBufferIndex, false)
                outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 0)
            }

            result.success(true)
        } catch (e: Exception) {
            Log.e("FlutterWidgetRecorder", "Error pushing frame", e)
            result.error("PUSH_ERROR", "Failed to push frame: ${e.message}", null)
        }
    }

    private fun stopRecording(result: Result) {
        if (!isRecording.get()) {
            result.error("NOT_RECORDING", "No recording in progress", null)
            return
        }

        try {
            val codec = mediaCodec
            val muxer = mediaMuxer

            if (codec != null && muxer != null) {
                // Завершаем кодирование
                codec.stop()
                codec.release()
                
                // Завершаем муксер
                muxer.stop()
                muxer.release()
            }

            isRecording.set(false)
            result.success(outputFile?.absolutePath)
        } catch (e: Exception) {
            Log.e("FlutterWidgetRecorder", "Error stopping recording", e)
            result.error("STOP_ERROR", "Failed to stop recording: ${e.message}", null)
        } finally {
            cleanup()
        }
    }

    private fun cleanup() {
        mediaCodec?.release()
        mediaCodec = null
        mediaMuxer?.release()
        mediaMuxer = null
        videoTrackIndex = -1
        firstTimestamp = 0
        isRecording.set(false)
    }

    private fun convertRGBAtoNV12(rgba: ByteArray, width: Int, height: Int): ByteArray {
        val ySize = width * height
        val uvSize = (width * height) / 4
        val nv12 = ByteArray(ySize + 2 * uvSize)
        
        var yIndex = 0
        var uvIndex = ySize
        
        for (j in 0 until height) {
            for (i in 0 until width) {
                val rgbIndex = (j * width + i) * 4
                val r = rgba[rgbIndex].toInt() and 0xff
                val g = rgba[rgbIndex + 1].toInt() and 0xff
                val b = rgba[rgbIndex + 2].toInt() and 0xff
                
                // Конвертация RGB в Y (BT.601)
                nv12[yIndex++] = ((0.299 * r + 0.587 * g + 0.114 * b).toInt()).toByte()
                
                // Конвертация RGB в UV (только для четных пикселей)
                if (j % 2 == 0 && i % 2 == 0) {
                    // U = 0.492 * (B - Y)
                    // V = 0.877 * (R - Y)
                    val y = 0.299 * r + 0.587 * g + 0.114 * b
                    val u = 128 + (0.492 * (b - y)).toInt()
                    val v = 128 + (0.877 * (r - y)).toInt()
                    
                    nv12[uvIndex++] = u.coerceIn(0, 255).toByte()
                    nv12[uvIndex++] = v.coerceIn(0, 255).toByte()
                }
            }
        }
        
        return nv12
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        cleanup()
    }
}
