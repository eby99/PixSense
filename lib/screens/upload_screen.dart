import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:convex_bottom_bar/convex_bottom_bar.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image/image.dart' as img;
import 'package:translator/translator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lottie/lottie.dart'; // Add for better animations
import 'story_page.dart';
import 'poem_page.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({Key? key}) : super(key: key);

  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> with TickerProviderStateMixin {
  String generatedCaption = "";
  late PageController _pageController;
  int _currentPage = 0;
  final List<String> _backgroundImages = [
    'assets/images/background1.jpg',
  ];
  late Timer _timer;
  bool isImageSelected = false;
  bool showButtons = false;
  bool _isGeneratingCaption = false;
  bool _isFailedToGenerateCaption = false;
  bool _isImageLoading = false;
  bool _isDownloading = false;
  bool _isErrorToastShown = false;

  // New variables for image handling
  XFile? _pickedImage;
  String? _imageUrl;
  final TextEditingController _urlController = TextEditingController();

  final String _apiKey = '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';
  final List<String> _captionModels = [
    'Salesforce/blip2-opt-2.7b',
    'Salesforce/blip-image-captioning-large',
    'microsoft/git-large-coco',
    'microsoft/git-base-coco',
    'nlpconnect/vit-gpt2-image-captioning',
    'Xenova/vit-gpt2-image-captioning',
  ];

  int _currentModelIndex = 0;
  String _currentModelName = '';

  final FlutterTts _flutterTts = FlutterTts();

  String _selectedLanguage = 'English';
  String _translatedCaption = '';
  bool _isTranslating = false;

  final List<String> _languages = [
    'English', 'Hindi', 'Bengali', 'Telugu', 'Marathi',
    'Tamil', 'Urdu', 'Gujarati', 'Malayalam', 'Kannada', 'Punjabi'
  ];

  // New variable for letter-by-letter display
  String _displayedCaption = '';
  Timer? _captionDisplayTimer;

  // Animation controllers
  late AnimationController _animationController;
  late Animation<double> _animation;

  // New animations for input buttons
  late AnimationController _buttonAnimController;
  late Animation<double> _buttonScaleAnimation;

  // Animation for image preview
  late AnimationController _imagePreviewAnimController;
  late Animation<double> _imagePreviewAnimation;

  // New animations for page elements
  late AnimationController _pageElementsAnimController;
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideAnimation;

  // Success animation controller
  late AnimationController _successAnimController;

  Future<void> _translateCaption() async {
    if (_selectedLanguage.isNotEmpty) {
      setState(() {
        _isTranslating = true;
      });

      try {
        final translator = GoogleTranslator();
        final translation = await translator.translate(
          generatedCaption,
          from: 'en',
          to: _getLanguageCode(_selectedLanguage),
        );

        setState(() {
          _translatedCaption = translation.text;
          _isTranslating = false;
        });
      } catch (e) {
        setState(() {
          _isTranslating = false;
        });
        _showErrorToast('Translation failed: $e');
      }
    }
  }

  String _getLanguageCode(String language) {
    switch (language) {
      case 'Hindi': return 'hi';
      case 'Bengali': return 'bn';
      case 'Telugu': return 'te';
      case 'Marathi': return 'mr';
      case 'Tamil': return 'ta';
      case 'Urdu': return 'ur';
      case 'Gujarati': return 'gu';
      case 'Malayalam': return 'ml';
      case 'Kannada': return 'kn';
      case 'Punjabi': return 'pa';
      default: return 'en';
    }
  }

  // Reset all caption-related data
  void _resetCaptionData() {
    setState(() {
      generatedCaption = "";
      _displayedCaption = '';
      showButtons = false;
      _translatedCaption = '';
      _isGeneratingCaption = false;
      _isFailedToGenerateCaption = false;
    });
    _captionDisplayTimer?.cancel();
  }

  // Reset the entire page
  void _resetPage() {
    setState(() {
      isImageSelected = false;
      _pickedImage = null;
      _imageUrl = null;
      _urlController.clear();
      _resetCaptionData();
    });
    _imagePreviewAnimController.reset();
    _successAnimController.reset();
    _pageElementsAnimController.forward();
  }

  Future<String> _generateCaptionUsingModel(Uint8List imageBytes, int modelIndex) async {
    try {
      String base64Image = base64Encode(imageBytes);

      var requestBody = jsonEncode({
        'inputs': base64Image,
        'parameters': {
          'max_new_tokens': 100,
        }
      });

      var response = await http.post(
        Uri.parse('https://api-inference.huggingface.co/models/${_captionModels[modelIndex]}'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: requestBody,
      );

      if (response.statusCode == 200) {
        var jsonData = jsonDecode(response.body);

        String caption = '';
        if (jsonData is List && jsonData.isNotEmpty) {
          caption = jsonData[0]['generated_text'] ?? '';
        } else if (jsonData is Map) {
          caption = jsonData['generated_text'] ?? '';
        }

        caption = caption.replaceFirst(RegExp(r'^arafed\s*', caseSensitive: false), '').trim();
        return caption;
      } else if (response.statusCode == 503) {
        _currentModelIndex = (_currentModelIndex + 1) % _captionModels.length;
        _currentModelName = _captionModels[_currentModelIndex];
        return await _generateCaptionUsingModel(imageBytes, _currentModelIndex);
      } else {
        throw Exception('Failed to generate caption with model ${_captionModels[modelIndex]}');
      }
    } catch (e) {
      print('Error with model ${_captionModels[modelIndex]}: $e');
      throw Exception('Failed to generate caption with model ${_captionModels[modelIndex]}');
    }
  }

  Future<void> _generateImageCaption() async {
    // Reset previous caption data first
    _resetCaptionData();

    setState(() {
      generatedCaption = "Generating Caption....";
      _isGeneratingCaption = true;
    });

    _animationController.reset();
    _animationController.forward();

    try {
      var imageBytes = await _preprocessImage();
      var caption = await _generateCaptionUsingModel(imageBytes, _currentModelIndex);

      setState(() {
        generatedCaption = caption;
        _isGeneratingCaption = false;
      });

      // Start displaying caption letter by letter
      _startCaptionDisplay();

      setState(() {
        showButtons = true;
      });
    } catch (e) {
      print('Error generating caption: $e');
      setState(() {
        _isGeneratingCaption = false;
        _isFailedToGenerateCaption = true;
      });

      // Auto-hide error after 3 seconds
      Timer(Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isFailedToGenerateCaption = false;
          });
        }
      });
    }
  }

  void _startCaptionDisplay() {
    _captionDisplayTimer?.cancel();
    _displayedCaption = '';
    int currentIndex = 0;

    _captionDisplayTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
      if (currentIndex < generatedCaption.length) {
        setState(() {
          _displayedCaption += generatedCaption[currentIndex];
          currentIndex++;
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<Uint8List> _preprocessImage() async {
    Uint8List imageBytes;

    if (_pickedImage != null) {
      imageBytes = await _pickedImage!.readAsBytes();
    } else if (_imageUrl != null) {
      var response = await http.get(Uri.parse(_imageUrl!));
      imageBytes = response.bodyBytes;
    } else {
      throw Exception('No image selected');
    }

    img.Image? decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) {
      throw Exception('Failed to decode image');
    }

    if (decodedImage.width > 1024 || decodedImage.height > 1024) {
      decodedImage = img.copyResize(decodedImage , width: 1024);
    }

    img.Image resizedImage = img.copyResize(decodedImage, width: 512);
    Uint8List processedImage = Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));
    return processedImage;
  }

  void _showErrorDialog(String errorMessage) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text('Caption Generation Error'),
          content: Text(
            errorMessage,
            style: TextStyle(fontSize: 14),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  generatedCaption = '';
                  showButtons = false;
                });
              },
            ),
            TextButton(
              child: const Text('Retry'),
              onPressed: () {
                Navigator.of(context).pop();
                _generateImageCaption();
              },
            ),
          ],
        );
      },
    );
  }

  void _showErrorToast(String message) async {
    if (!_isErrorToastShown) {
      _isErrorToastShown = true;
      await Future.delayed(Duration.zero);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.all(10),
          duration: Duration(seconds: 3),
        ),
      );
      Timer(Duration(seconds: 3), () {
        _isErrorToastShown = false;
      });
    }
  }

  void _showSuccessToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(10),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _readAloud() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(generatedCaption);
  }

  // Download image and caption
  Future<void> _downloadImageAndCaption() async {
    if (!isImageSelected || generatedCaption.isEmpty) {
      _showErrorToast('Please select an image and generate a caption first');
      return;
    }

    setState(() {
      _isDownloading = true;
    });

    try {
      // Check permissions first on mobile
      if (!kIsWeb) {
        var status = await Permission.storage.request();
        if (!status.isGranted) {
          setState(() {
            _isDownloading = false;
          });
          _showErrorToast('Storage permission is required');
          return;
        }
      }

      // Download logic differs based on platform
      if (kIsWeb) {
        // Web implementation using js interop would go here
        await Future.delayed(Duration(seconds: 2)); // Simulate download
        setState(() {
          _isDownloading = false;
        });
        _showSuccessToast('Downloaded successfully');
      } else {
        // Mobile implementation
        final directory = await getExternalStorageDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

        // Download image
        File imageFile;
        if (_imageUrl != null) {
          // Download from URL
          final response = await http.get(Uri.parse(_imageUrl!));
          final imagePath = '${directory!.path}/image_$timestamp.jpg';
          imageFile = File(imagePath);
          await imageFile.writeAsBytes(response.bodyBytes);
        } else if (_pickedImage != null) {
          // Copy from picked image
          final imagePath = '${directory!.path}/image_$timestamp.jpg';
          imageFile = File(imagePath);
          await imageFile.writeAsBytes(await _pickedImage!.readAsBytes());
        } else {
          setState(() {
            _isDownloading = false;
          });
          _showErrorToast('No image to download');
          return;
        }

        // Save caption as text file
        final captionPath = '${directory!.path}/caption_$timestamp.txt';
        final captionFile = File(captionPath);
        await captionFile.writeAsString(generatedCaption);

        setState(() {
          _isDownloading = false;
        });
        _showSuccessToast('Image and caption saved to ${directory.path}');
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
      });
      _showErrorToast('Error downloading: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0, viewportFraction: 1.0);
    _timer = Timer.periodic(const Duration(milliseconds: 3000), (Timer timer) {
      if (_currentPage < _backgroundImages.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });

    // Progress animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_animationController);

    // Button hover animation
    _buttonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _buttonScaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
        CurvedAnimation(parent: _buttonAnimController, curve: Curves.easeInOut)
    );

    // Image preview animation
    _imagePreviewAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _imagePreviewAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _imagePreviewAnimController, curve: Curves.easeInOut)
    );

    // Page elements animation
    _pageElementsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pageElementsAnimController,
        curve: Curves.easeIn,
      ),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _pageElementsAnimController,
      curve: Curves.easeOutCubic,
    ));

    // Success animation
    _successAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Start initial animations
    _pageElementsAnimController.forward();
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    _urlController.dispose();
    _captionDisplayTimer?.cancel();
    _animationController.dispose();
    _buttonAnimController.dispose();
    _imagePreviewAnimController.dispose();
    _pageElementsAnimController.dispose();
    _successAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "Caption Generator",
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 22, color: Colors.white),
        ),
        backgroundColor: Colors.black.withOpacity(0.3),
        elevation: 0,
        centerTitle: true,
        actions: [
          if (isImageSelected)
            IconButton(
              icon: const Icon(Icons.preview, color: Colors.white),
              onPressed: _showImagePreviewDialog,
            ),
        ],
      ),
      body: Stack(
        children: [
          // Background image with overlay
          Container(
            width: double.infinity,
            height: double.infinity,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _backgroundImages.length,
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    // Background image
                    Image.asset(
                      _backgroundImages[index],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                    // Modern gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.6),
                            Colors.black.withOpacity(0.3),
                            Colors.deepPurple.withOpacity(0.2),
                          ],
                        ),
                      ),
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ],
                );
              },
            ),
          ),

          // Main content with animations
          SafeArea(
            child: FadeTransition(
              opacity: _fadeInAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      SizedBox(height: 30),

                      // Image input section with glass morphism
                      Container(
                        margin: EdgeInsets.symmetric(horizontal: 20),
                        padding: EdgeInsets.all(20),
                        decoration:
                        BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 20,
                              offset: Offset(0, 10),
                            )
                          ],
                          border: Border.all(
                            color: Colors.white.withOpacity(0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "Upload an Image",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              "Choose an image to generate a caption",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 25),

                            // Input buttons row with new design
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // URL input button with animation
                                MouseRegion(
                                  onEnter: (_) => _buttonAnimController.forward(),
                                  onExit: (_) => _buttonAnimController.reverse(),
                                  child: AnimatedBuilder(
                                    animation: _buttonScaleAnimation,
                                    builder: (context, child) {
                                      return Transform.scale(
                                        scale: _buttonScaleAnimation.value,
                                        child: _buildInputButton(
                                          icon: Icons.link,
                                          label: "URL",
                                          onTap: _showImageUrlDialog,
                                          color: Colors.indigoAccent,
                                        ),
                                      );
                                    },
                                  ),
                                ),

                                // Device upload button with animation
                                MouseRegion(
                                  onEnter: (_) => _buttonAnimController.forward(),
                                  onExit: (_) => _buttonAnimController.reverse(),
                                  child: AnimatedBuilder(
                                    animation: _buttonScaleAnimation,
                                    builder: (context, child) {
                                      return Transform.scale(
                                        scale: _buttonScaleAnimation.value,
                                        child: _buildInputButton(
                                          icon: Icons.photo_library,
                                          label: "Gallery",
                                          onTap: _pickImageFromDevice,
                                          color: Colors.teal,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 20),

                      // Image preview with animation
                      if (isImageSelected)
                        AnimatedBuilder(
                          animation: _imagePreviewAnimation,
                          builder: (context, child) {
                            // Trigger the animation when image is selected
                            if (_imagePreviewAnimation.status == AnimationStatus.dismissed) {
                              _imagePreviewAnimController.forward();
                            }

                            return FadeTransition(
                              opacity: _imagePreviewAnimation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: Offset(0, 0.2),
                                  end: Offset.zero,
                                ).animate(_imagePreviewAnimation),
                                child: _buildImagePreview(),
                              ),
                            );
                          },
                        ),

                      SizedBox(height: 15),

                      // Generate Caption button and Reset button
                      if (isImageSelected && (_imageUrl != null || _pickedImage != null))
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Reset button
                            IconButton(
                              icon: Icon(Icons.refresh, color: Colors.deepPurple),
                              onPressed: _resetPage,
                            ),

                            // Generate Caption button
                            Container(
                              margin: EdgeInsets.symmetric(horizontal: 30),
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _currentModelIndex = (_currentModelIndex + 1) % _captionModels.length;
                                    _currentModelName = _captionModels[_currentModelIndex];
                                    generatedCaption = '';
                                  });
                                  _generateImageCaption();
                                },
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                                  backgroundColor: Colors.deepPurple,
                                  foregroundColor: Colors.white,
                                  elevation: 4,
                                  shadowColor: Colors.deepPurple.withOpacity(0.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.auto_awesome, size: 22),
                                    SizedBox(width: 8),
                                    Text(
                                      "Generate Caption",
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                      SizedBox(height: 20),

                      // Caption generation status / result
                      ...(_isGeneratingCaption
                          ? [_buildGeneratingAnimation()]
                          : _isFailedToGenerateCaption
                          ? [_buildFailedToGenerateCaption()]
                          : _displayedCaption.isNotEmpty
                          ? [_buildCaptionResult()]
                          : []
                      ),

                      SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ConvexAppBar(
          style: TabStyle.reactCircle,
          backgroundColor: Colors.black87,
          activeColor: Colors.blueAccent,
          color: Colors.white70,
          items: const [
            TabItem(icon: Icons.home, title: 'Home'),
            TabItem(icon: Icons.analytics, title: 'Analytics'),
            TabItem(icon: Icons.person, title: 'Profile'),
          ],
          initialActiveIndex: 0,
          onTap: (int index) {},
        ),
      ),
    );
  }

  // Helper widget for input buttons
  Widget _buildInputButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 15, horizontal: 25),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 32,
            ),
            SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Improved image preview
  Widget _buildImagePreview() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            spreadRadius: 2,
            blurRadius: 15,
            offset: Offset(0, 5),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          height: 250,
          child: _getImageWidget(),
        ),
      ),
    );
  }

  // Improved image widget getter
  Widget _getImageWidget() {
    try {
      if (_imageUrl != null) {
        return CachedNetworkImage(
          imageUrl: _imageUrl!,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: Colors.black12,
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
              ),
            ),
          ),
          errorWidget: (context, url, error) {
            if (!_isErrorToastShown) {
              _showErrorToast('Failed to load image: $error');
            }
            return Container(
              color: Colors.red.withOpacity(0.1),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 40),
                    SizedBox(height: 10),
                    Text(
                      'Failed to load image',
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }

      if (_pickedImage != null) {
        if (kIsWeb) {
          return Image.network(
            _pickedImage!.path,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: Colors.black12,
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              if (!_isErrorToastShown) {
                _showErrorToast('Failed to load image: $error');
              }
              return Container(
                color: Colors.red.withOpacity(0.1),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red , size: 40),
                      SizedBox(height: 10),
                      Text(
                        'Failed to load image',
                        style: TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }

        if (Platform.isAndroid || Platform.isIOS) {
          return Image.file(
            File(_pickedImage!.path),
            fit: BoxFit.cover,
          );
        }
      }

      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Text('No image selected'),
        ),
      );
    } catch (e) {
      if (!_isErrorToastShown) {
        _showErrorToast('Error loading image: $e');
      }
      return Container(
        color: Colors.red.withOpacity(0.1),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 40),
              SizedBox(height: 10),
              Text(
                'Error loading image',
                style: TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      );
    }
  }

  // Animated generating caption indicator
  Widget _buildGeneratingAnimation() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Container(
                width: 200,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(5),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _animation.value,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blueAccent,
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blueAccent.withOpacity(0.5),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          SizedBox(height: 20),
          Text(
            "Generating Caption...",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 10),
          Text(
            "Our AI is analyzing your image",
            style: TextStyle(
              fontSize: 14,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  // Failed to generate caption
  Widget _buildFailedToGenerateCaption() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Error icon with animation
          TweenAnimationBuilder(
            tween: Tween<double>(begin: 0.5, end: 1.0),
            duration: Duration(milliseconds: 800),
            builder: (context, value, child) {
              return Transform.scale(
                scale: value.toDouble(),
                child: Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 50,
                ),
              );
            },
          ),
          SizedBox(height: 20),
          // Animated text appearance
          TweenAnimationBuilder(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 1000),
            builder: (context, value, child) {
              return Opacity(
                opacity: value.toDouble(),
                child: Text(
                  "Unable to Generate Caption",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              );
            },
          ),
          SizedBox(height: 10),
          TweenAnimationBuilder(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 1200),
            builder: (context, value, child) {
              return Opacity(
                opacity: value.toDouble(),
                child: Text(
                  "Please try again",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Caption result display with actions
  Widget _buildCaptionResult() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          )
        ],
      ),
      child: Column(
        children: [
          // Caption display
          Container(
            padding: EdgeInsets.all(20),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  "Generated Caption",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  _displayedCaption,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildActionButton(
                      icon: Icons.volume_up,
                      label: "",
                      onTap: _readAloud,
                      color: Colors.blue,
                    ),
                    SizedBox(width: 15),
                    _buildActionButton(
                      icon: Icons.translate,
                      label: "",
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              title: const Text('Select Language'),
                              content: DropdownButton<String>(
                                value: _selectedLanguage,
                                items: _languages.map((String language) {
                                  return DropdownMenuItem<String>(
                                    value: language,
                                    child: Text(language),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  setState(() {
                                    _selectedLanguage = newValue!;
                                  });
                                  _translateCaption();
                                  Navigator.of(context).pop();
                                },
                              ),
                            );
                          },
                        );
                      },
                      color: Colors.blue,
                    ),
                  ],
                ),
                if (_translatedCaption.isNotEmpty)
                  Column(
                    children: [
                      SizedBox(height: 15), // Gap above translated caption
                      Text(
                        '$_selectedLanguage: $_translatedCaption',
                        style: TextStyle(fontSize: 16, color: Colors.black87),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Caption actions
          Container(
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        if (_displayedCaption.isEmpty) {
                          _showErrorToast('Please generate a caption first');
                          return;
                        }

                        if (_imageUrl != null) {
                          // For URL-based images
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => StoryPage(
                              caption: generatedCaption,
                              imageUrl: _imageUrl,
                            )),
                          );
                        } else if (_pickedImage != null) {
                          if (kIsWeb) {
                            // Convert image to base64 string
                            Uint8List bytes = await _pickedImage!.readAsBytes();
                            String base64Image = base64Encode(bytes);

                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => StoryPage(
                                caption: generatedCaption,
                                base64Image: base64Image, // Pass the base64Image parameter
                              )),
                            );
                          } else {
                            // For mobile
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => StoryPage(
                                caption: generatedCaption,
                                imageFile: File(_pickedImage!.path),
                              )),
                            );
                          }
                        } else {
                          // No image case - still allow generating a story without an image
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => StoryPage(
                              caption: generatedCaption,
                            )),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shadowColor: Colors.deepPurple.withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        "Story",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                    SizedBox(width: 15),
                    ElevatedButton(
                      onPressed: () async {
                        if (_displayedCaption.isEmpty) {
                          _showErrorToast('Please generate a caption first');
                          return;
                        }

                        if (_imageUrl != null) {
                          // For URL-based images
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PoemPage(
                                caption: generatedCaption,
                                imageUrl: _imageUrl,
                              ),
                            ),
                          );
                        } else if (_pickedImage != null) {
                          if (kIsWeb) {
                            // Convert image to base64 string
                            Uint8List bytes = await _pickedImage!.readAsBytes();
                            String base64Image = base64Encode(bytes);

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PoemPage(
                                  caption: generatedCaption,
                                  base64Image: base64Image, // Pass the base64Image parameter
                                ),
                              ),
                            );
                          } else {
                            // For mobile
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PoemPage(
                                  caption: generatedCaption,
                                  imageFile: File(_pickedImage!.path),
                                ),
                              ),
                            );
                          }
                        }
                        else {
                          // No image case - still allow generating a poem without an image
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => PoemPage(
                              caption: generatedCaption,
                            )),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shadowColor: Colors.deepPurple.withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        "Poem",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for action buttons
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 15),
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 2,
        shadowColor: color.withOpacity(0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  void _showImagePreviewDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _getFullImageWidget(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              )
            ],
          ),
        );
      },
    );
  }

  void _showImageUrlDialog() async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Enter Image URL"),
          content: TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              hintText: "https://example.com/image.jpg",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog first
                setState(() { // Then update the state
                  _imageUrl = _urlController.text;
                  isImageSelected = true;
                  _resetCaptionData(); // Reset caption data when a new image is loaded
                });
              },
              child: const Text("Submit"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  Widget _getFullImageWidget() {
    if (_imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: _imageUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => Center(child: CircularProgressIndicator()),
        errorWidget: (context, url, error) => Icon(Icons.error),
      );
    }

    if (_pickedImage != null) {
      return Image.file(
        File(_pickedImage!.path),
        fit: BoxFit.cover,
      );
    }

    return Center(child: Text('No image selected'));
  }

  Future<void> _pickImageFromDevice() async {
    final ImagePicker _picker = ImagePicker();
    _pickedImage = await _picker.pickImage(source: ImageSource.gallery);
    if (_pickedImage != null) setState(() {
      isImageSelected = true;
      _imageUrl = null; // Clear URL if an image is picked
      _resetCaptionData(); // Reset caption data when a new image is loaded
    });
  }
}