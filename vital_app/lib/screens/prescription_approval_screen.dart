import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/prescription_service.dart';
import '../services/daily_tracking_service.dart';
import '../services/auth_service.dart';

class PrescriptionApprovalScreen extends StatefulWidget {
  const PrescriptionApprovalScreen({super.key});

  @override
  State<PrescriptionApprovalScreen> createState() =>
      _PrescriptionApprovalScreenState();
}

class _PrescriptionApprovalScreenState
    extends State<PrescriptionApprovalScreen> {
  final _prescriptionService = PrescriptionService();
  final _dailyTrackingService = DailyTrackingService();
  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pending Prescriptions')),
        body: const Center(child: Text('No user logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Prescriptions'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _prescriptionService.getPrescriptionsForPatient(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No prescriptions found',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          final prescriptions = snapshot.data!.docs;
          final pendingPrescriptions = prescriptions.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['approved'] != true;
          }).toList();

          if (pendingPrescriptions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: Colors.green[400]),
                  const SizedBox(height: 16),
                  Text(
                    'All prescriptions approved!',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: pendingPrescriptions.length,
            itemBuilder: (context, index) {
              final prescription = pendingPrescriptions[index];
              final data = prescription.data() as Map<String, dynamic>;
              final clinicianName = data['clinicianName'] as String? ?? 'Unknown';
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
              final recommendedFoods = List<String>.from(data['recommendedFoods'] ?? []);
              final recommendedExercises = List<String>.from(data['recommendedExercises'] ?? []);
              final medicines = List<Map<String, dynamic>>.from(data['medicines'] ?? []);
              final appointments = List<Map<String, dynamic>>.from(data['appointments'] ?? []);

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: ExpansionTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.medical_information, color: Colors.orange),
                  ),
                  title: Text(
                    'Prescription from $clinicianName',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (createdAt != null)
                        Text(
                          'Date: ${DateFormat('MMM dd, yyyy').format(createdAt)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap to view details',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (recommendedFoods.isNotEmpty) ...[
                            _buildSectionHeader('Recommended Foods'),
                            Wrap(
                              spacing: 8.0,
                              runSpacing: 4.0,
                              children: recommendedFoods
                                  .map((food) => Chip(label: Text(food)))
                                  .toList(),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (recommendedExercises.isNotEmpty) ...[
                            _buildSectionHeader('Recommended Exercises'),
                            Wrap(
                              spacing: 8.0,
                              runSpacing: 4.0,
                              children: recommendedExercises
                                  .map((exercise) => Chip(label: Text(exercise)))
                                  .toList(),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (medicines.isNotEmpty) ...[
                            _buildSectionHeader('Medicines'),
                            ...medicines.map((med) {
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.medication, size: 20),
                                title: Text(med['name'] as String? ?? 'Unknown'),
                                subtitle: Text(
                                    '${med['duration']} days, ${med['timesPerDay']} times/day'),
                              );
                            }),
                            const SizedBox(height: 16),
                          ],
                          if (appointments.isNotEmpty) ...[
                            _buildSectionHeader('Appointments'),
                            ...appointments.map((appt) {
                              final apptDate = (appt['date'] as Timestamp).toDate();
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.event, size: 20),
                                title: Text(appt['title'] as String? ?? 'Appointment'),
                                subtitle: Text(DateFormat('MMM dd, yyyy').format(apptDate)),
                              );
                            }),
                            const SizedBox(height: 16),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _rejectPrescription(
                                  context,
                                  prescription.id,
                                ),
                                child: const Text('Reject'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => _approvePrescription(
                                  context,
                                  prescription.id,
                                  data,
                                  createdAt ?? DateTime.now(),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Approve'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.orange,
        ),
      ),
    );
  }

  Future<void> _approvePrescription(
    BuildContext context,
    String prescriptionId,
    Map<String, dynamic> prescriptionData,
    DateTime prescriptionDate,
  ) async {
    // Show loading dialog
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      debugPrint('Starting prescription approval...');
      debugPrint('Prescription ID: $prescriptionId');
      debugPrint('Prescription Date: $prescriptionDate');
      
      // Mark prescription as approved first
      debugPrint('Marking prescription as approved...');
      await _prescriptionService.approvePrescription(prescriptionId);
      debugPrint('Prescription marked as approved');

      // Process prescription and create daily tracking documents
      debugPrint('Processing prescription for daily tracking...');
      final medicines = List<Map<String, dynamic>>.from(prescriptionData['medicines'] ?? []);
      final appointments = List<Map<String, dynamic>>.from(prescriptionData['appointments'] ?? []);
      
      debugPrint('Medicines count: ${medicines.length}');
      debugPrint('Appointments count: ${appointments.length}');
      
      await _dailyTrackingService.processApprovedPrescription(
        prescriptionId: prescriptionId,
        prescriptionDate: prescriptionDate,
        medicines: medicines,
        appointments: appointments,
      );
      debugPrint('Daily tracking documents created');

      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prescription approved and added to your tracking!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error approving prescription: $e');
      debugPrint('Stack trace: $stackTrace');
      if (context.mounted) {
        // Make sure to close loading dialog even on error
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(); // Close loading dialog
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving prescription: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _rejectPrescription(
    BuildContext context,
    String prescriptionId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Prescription'),
        content: const Text(
          'Are you sure you want to reject this prescription? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _prescriptionService.rejectPrescription(prescriptionId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prescription rejected'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting prescription: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

