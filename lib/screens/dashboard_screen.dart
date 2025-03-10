import 'package:flutter/material.dart';
import 'package:convex_bottom_bar/convex_bottom_bar.dart';
import 'package:card_swiper/card_swiper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import 'upload_screen.dart';
import 'gallery_screen.dart';
import 'capture_screen.dart';
import 'profile_screen.dart'; // Updated import for the new profile screen

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  final PageController _pageController = PageController(initialPage: 0);

  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      HomeView(),
      AnalyticsView(),
      ProfileScreen(), // Direct use of UserProfileScreen
    ];
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PixSense', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: _pages,
      ),
      bottomNavigationBar: ConvexAppBar(
        items: [
          TabItem(icon: Icons.home, title: 'Home'),
          TabItem(icon: Icons.analytics, title: 'Analytics'),
          TabItem(icon: Icons.person, title: 'Profile'),
        ],
        initialActiveIndex: _currentIndex,
        onTap: (int index) {
          _pageController.jumpToPage(index);
        },
      ),
    );
  }
}

// Rest of the code remains the same as in your original dashboard_screen.dart
class HomeView extends StatelessWidget {
  final List<String> cardImages = [
    'assets/images/image1.jpg',
    'assets/images/image2.jpg',
    'assets/images/image3.jpg',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(
            height: 250,
            child: Swiper(
              itemBuilder: (BuildContext context, int index) {
                return Image.asset(
                  cardImages[index],
                  fit: BoxFit.cover,
                );
              },
              itemCount: cardImages.length,
              pagination: const SwiperPagination(),
              control: const SwiperControl(),
              autoplay: true,
            ),
          ),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            children: [
              _buildGridItem(Icons.upload, 'Upload', context),
              _buildGridItem(Icons.camera, 'Capture', context),
              _buildGridItem(Icons.image, 'Gallery', context),
              _buildGridItem(Icons.settings, 'Settings', context),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem(IconData icon, String label, BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (label == 'Upload') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => UploadScreen()),
          );
        } else if (label == 'Gallery') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => GalleryScreen()),
          );
        } else if (label == 'Capture') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => CaptureScreen()),
          );
        } else if (label == 'Settings') {
          // Add settings screen navigation when implemented
        }
      },
      child: Card(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: Colors.blue),
            Text(label, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class AnalyticsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Analytics Coming Soon'));
  }
}