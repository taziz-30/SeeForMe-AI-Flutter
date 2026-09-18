import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class TextReaderScreen extends StatefulWidget {
  const TextReaderScreen({super.key});

  @override
  State<TextReaderScreen> createState() => _TextReaderScreenState();
}

class _TextReaderScreenState extends State<TextReaderScreen> {
  CameraController? _cameraController;
  final FlutterTts _tts = FlutterTts();

  bool _cameraReady = false;
  bool _isScanning = false;
  bool _isSpeaking = false;

  String _status = "Starting camera...";
  String _detectedText = "";

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeAudio();
  }

  // ============================================================
  // CAMERA INITIALIZATION
  // ============================================================

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() {
          _status = "No camera found.";
        });
        return;
      }

      final camera = cameras.first;

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _cameraReady = true;
        _status = "Camera ready";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _status = "Camera error";
      });
    }
  }

  // ============================================================
  // AUDIO / TEXT TO SPEECH
  // ============================================================

  Future<void> _initializeAudio() async {
    try {
      await _tts.setLanguage("en-US");
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      await _tts.awaitSpeakCompletion(true);

      _tts.setStartHandler(() {
        if (!mounted) return;

        setState(() {
          _isSpeaking = true;
        });
      });

      _tts.setCompletionHandler(() {
        if (!mounted) return;

        setState(() {
          _isSpeaking = false;
        });
      });

      _tts.setCancelHandler(() {
        if (!mounted) return;

        setState(() {
          _isSpeaking = false;
        });
      });

      _tts.setErrorHandler((message) {
        if (!mounted) return;

        setState(() {
          _isSpeaking = false;
        });
      });
    } catch (e) {
      debugPrint("Audio initialization error: $e");
    }
  }

  // ============================================================
  // IMAGE ORIENTATION CORRECTION
  // ============================================================

  Future<Uint8List> _correctImageOrientation(
    Uint8List bytes,
  ) async {
    final decoded = img.decodeImage(bytes);

    if (decoded == null) {
      return bytes;
    }

    // Remove camera EXIF orientation first.
    final oriented = img.bakeOrientation(decoded);

    // Your camera/OCR problem was upside-down text.
    // Rotate the image 180 degrees before sending to OCR.
    final corrected = img.copyRotate(
      oriented,
      angle: 180,
    );

    return Uint8List.fromList(
      img.encodeJpg(
        corrected,
        quality: 95,
      ),
    );
  }

  // ============================================================
  // OCR SCAN
  // ============================================================

  Future<void> _scanText() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isScanning = true;
      _status = "Scanning text...";
    });

    try {
      // Capture image
      final XFile capturedFile =
          await _cameraController!.takePicture();

      // Read captured image
      final Uint8List originalBytes =
          await capturedFile.readAsBytes();

      // Correct upside-down orientation
      final Uint8List correctedBytes =
          await _correctImageOrientation(
        originalBytes,
      );

      // Send corrected image to FastAPI OCR
      final request = http.MultipartRequest(
        "POST",
        Uri.parse(
          "http://127.0.0.1:8000/ocr/read",
        ),
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          "file",
          correctedBytes,
          filename: "corrected_ocr_image.jpg",
        ),
      );

      final response = await request.send();

      final responseBody =
          await response.stream.bytesToString();

      if (response.statusCode != 200) {
        throw Exception(
          "OCR server returned ${response.statusCode}",
        );
      }

      final data = jsonDecode(responseBody);

      final String text =
          (data["text"] ?? "").toString().trim();

      if (!mounted) return;

      setState(() {
        _detectedText = text;

        if (text.isNotEmpty) {
          _status = "Text detected successfully";
        } else {
          _status = "No text detected";
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _status =
            "Unable to connect to OCR server";
      });

      debugPrint("OCR Error: $e");
    } finally {
      if (!mounted) return;

      setState(() {
        _isScanning = false;
      });
    }
  }

  // ============================================================
  // READ ALOUD
  // ============================================================

  Future<void> _readAloud() async {
    if (_detectedText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please scan text first.",
          ),
        ),
      );
      return;
    }

    try {
      await _tts.stop();

      await _tts.setLanguage("en-US");
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      await _tts.speak(
        _detectedText,
      );
    } catch (e) {
      debugPrint("TTS Error: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Audio could not be played.",
          ),
        ),
      );
    }
  }

  // ============================================================
  // STOP AUDIO
  // ============================================================

  Future<void> _stopAudio() async {
    await _tts.stop();

    if (!mounted) return;

    setState(() {
      _isSpeaking = false;
    });
  }

  // ============================================================
  // COPY TEXT
  // ============================================================

  Future<void> _copyText() async {
    if (_detectedText.trim().isEmpty) {
      return;
    }

    await Clipboard.setData(
      ClipboardData(
        text: _detectedText,
      ),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Text copied successfully.",
        ),
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _tts.stop();
    _cameraController?.dispose();
    super.dispose();
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Text Reader",
        ),
        centerTitle: true,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,

            children: [

              // ==================================================
              // CAMERA PREVIEW
              // ==================================================

              Container(
                height: 320,

                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius:
                      BorderRadius.circular(20),
                ),

                clipBehavior:
                    Clip.hardEdge,

                child: _cameraReady &&
                        _cameraController != null
                    ? CameraPreview(
                        _cameraController!,
                      )
                    : const Center(
                        child:
                            CircularProgressIndicator(),
                      ),
              ),

              const SizedBox(height: 16),

              // ==================================================
              // STATUS
              // ==================================================

              Text(
                _status,
                textAlign: TextAlign.center,

                style: const TextStyle(
                  fontSize: 16,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),

              const SizedBox(height: 16),

              // ==================================================
              // SCAN BUTTON
              // ==================================================

              ElevatedButton.icon(
                onPressed:
                    _cameraReady &&
                            !_isScanning
                        ? _scanText
                        : null,

                icon: const Icon(
                  Icons.document_scanner,
                ),

                label: Text(
                  _isScanning
                      ? "Scanning..."
                      : "Scan Text",
                ),

                style:
                    ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ==================================================
              // DETECTED TEXT TITLE
              // ==================================================

              const Text(
                "Detected Text",

                style: TextStyle(
                  fontSize: 20,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              // ==================================================
              // DETECTED TEXT BOX
              // ==================================================

              Container(
                width: double.infinity,

                padding:
                    const EdgeInsets.all(16),

                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(16),

                  border: Border.all(
                    color:
                        Colors.grey.shade300,
                  ),
                ),

                child: _detectedText
                        .isEmpty
                    ? const Text(
                        "Scanned text will appear here.",
                        style: TextStyle(
                          color:
                              Colors.grey,
                          fontSize: 16,
                        ),
                      )
                    : Text(
                        _detectedText,

                        style:
                            const TextStyle(
                          fontSize: 18,
                          height: 1.5,
                        ),
                      ),
              ),

              const SizedBox(height: 15),

              // ==================================================
              // READ ALOUD
              // ==================================================

              ElevatedButton.icon(
                onPressed:
                    _detectedText
                            .isEmpty
                        ? null
                        : _readAloud,

                icon: Icon(
                  _isSpeaking
                      ? Icons.volume_up
                      : Icons.play_arrow,
                ),

                label: Text(
                  _isSpeaking
                      ? "Playing Audio..."
                      : "Read Aloud",
                ),

                style:
                    ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ==================================================
              // STOP AUDIO
              // ==================================================

              OutlinedButton.icon(
                onPressed:
                    _isSpeaking
                        ? _stopAudio
                        : null,

                icon: const Icon(
                  Icons.stop,
                ),

                label: const Text(
                  "Stop Audio",
                ),
              ),

              const SizedBox(height: 10),

              // ==================================================
              // COPY
              // ==================================================

              OutlinedButton.icon(
                onPressed:
                    _detectedText
                            .isEmpty
                        ? null
                        : _copyText,

                icon: const Icon(
                  Icons.copy,
                ),

                label: const Text(
                  "Copy Text",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}