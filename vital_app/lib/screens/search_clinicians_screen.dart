import 'package:flutter/material.dart';
import '../services/prescription_service.dart';
import '../services/auth_service.dart';

class SearchCliniciansScreen extends StatefulWidget {
  const SearchCliniciansScreen({super.key});

  @override
  State<SearchCliniciansScreen> createState() => _SearchCliniciansScreenState();
}

class _SearchCliniciansScreenState extends State<SearchCliniciansScreen> {
  final _prescriptionService = PrescriptionService();
  final _authService = AuthService();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _clinicians = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadAllClinicians();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _loadAllClinicians();
    } else {
      _searchClinicians(query);
    }
  }

  Future<void> _loadAllClinicians() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final clinicians = await _prescriptionService.searchClinicians('');
      setState(() {
        _clinicians = clinicians;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _searchClinicians(String query) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final clinicians = await _prescriptionService.searchClinicians(query);
      setState(() {
        _clinicians = clinicians;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _sendRequest(Map<String, dynamic> clinician) async {
    final user = _authService.currentUser;
    if (user == null) return;

    // Get patient profile
    final patientProfile = await _authService.getUserProfile(
      user.uid,
      'patient',
    );
    if (patientProfile == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Patient profile not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;

    // Show dialog for info type selection and optional message
    String selectedInfoType = 'basic';
    final messageController = TextEditingController();
    final confirmed = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Request Prescription from ${clinician['name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select information to share:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // ignore: deprecated_member_use
                RadioListTile<String>(
                  title: const Text('Basic Info'),
                  subtitle: const Text('Name, age, email only'),
                  value: 'basic',
                  // ignore: deprecated_member_use
                  groupValue: selectedInfoType,
                  // ignore: deprecated_member_use
                  onChanged: (value) {
                    setDialogState(() {
                      selectedInfoType = value!;
                    });
                  },
                ),
                // ignore: deprecated_member_use
                RadioListTile<String>(
                  title: const Text('Extensive Info'),
                  subtitle: const Text('Includes conditions, allergies, medications'),
                  value: 'extensive',
                  // ignore: deprecated_member_use
                  groupValue: selectedInfoType,
                  // ignore: deprecated_member_use
                  onChanged: (value) {
                    setDialogState(() {
                      selectedInfoType = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: messageController,
                  decoration: const InputDecoration(
                    labelText: 'Message (optional)',
                    hintText: 'Add any additional information...',
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop({
                'confirmed': true,
                'infoType': selectedInfoType,
                'message': messageController.text.trim(),
              }),
              child: const Text('Send Request'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == null || confirmed['confirmed'] != true || !mounted) return;

    try {
      // Get extensive info if selected
      List<String>? chronicConditions;
      List<String>? allergies;
      List<String>? medications;

      if (confirmed['infoType'] == 'extensive') {
        if (patientProfile['chronicConditions'] != null) {
          if (patientProfile['chronicConditions'] is List) {
            chronicConditions = List<String>.from(patientProfile['chronicConditions']);
          }
        }
        if (patientProfile['allergies'] != null) {
          if (patientProfile['allergies'] is List) {
            allergies = List<String>.from(patientProfile['allergies']);
          }
        }
        if (patientProfile['medications'] != null) {
          if (patientProfile['medications'] is List) {
            medications = List<String>.from(patientProfile['medications']);
          }
        }
      }

      await _prescriptionService.createRequest(
        patientId: user.uid,
        patientName: patientProfile['name'] ?? 'Unknown',
        patientEmail: patientProfile['email'] ?? user.email ?? '',
        clinicianId: clinician['id'],
        clinicianName: clinician['name'],
        message: confirmed['message'].toString().isEmpty
            ? null
            : confirmed['message'].toString(),
        infoType: confirmed['infoType'] as String,
        chronicConditions: chronicConditions,
        allergies: allergies,
        medications: medications,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request sent to ${clinician['name']}'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending request: $e'),
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
        title: const Text('Search Clinicians'),
        backgroundColor: Colors.green,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by clinician name...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _clinicians.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isEmpty
                              ? 'No clinicians found'
                              : 'No clinicians match your search',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _clinicians.length,
                    itemBuilder: (context, index) {
                      final clinician = _clinicians[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green,
                            child: Text(
                              (clinician['name'] as String)[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            clinician['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(clinician['email']),
                          trailing: ElevatedButton(
                            onPressed: () => _sendRequest(clinician),
                            child: const Text('Request'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
