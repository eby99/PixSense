import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math' as math;
import 'package:flutter_tts/flutter_tts.dart';

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() {
    return 'TimeoutException: $message';
  }
}

class PoemPage extends StatefulWidget {
  final String caption;
  final String? imageUrl;
  final File? imageFile;
  final String? base64Image;

  const PoemPage({
    Key? key,
    required this.caption,
    this.imageUrl,
    this.imageFile,
    this.base64Image,
  }) : super(key: key);

  @override
  _PoemPageState createState() => _PoemPageState();
}

class _PoemPageState extends State<PoemPage> with SingleTickerProviderStateMixin {
  String? _poem;
  bool _isLoading = false;
  String? _error;
  String _progressStatus = 'Initializing...';
  FlutterTts flutterTts = FlutterTts();
  bool _isSpeaking = false;
  int _poemAttempt = 0; // Counter to force new poem generation
  late AnimationController _animationController;
  late Animation<double> _animation;
  final ScrollController _scrollController = ScrollController();

  // Improved fallback poems with more variety
  final List<String> _fallbackPoems = [
    "Sunlight streams through ancient trees,\nCasting shadows, dancing free.\nMoss-covered rocks and gentle streams,\nA hidden world of timeless dreams.\n\nSilence broken only by water's song,\nWhere moments stretch eternally long.\nIn this sanctuary so pure and bright,\nTime pauses in its endless flight.",

    "Neon rainbows on wet pavement gleam,\nTwilight city wakes from daytime dream.\nHurried footsteps, umbrellas blooming wide,\nVendors call their wares with voices dignified.\n\nOne figure walks unhurried through the crowd,\nNoticing beauty where noise is loud.\nIn urban chaos finding grace and light,\nAs day surrenders to the coming night.",

    "Sentinel tower against darkening sky,\nBeacon spinning, reaching high.\nFor generations guiding ships to shore,\nThrough densest fog and ocean's roar.\n\nNow automated, still faithful, true,\nNo keeper climbs the stairs anew.\nYet legends whisper of a ghostly shape,\nWatching over waters as storm clouds drape.",

    "Colors dancing in the gentle breeze,\nPetals bowing to nature's expertise.\nSunlight transformed through nature's prism,\nA kaleidoscope of living optimism.\n\nTiny creatures move with silent grace,\nChanging hues to match each flowered face.\nMasters of disguise in vibrant lands,\nNature's artistry by unseen hands.",

    "Mirror lake reflects the endless sky,\nImpossible to tell where waters lie.\nPine sentinels stand in solemn rows,\nGuarding secrets only silence knows.\n\nUntouched by time, a sanctuary pure,\nFor weary souls seeking nature's cure.\nAs daylight fades to golden gleam,\nReality dissolves into a dream."
  ];

  // Different poem styles for variety
  final List<String> _poemStyles = [
    'sonnet',
    'haiku',
    'free verse',
    'quatrain',
    'acrostic',
    'cinquain',
    'ballad',
    'ode'
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
    _startGeneratingPoem();
  }

  @override
  void dispose() {
    _stopSpeaking();
    flutterTts.stop();
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);

    flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });
  }

  Future<void> _startSpeaking() async {
    if (_poem != null) {
      setState(() {
        _isSpeaking = true;
      });
      await flutterTts.speak(_poem!);
    }
  }

  Future<void> _stopSpeaking() async {
    if (_isSpeaking) {
      setState(() {
        _isSpeaking = false;
      });
      await flutterTts.stop();
    }
  }

  Future<void> _startGeneratingPoem() async {
    if (!mounted) return;

    // Stop any ongoing narration
    _stopSpeaking();

    setState(() {
      _isLoading = true;
      _error = null;
      _poem = null;
      _progressStatus = 'Starting poem generation...';
    });

    // Increment the poem attempt counter to ensure we get a different poem
    _poemAttempt++;

    try {
      await _generatePoem();
    } catch (e) {
      debugPrint('Error in _startGeneratingPoem: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
          _poem = null;
        });
      }
    }
  }

  Future<void> _generatePoem() async {
    try {
      _updateProgress('Creating a poem based on the image...');

      // Select a poem style based on attempt number for variety
      final poemStyle = _poemStyles[_poemAttempt % _poemStyles.length];

      // Create a more detailed and structured prompt that emphasizes poetic elements
      final String caption = widget.caption.trim();
      final prompt = "Write a beautiful $poemStyle poem (10-15 lines) inspired by this image description: \"$caption\". Include vivid imagery, emotion, and sensory details. Focus on creating rhythm and flow. The poem should be complete.";

      try {
        // Add the attempt number to ensure different results each time
        final response = await _makeHuggingFaceApiRequest(
            "$prompt (Attempt: $_poemAttempt)");
        if (!mounted) return;

        setState(() {
          _poem = _formatPoem(response.trim());
          _isLoading = false;
          _error = null;
        });

        // Scroll to top when new poem is loaded
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      } catch (e) {
        debugPrint('API error: $e - Falling back to local poem generation');
        _updateProgress('API unavailable. Using local poem generation...');

        // Fallback to local poem generation
        await _generateLocalPoem();
      }
    } catch (e, stackTrace) {
      debugPrint('Error in _generatePoem: $e');
      debugPrint('Stack trace: $stackTrace');

      // Final fallback - use a pre-written poem
      if (mounted) {
        _updateProgress('Falling back to pre-written poem...');
        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          setState(() {
            // Select a random fallback poem that best matches the caption
            // Use the attempt counter as additional randomization factor
            _poem = _selectBestFallbackPoem(_poemAttempt);
            _poem = _poem! +
                "\n\n[Note: This is a pre-written poem as the poem generation API is currently unavailable.]";
            _isLoading = false;
            _error = null;
          });
        }
      }
    }
  }

  String _formatPoem(String rawPoem) {
    // Clean up poem text while preserving all content
    String poem = rawPoem.trim();

    // Remove any potential instruction text or prefixes
    if (poem.contains("[/INST]")) {
      poem = poem
          .split("[/INST]")
          .last
          .trim();
    }

    // Remove any potential AI model completion markers
    poem = poem
        .replaceAll("<eos>", "")
        .replaceAll("<EOS>", "")
        .replaceAll("[END]", "")
        .replaceAll("[STOP]", "");

    // Preserve line breaks for proper poem formatting
    poem = poem.replaceAll(RegExp(r'\n{4,}'), '\n\n\n');

    // Add title if there isn't one already
    if (!poem.contains("\n\n") && !poem.contains("Title:")) {
      // Generate a title based on the first line
      final firstLine = poem
          .split('\n')
          .first;
      final words = firstLine.split(' ');
      final titleWords = words.length > 3 ? words.sublist(0, 3) : words;
      poem = "\"${titleWords.join(' ')}...\"\n\n$poem";
    }

    // If poem is too short, add a note
    if (poem.length < 80) {
      poem +=
      "\n\n[Note: The poem generation API provided a brief response. You can try again for a longer poem.]";
    }

    return poem;
  }

  String _selectBestFallbackPoem(int attempt) {
    // Extract keywords from caption
    final keywords = widget.caption
        .toLowerCase()
        .split(RegExp(r'[ ,\.!?]'))
        .where((word) => word.length > 3)
        .toList();

    // Score each fallback poem based on keyword matches
    Map<int, int> poemScores = {};

    for (int i = 0; i < _fallbackPoems.length; i++) {
      int score = 0;
      String poemLower = _fallbackPoems[i].toLowerCase();

      for (final keyword in keywords) {
        if (poemLower.contains(keyword)) {
          score += 1;
        }
      }

      poemScores[i] = score;
    }

    // Find the poem with the highest score
    int bestPoemIndex = 0;
    int highestScore = -1;

    poemScores.forEach((index, score) {
      if (score > highestScore) {
        highestScore = score;
        bestPoemIndex = index;
      }
    });

    // If no good match found or we're regenerating, force a different poem
    if (highestScore <= 0 || attempt > 1) {
      // Use the attempt number to ensure we get a different poem each time
      bestPoemIndex = (attempt % _fallbackPoems.length);
    }

    return _fallbackPoems[bestPoemIndex];
  }

  Future<void> _generateLocalPoem() async {
    if (!mounted) return;

    _updateProgress('Processing image description...');
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    _updateProgress('Finding poetic inspiration...');
    await Future.delayed(const Duration(milliseconds: 700));

    if (!mounted) return;
    _updateProgress('Crafting verses...');
    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;

    // Extract keywords from caption
    final keywords = widget.caption
        .toLowerCase()
        .split(RegExp(r'[ ,\.!?]'))
        .where((word) => word.length > 3)
        .toList();

    // Generate a more customized poem based on keywords and attempt number
    final poemElements = _generatePoemElements(keywords);
    final generatedPoem = _createPoemFromElements(
        poemElements, widget.caption, _poemAttempt);

    if (!mounted) return;

    setState(() {
      _poem = generatedPoem;
      _isLoading = false;
      _error = null;
    });
  }

  Map<String, dynamic> _generatePoemElements(List<String> keywords) {
    // Define some poem building blocks
    final themes = [
      'nature', 'love', 'time', 'memory', 'journey', 'reflection',
      'wonder', 'change', 'beauty', 'silence', 'dreams', 'courage',
      'hope', 'loss', 'renewal', 'mystery', 'solitude', 'connection'
    ];

    final moods = [
      'peaceful', 'nostalgic', 'contemplative', 'joyful', 'melancholic',
      'awed', 'hopeful', 'wistful', 'inspired', 'serene', 'mystical',
      'longing', 'grateful', 'somber', 'uplifted', 'reverent'
    ];

    final imagery = [
      'sunlight', 'shadows', 'stars', 'water', 'trees', 'mountains',
      'clouds', 'wind', 'flowers', 'moon', 'ocean', 'sky', 'leaves',
      'rain', 'snow', 'mist', 'rivers', 'stones', 'dawn', 'dusk'
    ];

    final colors = [
      'golden', 'silver', 'azure', 'emerald', 'crimson', 'amber',
      'violet', 'indigo', 'ivory', 'ebony', 'turquoise', 'copper',
      'sapphire', 'ruby', 'pearl', 'obsidian', 'jade', 'topaz'
    ];

    final sounds = [
      'whisper', 'rustle', 'echo', 'silence', 'melody', 'rhythm',
      'harmony', 'murmur', 'song', 'call', 'hum', 'chime', 'pulse'
    ];

    // Try to match keywords with poem elements
    String theme = _findMatchOrRandom(keywords, themes);
    String mood = _findMatchOrRandom(keywords, moods);
    String primaryImage = _findMatchOrRandom(keywords, imagery);
    String color = _findMatchOrRandom(keywords, colors);
    String sound = _findMatchOrRandom(keywords, sounds);

    return {
      'theme': theme,
      'mood': mood,
      'primaryImage': primaryImage,
      'color': color,
      'sound': sound
    };
  }

  String _findMatchOrRandom(List<String> keywords, List<String> options) {
    // Try to find a matching element from keywords
    for (final keyword in keywords) {
      for (final option in options) {
        if (keyword.contains(option) || option.contains(keyword)) {
          return option;
        }
      }
    }

    // If no match, return random element
    return options[DateTime
        .now()
        .millisecond % options.length];
  }

  String _createPoemFromElements(Map<String, dynamic> elements, String caption,
      int attempt) {
    // Rotate through different poem structures based on attempt number
    final poemFormats = [
      _createSimpleVerse,
      _createHaiku,
      _createSonnetStyle,
      _createFreeVerse,
      _createOdeStyle,
    ];

    // Use attempt number to select a different poem format each time
    final formatIndex = attempt % poemFormats.length;
    return poemFormats[formatIndex](elements, caption);
  }

  String _createSimpleVerse(Map<String, dynamic> elements, String caption) {
    final theme = elements['theme'];
    final mood = elements['mood'];
    final primaryImage = elements['primaryImage'];
    final color = elements['color'];
    final sound = elements['sound'];

    // Create a title based on elements
    final title = "The $mood $primaryImage";

    // Create a simple quatrain poem (4-line stanzas)
    final stanza1 = "$color $primaryImage in the $theme of light,\n" +
        "A $mood moment caught in time's flight.\n" +
        "The gentle $sound of $theme's embrace,\n" +
        "Reveals a world of wonder and grace.\n";

    final stanza2 = "Here in this image of ${_extractKeyNoun(caption)},\n" +
        "We glimpse the beauty that briefly stays.\n" +
        "A $mood whisper of what might be,\n" +
        "A $theme captured for eternity.\n";

    return "$title\n\n$stanza1\n$stanza2";
  }

  String _createHaiku(Map<String, dynamic> elements, String caption) {
    final primaryImage = elements['primaryImage'];
    final color = elements['color'];
    final mood = elements['mood'];

    // Create a title
    final title = "$color $primaryImage";

    // Traditional 5-7-5 syllable pattern (approximated)
    final line1 = "$color $primaryImage";
    final line2 = "${_extractKeyNoun(caption)} in $mood light";
    final line3 = "${elements['theme']} awakens";

    return "$title\n\n$line1\n$line2\n$line3";
  }

  String _createSonnetStyle(Map<String, dynamic> elements, String caption) {
    final theme = elements['theme'];
    final mood = elements['mood'];
    final primaryImage = elements['primaryImage'];
    final color = elements['color'];

    // Create a title
    final title = "Sonnet of the $primaryImage";

    // Create a shortened sonnet-inspired form (just two quatrains)
    final quatrain1 = "How does the $color $primaryImage shine,\n" +
        "When $mood moments capture the heart?\n" +
        "The ${_extractKeyNoun(caption)} reveals a sign,\n" +
        "That beauty and $theme shall never part.\n";

    final quatrain2 = "Like whispers of ${elements['sound']} through time,\n" +
        "This image holds secrets yet untold.\n" +
        "A vision of $mood grace, sublime,\n" +
        "More precious than treasures of gold.\n";

    return "$title\n\n$quatrain1\n$quatrain2";
  }

  String _createFreeVerse(Map<String, dynamic> elements, String caption) {
    final theme = elements['theme'];
    final mood = elements['mood'];
    final primaryImage = elements['primaryImage'];
    final color = elements['color'];
    final sound = elements['sound'];

    // Create a title
    final title = "Reflections";

    // Create a free verse poem with varied line lengths
    final verse = "In the $mood light\n" +
        "$color $primaryImage\n" +
        "Speaks of ${_extractKeyNoun(caption)}.\n\n" +
        "The $theme waits\n" +
        "Patient as centuries\n" +
        "While the $sound of time\n" +
        "Passes through us.\n\n" +
        "We are but moments\n" +
        "Captured in light and shadow\n" +
        "Beautiful\n" +
        "Transient\n" +
        "$mood.";

    return "$title\n\n$verse";
  }

  String _createOdeStyle(Map<String, dynamic> elements, String caption) {
    final theme = elements['theme'];
    final mood = elements['mood'];
    final primaryImage = elements['primaryImage'];
    final color = elements['color'];

    // Create a title
    final title = "Ode to the $primaryImage";

    // Create an ode-inspired poem
    final verse = "O $color $primaryImage, bearer of $theme,\n" +
        "How you stand in $mood splendor,\n" +
        "A testament to beauty's eternal scheme,\n" +
        "Your presence both powerful and tender.\n\n" +

        "Within you, I see ${_extractKeyNoun(caption)},\n" +
        "A vision that transcends the ordinary sight.\n" +
        "A glimpse of wonder that sets the spirit free,\n" +
        "Illuminated in nature's perfect light.";

    return "$title\n\n$verse";
  }

  String _extractKeyNoun(String caption) {
    // Extract potential key nouns from the caption
    final words = caption.split(' ');
    final nouns = words.where((word) =>
    word.length > 3 &&
        !word.toLowerCase().startsWith('the') &&
        !word.toLowerCase().startsWith('and') &&
        !word.toLowerCase().startsWith('with')
    ).toList();

    if (nouns.isEmpty) {
      return "beauty";
    }

    // Return a random noun from the extracted list
    return nouns[DateTime
        .now()
        .millisecond % nouns.length];
  }

  void _updateProgress(String status) {
    if (mounted) {
      setState(() {
        _progressStatus = status;
      });
    }
  }

  Future<String> _makeHuggingFaceApiRequest(String prompt) async {
    // Use a better instruction-following model
    final endpoint = 'https://api-inference.huggingface.co/models/mistralai/Mistral-7B-Instruct-v0.2';
    final apiKey = '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';

    // More structured prompt formatting for instruction models
    final requestBody = {
      'inputs': "<s>[INST] $prompt [/INST]",
      'parameters': {
        'max_new_tokens': 350,
        // Adjusted for poems which are typically shorter than stories
        'temperature': 0.8,
        // Slightly higher temperature for more creativity in poetry
        'return_full_text': false,
      },
    };

    try {
      debugPrint('Making API request with prompt: $prompt');
      debugPrint('Request body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      debugPrint('Response status code: ${response.statusCode}');
      debugPrint('Full response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final decoded = jsonDecode(response.body);
          String generatedText = '';

          if (decoded is List && decoded.isNotEmpty) {
            generatedText =
                decoded.first['generated_text'] ?? 'No text generated.';
          } else if (decoded is Map && decoded.containsKey('generated_text')) {
            generatedText = decoded['generated_text'];
          } else {
            throw Exception('Unexpected response format');
          }

          // Remove any potential truncation indicators from the API
          generatedText = generatedText
              .replaceAll("[INCOMPLETE]", "")
              .replaceAll("...", "");

          return generatedText;
        } catch (e) {
          debugPrint('Error decoding JSON: $e');

          // If we can't parse JSON but have text, just use the text directly
          if (response.body.isNotEmpty) {
            return response.body;
          }
          throw Exception('Failed to parse response: $e');
        }
      } else if (response.statusCode == 503) {
        // Model is loading
        throw Exception(
            'Model is currently loading. Please try again in a moment.');
      } else {
        // Capture detailed error message
        var errorDetails = response.body;
        try {
          final errorJson = jsonDecode(response.body);
          if (errorJson is Map && errorJson.containsKey('error')) {
            errorDetails = errorJson['error'];
          }
        } catch (_) {}

        throw Exception(
            'API request failed: ${response.statusCode} - $errorDetails');
      }
    } catch (e) {
      debugPrint('Error in _makeHuggingFaceApiRequest: $e');
      throw Exception('Failed to generate text: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Gradient background - using more poetic colors
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.purple.shade50,
                  Colors.indigo.shade100,
                ],
              ),
            ),
          ),

          // Background pattern
          Opacity(
            opacity: 0.05,
            child: Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/pattern.png'),
                  repeat: ImageRepeat.repeat,
                ),
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // App bar
                SliverAppBar(
                  title: const Text(
                    'Your Poem',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  floating: true,
                  backgroundColor: Colors.white.withOpacity(0.9),
                  elevation: 0,
                  actions: [
                    if (_poem != null)
                      IconButton(
                        icon: const Icon(Icons.share),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text(
                                  'Share functionality to be implemented'))
                          );
                        },
                      ),
                  ],
                ),

                // Content
                SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _animation,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Image with animation
                          Hero(
                            tag: 'poem_image',
                            child: _buildImageWidget(),
                          ),
                          const SizedBox(height: 24),

                          // Content (loading, error, or poem)
                          if (_isLoading) ...[
                            _buildLoadingDisplay(),
                          ] else
                            if (_error != null) ...[
                              _buildErrorDisplay(),
                            ] else
                              if (_poem != null) ...[
                                _buildPoemDisplay(),
                              ] else
                                ...[
                                  const Text('No poem available',
                                      style: TextStyle(
                                          fontSize: 16, color: Colors.grey)),
                                ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWidget() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.white,
              width: 4,
            ),
          ),
          child: _getImageWidget(),
        ),
      ),
    );
  }

  Widget _buildLoadingDisplay() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              SizedBox(
                height: 60,
                width: 60,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.purple.shade400),
                  backgroundColor: Colors.grey.shade200,
                  strokeWidth: 4,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _progressStatus,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.purple.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Crafting poetic verses just for you...",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPoemDisplay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity, // Ensure the container takes full width
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Inspired by "${widget.caption}"',
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Colors.purple.shade700,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _poem!,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.8,
                  // Increased line height for poetry
                  letterSpacing: 0.5,
                  // Increased letter spacing for poetic feel
                  fontFamily: 'Georgia', // More poetic font
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Listen button
            Expanded(
              child: ElevatedButton.icon(
                icon: Icon(_isSpeaking ? Icons.stop : Icons.volume_up),
                label: Text(_isSpeaking ? 'Stop' : 'Listen'),
                onPressed: () {
                  if (_isSpeaking) {
                    _stopSpeaking();
                  } else {
                    _startSpeaking();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isSpeaking ? Colors.red.shade400 : Colors
                      .purple.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Generate new poem button
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Generate New Poem'),
                onPressed: _startGeneratingPoem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorDisplay() {
    return Column(
      children: [
        const Icon(
          Icons.error_outline,
          size: 48,
          color: Colors.red,
        ),
        const SizedBox(height: 16),
        Text(
          'Oops! Something went wrong.',
          style: TextStyle(
            fontSize: 18,
            color: Colors.red.shade700,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? 'An unknown error occurred.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: Colors.red.shade600,
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _startGeneratingPoem,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade400,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Try Again'),
        ),
      ],
    );
  }

  Widget _getImageWidget() {
    if (widget.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) =>
        const Center(
          child: CircularProgressIndicator(),
        ),
        errorWidget: (context, url, error) => const Icon(Icons.error),
      );
    } else if (widget.imageFile != null) {
      return Image.file(
        widget.imageFile!,
        fit: BoxFit.cover,
      );
    } else if (widget.base64Image != null) {
      return Image.memory(
        base64Decode(widget.base64Image!),
        fit: BoxFit.cover,
      );
    } else {
      return const Center(
        child: Icon(Icons.image, size: 100, color: Colors.grey),
      );
    }
  }
}