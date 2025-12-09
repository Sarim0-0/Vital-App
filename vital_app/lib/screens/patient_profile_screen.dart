import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/patient_migration_service.dart';
import 'chat_screen.dart';
import 'user_type_selection_screen.dart';
import 'search_clinicians_screen.dart';
import 'complete_profile_screen.dart';
import 'health_metrics_screen.dart';
import 'food_tracking_screen.dart';
import 'exercise_tracking_screen.dart';

class PatientProfileScreen extends StatefulWidget {
  const PatientProfileScreen({super.key});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  final _authService = AuthService();
  final _migrationService = PatientMigrationService();
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = _authService.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No user logged in';
        _isLoading = false;
      });
      return;
    }

    try {
      // Check if patient needs migration
      final needsMigration = await _migrationService
          .currentPatientNeedsMigration();
      if (needsMigration) {
        // Migrate the patient profile
        await _migrationService.migrateCurrentPatient();
      }

      if (!mounted) return;
      final profile = await _authService.getUserProfile(user.uid, 'patient');
      if (!mounted) return;
      setState(() {
        _userProfile = profile;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSignOut() async {
    try {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const UserTypeSelectionScreen(),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Profile'),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleSignOut,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red[700], fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _loadUserProfile,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : _userProfile == null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No profile data found',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    // Profile Icon
                    Center(
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.green,
                        child: Text(
                          _userProfile!['name']?[0].toUpperCase() ?? 'P',
                          style: const TextStyle(
                            fontSize: 48,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Profile Card
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  color: Colors.green,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Patient Information',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Name
                            _buildProfileItem(
                              context,
                              icon: Icons.person,
                              label: 'Name',
                              value: _userProfile!['name'] ?? 'Not set',
                            ),
                            const SizedBox(height: 20),

                            // Age
                            _buildProfileItem(
                              context,
                              icon: Icons.calendar_today,
                              label: 'Age',
                              value:
                                  _userProfile!['age']?.toString() ?? 'Not set',
                            ),
                            const SizedBox(height: 20),

                            // Email
                            _buildProfileItem(
                              context,
                              icon: Icons.email,
                              label: 'Email',
                              value:
                                  _userProfile!['email'] ??
                                  _authService.currentUser?.email ??
                                  'Not set',
                            ),
                            const SizedBox(height: 20),

                            // User Type
                            _buildProfileItem(
                              context,
                              icon: Icons.badge,
                              label: 'User Type',
                              value: 'Patient',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Profile Completion Status
                    if (_userProfile!['profiled'] != true)
                      Card(
                        color: Colors.orange.withValues(alpha: 0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.orange[700],
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Complete Your Profile',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange[700],
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Complete your health profile to unlock the chatbot feature and get personalized health recommendations.',
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const CompleteProfileScreen(),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Complete Profile Now'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_userProfile!['profiled'] != true)
                      const SizedBox(height: 16),

                    // Chat Button (only if profiled)
                    ElevatedButton.icon(
                      onPressed: _userProfile!['profiled'] == true
                          ? () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const ChatScreen(),
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.chat),
                      label: Text(
                        _userProfile!['profiled'] == true
                            ? 'Open Chat'
                            : 'Complete Profile to Use Chat',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        backgroundColor: _userProfile!['profiled'] == true
                            ? Colors.green
                            : Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Edit Profile Button
                    ElevatedButton.icon(
                      onPressed: () async {
                        // Reload profile to get latest data
                        await _loadUserProfile();
                        if (!mounted) return;
                        final profile = _userProfile;
                        if (profile != null) {
                          if (!mounted) return;
                          // ignore: use_build_context_synchronously
                          Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (context) => CompleteProfileScreen(
                                    existingProfile: profile,
                                  ),
                                ),
                              )
                              .then((_) {
                                // Reload profile after editing
                                if (mounted) {
                                  _loadUserProfile();
                                }
                              });
                        }
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text(
                        'Edit Profile',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Health Metrics Button
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const HealthMetricsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.favorite),
                      label: const Text(
                        'Health Metrics',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Food Tracking Button
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const FoodTrackingScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.restaurant),
                      label: const Text(
                        'Food Tracking',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Exercise Tracking Button
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ExerciseTrackingScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.fitness_center),
                      label: const Text(
                        'Exercise Tracking',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Request Prescription Button
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const SearchCliniciansScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.medical_services),
                      label: const Text(
                        'Request Prescription',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sign Out Button
                    OutlinedButton(
                      onPressed: _handleSignOut,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Sign Out',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildProfileItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.green, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
