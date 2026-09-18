import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import '../theme/app_theme.dart';

class LiveDetectionScreen extends StatefulWidget {
  const LiveDetectionScreen({super.key});

  @override
  State<LiveDetectionScreen> createState() =>
      _LiveDetectionScreenState();
}

class _LiveDetectionScreenState
    extends State<LiveDetectionScreen> {
  static const String backendUrl =
      'http://127.0.0.1:8000';

  CameraController? _cameraController;

  List<CameraDescription> _cameras = [];

  bool _cameraReady = false;
  bool isScanning = false;
  bool isLoading = false;

  final FlutterTts _flutterTts = FlutterTts();

  List<DetectionItem> detections = [];

  String? analysisMessage;
  String? recommendedDirection;
  String? speechMessage;

  @override
  void initState() {
    super.initState();

    initializeCamera();
    initializeTts();
  }

  // =========================
  // CAMERA
  // =========================

  Future<void> initializeCamera() async {
    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        debugPrint('No camera found.');
        return;
      }

      CameraDescription selectedCamera =
          _cameras.first;

      for (final camera in _cameras) {
        if (camera.lensDirection ==
            CameraLensDirection.back) {
          selectedCamera = camera;
          break;
        }
      }

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _cameraReady = true;
      });
    } catch (e) {
      debugPrint(
        'Camera initialization error: $e',
      );
    }
  }

  // =========================
  // TEXT TO SPEECH
  // =========================

  Future<void> initializeTts() async {
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
    } catch (e) {
      debugPrint(
        'TTS initialization error: $e',
      );
    }
  }

  Future<void> speakText(String text) async {
    if (text.trim().isEmpty) return;

    try {
      await _flutterTts.stop();

      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);

      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint(
        'Voice error: $e',
      );
    }
  }

  // =========================
  // START DETECTION
  // =========================

  Future<void> startDetection() async {
    if (!_cameraReady ||
        _cameraController == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera is not ready yet.',
          ),
        ),
      );
      return;
    }

    setState(() {
      isScanning = true;
      isLoading = true;

      detections = [];

      analysisMessage = null;
      recommendedDirection = null;
      speechMessage = null;
    });

    try {
      // Take picture
      final XFile image =
          await _cameraController!.takePicture();

      // IMPORTANT:
      // Read image as bytes.
      // This works on Chrome/Web.
      final imageBytes =
          await image.readAsBytes();

      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '$backendUrl/vision/analyze',
        ),
      );

      // Upload image bytes
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'camera_image.jpg',
        ),
      );

      // Send request
      final streamedResponse =
          await request.send();

      final response =
          await http.Response.fromStream(
        streamedResponse,
      );

      // Check response
      if (response.statusCode != 200) {
        throw Exception(
          'Vision API returned '
          '${response.statusCode}: '
          '${response.body}',
        );
      }

      // Convert JSON response
      final data =
          jsonDecode(response.body);

      // Detection list
      final List<DetectionItem> resultList =
          [];

      if (data['objects'] is List) {
        for (final object
            in data['objects']) {
          if (object is Map) {
            resultList.add(
              DetectionItem.fromJson(
                Map<String, dynamic>.from(
                  object,
                ),
              ),
            );
          }
        }
      }

      final String message =
          data['message']?.toString() ??
              'Analysis completed.';

      final String direction =
          data['recommended_direction']
                  ?.toString() ??
              '';

      final String speech =
          data['speech']?.toString() ??
              message;

      if (!mounted) return;

      setState(() {
        isLoading = false;

        detections = resultList;

        analysisMessage = message;

        recommendedDirection =
            direction.isEmpty
                ? null
                : direction;

        speechMessage = speech;
      });

      // Speak result
      await speakText(speech);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        isScanning = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to analyze image.\n$e',
          ),
        ),
      );
    }
  }

  // =========================
  // STOP DETECTION
  // =========================

  Future<void> stopDetection() async {
    await _flutterTts.stop();

    if (!mounted) return;

    setState(() {
      isScanning = false;
      isLoading = false;

      detections = [];

      analysisMessage = null;
      recommendedDirection = null;
      speechMessage = null;
    });
  }

  // =========================
  // OBJECT ICON
  // =========================

  String getObjectIcon(String object) {
    switch (object.toLowerCase()) {
      case 'person':
        return '🚶';

      case 'door':
        return '🚪';

      case 'stairs':
        return '🪜';

      case 'chair':
        return '🪑';

      case 'car':
        return '🚗';

      case 'bicycle':
        return '🚲';

      case 'motorcycle':
        return '🏍️';

      case 'bus':
        return '🚌';

      case 'truck':
        return '🚚';

      case 'dog':
        return '🐕';

      case 'cat':
        return '🐈';

      case 'backpack':
        return '🎒';

      case 'suitcase':
        return '🧳';

      case 'cell phone':
        return '📱';

      case 'book':
        return '📖';

      case 'box':
        return '📦';

      case 'obstacle':
        return '⚠️';

      default:
        return '🔎';
    }
  }

  // =========================
  // BUILD
  // =========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          AppTheme.background,

      appBar: AppBar(
        backgroundColor:
            Colors.transparent,
        elevation: 0,

        title: const Text(
          'Live Detection',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),

        centerTitle: true,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            10,
            20,
            30,
          ),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [
              _buildCameraPreview(),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,

                children: [
                  const Text(
                    'Detected Objects',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  if (isScanning)
                    _buildScanningIndicator(),
                ],
              ),

              const SizedBox(height: 14),

              if (isLoading)
                _buildLoadingCard()

              else if (analysisMessage != null)
                _buildAnalysisCard()

              else if (!isScanning)
                _buildEmptyState()

              else if (detections.isEmpty)
                _buildNoDetection()

              else
                ...detections.map(
                  (detection) =>
                      _buildDetectionCard(
                    detection,
                  ),
                ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 56,

                child: ElevatedButton.icon(
                  onPressed: isScanning
                      ? stopDetection
                      : startDetection,

                  icon: Icon(
                    isScanning
                        ? Icons.stop_rounded
                        : Icons
                            .play_arrow_rounded,
                  ),

                  label: Text(
                    isScanning
                        ? 'Stop Detection'
                        : 'Start Detection',
                  ),

                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        isScanning
                            ? AppTheme.danger
                            : AppTheme.teal,

                    foregroundColor:
                        Colors.white,

                    elevation: 0,

                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        18,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================
  // CAMERA PREVIEW
  // =========================

  Widget _buildCameraPreview() {
    if (!_cameraReady ||
        _cameraController == null) {
      return Container(
        height: 280,
        width: double.infinity,

        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(28),

          color: AppTheme.deepTeal,
        ),

        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    return Container(
      height: 280,
      width: double.infinity,

      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(28),
      ),

      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(28),

        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: 280,

              child: CameraPreview(
                _cameraController!,
              ),
            ),

            Positioned(
              top: 16,
              left: 16,

              child: Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),

                decoration: BoxDecoration(
                  color: Colors.black
                      .withOpacity(0.5),

                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                ),

                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,

                      decoration:
                          BoxDecoration(
                        shape:
                            BoxShape.circle,

                        color: isScanning
                            ? Colors.greenAccent
                            : Colors.white70,
                      ),
                    ),

                    const SizedBox(width: 7),

                    Text(
                      isScanning
                          ? 'AI ACTIVE'
                          : 'CAMERA READY',

                      style:
                          const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight:
                            FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // SCANNING INDICATOR
  // =========================

  Widget _buildScanningIndicator() {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),

      decoration: BoxDecoration(
        color: AppTheme.mist,

        borderRadius:
            BorderRadius.circular(20),
      ),

      child: Text(
        'AI Active',

        style: TextStyle(
          color: AppTheme.deepTeal,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // =========================
  // ANALYSIS CARD
  // =========================

  Widget _buildAnalysisCard() {
    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: AppTheme.paper,

        borderRadius:
            BorderRadius.circular(20),

        boxShadow: [
          BoxShadow(
            blurRadius: 12,
            offset:
                const Offset(0, 5),

            color: Colors.black
                .withOpacity(0.06),
          ),
        ],
      ),

      child: Column(
        children: [
          Icon(
            Icons
                .check_circle_outline_rounded,

            size: 48,

            color: AppTheme.teal,
          ),

          const SizedBox(height: 12),

          const Text(
            'AI Analysis Complete',

            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            analysisMessage ?? '',

            textAlign:
                TextAlign.center,

            style: TextStyle(
              color: AppTheme.muted,
              fontSize: 14,
            ),
          ),

          if (recommendedDirection !=
              null) ...[
            const SizedBox(height: 10),

            Text(
              'Direction: '
              '$recommendedDirection',

              style: TextStyle(
                color: AppTheme.teal,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ],

          if (speechMessage != null) ...[
            const SizedBox(height: 12),

            IconButton(
              onPressed: () {
                speakText(
                  speechMessage!,
                );
              },

              icon: Icon(
                Icons.volume_up_rounded,

                color: AppTheme.teal,

                size: 30,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================
  // DETECTION CARD
  // =========================

  Widget _buildDetectionCard(
    DetectionItem detection,
  ) {
    final distanceText =
        detection.distance != null
            ? '${detection.distance!.toStringAsFixed(1)} m away'
            : 'Distance unavailable';

    final confidenceText =
        detection.confidence != null
            ? '${(detection.confidence! * 100).round()}% confidence'
            : 'Confidence unavailable';

    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),

      padding:
          const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: AppTheme.paper,

        borderRadius:
            BorderRadius.circular(20),

        boxShadow: [
          BoxShadow(
            blurRadius: 12,

            offset:
                const Offset(0, 5),

            color: Colors.black
                .withOpacity(0.06),
          ),
        ],
      ),

      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,

            alignment:
                Alignment.center,

            decoration: BoxDecoration(
              color: AppTheme.mist,

              borderRadius:
                  BorderRadius.circular(
                16,
              ),
            ),

            child: Text(
              getObjectIcon(
                detection.object,
              ),

              style:
                  const TextStyle(
                fontSize: 25,
              ),
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                Text(
                  detection.object,

                  style:
                      const TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  '${detection.position} • '
                  '$distanceText',

                  style: TextStyle(
                    color:
                        AppTheme.muted,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  confidenceText,

                  style: TextStyle(
                    color:
                        AppTheme.teal,
                    fontSize: 12,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          Icon(
            Icons
                .chevron_right_rounded,

            color:
                AppTheme.muted,
          ),
        ],
      ),
    );
  }

  // =========================
  // LOADING CARD
  // =========================

  Widget _buildLoadingCard() {
    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.all(25),

      decoration: BoxDecoration(
        color: AppTheme.paper,

        borderRadius:
            BorderRadius.circular(20),
      ),

      child: Column(
        children: [
          const CircularProgressIndicator(),

          const SizedBox(height: 15),

          Text(
            'Analyzing camera image...',

            style: TextStyle(
              color: AppTheme.text,
              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // EMPTY STATE
  // =========================

  Widget _buildEmptyState() {
    return _infoCard(
      Icons.camera_alt_outlined,
      'Ready to scan',
      'Point the camera at your surroundings '
          'and start detection.',
    );
  }

  // =========================
  // NO DETECTION
  // =========================

  Widget _buildNoDetection() {
    return _infoCard(
      Icons.search_off_rounded,
      'Nothing detected',
      'Try pointing the camera in another '
          'direction.',
    );
  }

  // =========================
  // INFO CARD
  // =========================

  Widget _infoCard(
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.all(22),

      decoration: BoxDecoration(
        color: AppTheme.paper,

        borderRadius:
            BorderRadius.circular(20),
      ),

      child: Column(
        children: [
          Icon(
            icon,

            size: 40,

            color:
                AppTheme.teal,
          ),

          const SizedBox(height: 12),

          Text(
            title,

            style:
                const TextStyle(
              fontSize: 17,
              fontWeight:
                  FontWeight.w800,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            subtitle,

            textAlign:
                TextAlign.center,

            style: TextStyle(
              color:
                  AppTheme.muted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // DISPOSE
  // =========================

  @override
  void dispose() {
    _cameraController?.dispose();
    _flutterTts.stop();

    super.dispose();
  }
}

// ======================================================
// DETECTION MODEL
// ======================================================

class DetectionItem {
  final String object;
  final String position;
  final double? distance;
  final double? confidence;

  DetectionItem({
    required this.object,
    required this.position,
    this.distance,
    this.confidence,
  });

  factory DetectionItem.fromJson(
    Map<String, dynamic> json,
  ) {
    return DetectionItem(
      object:
          json['object']?.toString() ??
          json['class']?.toString() ??
          json['name']?.toString() ??
          'Unknown',

      position:
          json['position']?.toString() ??
          'CENTER',

      distance:
          _toDouble(
            json['distance'],
          ),

      confidence:
          _toDouble(
            json['confidence'],
          ),
    );
  }

  static double? _toDouble(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    );
  }
}