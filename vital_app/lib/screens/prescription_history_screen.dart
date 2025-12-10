import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/prescription_service.dart';

class PrescriptionHistoryScreen extends StatelessWidget {
  const PrescriptionHistoryScreen({super.key});

  String _formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  String _formatDateTime(DateTime date) {
    return DateFormat('MMM dd, yyyy • hh:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final prescriptionService = PrescriptionService();
    final user = prescriptionService.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Prescription History')),
        body: const Center(child: Text('No user logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prescription History'),
        backgroundColor: Colors.blue,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: prescriptionService.getPrescriptionsForClinician(user.uid),
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
                  Icon(Icons.history, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No prescription history yet',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          final prescriptions = snapshot.data!.docs;

          // Sort by createdAt (most recent first) client-side
          final sortedPrescriptions = List<QueryDocumentSnapshot>.from(prescriptions);
          sortedPrescriptions.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTimestamp = aData['createdAt'] as Timestamp?;
            final bTimestamp = bData['createdAt'] as Timestamp?;

            if (aTimestamp == null && bTimestamp == null) return 0;
            if (aTimestamp == null) return 1;
            if (bTimestamp == null) return -1;

            return bTimestamp.compareTo(aTimestamp); // Descending order
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedPrescriptions.length,
            itemBuilder: (context, index) {
              final prescription = sortedPrescriptions[index];
              final data = prescription.data() as Map<String, dynamic>;
              
              final patientName = data['patientName'] as String? ?? 'Unknown';
              final patientEmail = data['patientEmail'] as String? ?? '';
              final createdAt = data['createdAt'] as Timestamp?;
              final recommendedFoods = List<String>.from(data['recommendedFoods'] ?? []);
              final recommendedExercises = List<String>.from(data['recommendedExercises'] ?? []);
              final medicines = List<Map<String, dynamic>>.from(data['medicines'] ?? []);
              final appointments = List<Map<String, dynamic>>.from(data['appointments'] ?? []);

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 2,
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Text(
                      patientName[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(
                    patientName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(patientEmail),
                      if (createdAt != null)
                        Text(
                          _formatDateTime(createdAt.toDate()),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Recommended Foods
                          if (recommendedFoods.isNotEmpty) ...[
                            _buildSectionHeader('Recommended Foods', Icons.restaurant),
                            const SizedBox(height: 8),
                            ...recommendedFoods.map((food) => Padding(
                              padding: const EdgeInsets.only(left: 8, bottom: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(food)),
                                ],
                              ),
                            )),
                            const SizedBox(height: 16),
                          ],

                          // Recommended Exercises
                          if (recommendedExercises.isNotEmpty) ...[
                            _buildSectionHeader('Recommended Exercises', Icons.fitness_center),
                            const SizedBox(height: 8),
                            ...recommendedExercises.map((exercise) => Padding(
                              padding: const EdgeInsets.only(left: 8, bottom: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(exercise)),
                                ],
                              ),
                            )),
                            const SizedBox(height: 16),
                          ],

                          // Medicines
                          if (medicines.isNotEmpty) ...[
                            _buildSectionHeader('Medicines', Icons.medication),
                            const SizedBox(height: 8),
                            ...medicines.map((medicine) {
                              final name = medicine['name'] as String? ?? 'Unknown';
                              final duration = medicine['duration'] as int? ?? 0;
                              final timesPerDay = medicine['timesPerDay'] as int? ?? 0;
                              return Padding(
                                padding: const EdgeInsets.only(left: 8, bottom: 8),
                                child: Card(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Duration: $duration days • $timesPerDay times/day',
                                          style: TextStyle(
                                            color: Colors.grey[700],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 16),
                          ],

                          // Appointments
                          if (appointments.isNotEmpty) ...[
                            _buildSectionHeader('Appointments', Icons.calendar_today),
                            const SizedBox(height: 8),
                            ...appointments.map((appointment) {
                              final title = appointment['title'] as String? ?? 'Untitled';
                              Timestamp? dateTimestamp;
                              if (appointment['date'] is Timestamp) {
                                dateTimestamp = appointment['date'] as Timestamp;
                              }
                              return Padding(
                                padding: const EdgeInsets.only(left: 8, bottom: 8),
                                child: Card(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        if (dateTimestamp != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatDate(dateTimestamp.toDate()),
                                            style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
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

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
      ],
    );
  }
}

