import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'login_screen.dart'; //

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late User? _currentUser;
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    try {
      _currentUser = FirebaseAuth.instance.currentUser;

      if (_currentUser != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .get();

        setState(() {
          _userProfile = userDoc.data() as Map<String, dynamic>?;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching user profile: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false, // Removes the back button
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Profile',
          style: TextStyle(
            color: Color(0xFF673AB7),
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(
        child: CircularProgressIndicator(
          color: Color(0xFF673AB7),
        ),
      )
          : _currentUser == null
          ? Center(
        child: Text(
          'No user logged in',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 18,
          ),
        ),
      )
          : SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildProfileHeader(),
              SizedBox(height: 32),
              _buildProfileDetails(),
              SizedBox(height: 32),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0xFF673AB7).withOpacity(0.2),
                spreadRadius: 2,
                blurRadius: 15,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 70,
            backgroundColor: Color(0xFF673AB7).withOpacity(0.1),
            backgroundImage: _currentUser!.photoURL != null
                ? NetworkImage(_currentUser!.photoURL!)
                : null,
            child: _currentUser!.photoURL == null
                ? Icon(
              Icons.person,
              size: 70,
              color: Color(0xFF673AB7),
            )
                : null,
          ),
        ).animate().fadeIn(duration: 600.ms).scale(),
        SizedBox(height: 20),
        Text(
          _currentUser!.displayName ?? 'User',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF673AB7),
            letterSpacing: -0.5,
          ),
        ).animate().fadeIn(delay: 200.ms),
        SizedBox(height: 8),
        Text(
          _currentUser!.email ?? 'No email',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
            fontWeight: FontWeight.w300,
          ),
        ).animate().fadeIn(delay: 300.ms),
      ],
    );
  }

  Widget _buildProfileDetails() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          _buildDetailRow(
            icon: Icons.person_outline,
            label: 'Username',
            value: _userProfile?['username'] ?? 'Not set',
          ),
          _buildDivider(),
          _buildDetailRow(
            icon: Icons.calendar_today,
            label: 'Joined Date',
            value: _userProfile?['joinedDate'] != null
                ? _formatTimestamp(_userProfile!['joinedDate'])
                : 'Unknown',
          ),
          _buildDivider(),
          _buildDetailRow(
            icon: Icons.login,
            label: 'Last Login',
            value: _currentUser!.metadata.lastSignInTime != null
                ? _formatDateTime(_currentUser!.metadata.lastSignInTime!)
                : 'Unknown',
          ),
          _buildDivider(),
          _buildDetailRow(
            icon: Icons.date_range,
            label: 'Account Created',
            value: _formatDateTime(_currentUser!.metadata.creationTime!),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms);
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            icon,
            color: Color(0xFF673AB7).withOpacity(0.7),
            size: 24,
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      color: Colors.grey.withOpacity(0.2),
      indent: 16,
      endIndent: 16,
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 150, // Set a fixed width for the button
          child: ElevatedButton(
            onPressed: _logout,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10), // Reduced padding
              textStyle: TextStyle(
                fontSize: 14, // Smaller font size
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 3,
            ),
            child: Text('Logout'),
          ).animate().fadeIn(delay: 600.ms).scale(),
        ),
      ],
    );
  }

  void _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      // Replace the navigation method with a more direct approach
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error logging out: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatTimestamp(Timestamp timestamp) {
    return _formatDateTime(timestamp.toDate());
  }

  String _formatDateTime(DateTime dateTime) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year}';
  }
}