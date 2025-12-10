import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/prescription_service.dart';
import 'generate_prescription_screen.dart';

class PrescriptionRequestsScreen extends StatelessWidget {
  const PrescriptionRequestsScreen({super.key});

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} minutes ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<void> _updateStatus(
    BuildContext context,
    PrescriptionService prescriptionService,
    String requestId,
    String status,
  ) async {
    try {
      await prescriptionService.updateRequestStatus(
        requestId: requestId,
        status: status,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request $status'),
            backgroundColor: status == 'approved' ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prescriptionService = PrescriptionService();
    final user = prescriptionService.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Prescription Requests')),
        body: const Center(child: Text('No user logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prescription Requests'),
        backgroundColor: Colors.blue,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: prescriptionService.getRequestsForClinician(user.uid),
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
                  Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No prescription requests yet',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          final requests = snapshot.data!.docs;

          // Sort requests by createdAt (most recent first) client-side
          final sortedRequests = List<QueryDocumentSnapshot>.from(requests);
          sortedRequests.sort((a, b) {
            final aCreatedAt = a.data() as Map<String, dynamic>;
            final bCreatedAt = b.data() as Map<String, dynamic>;
            final aTimestamp = aCreatedAt['createdAt'] as Timestamp?;
            final bTimestamp = bCreatedAt['createdAt'] as Timestamp?;

            if (aTimestamp == null && bTimestamp == null) return 0;
            if (aTimestamp == null) return 1;
            if (bTimestamp == null) return -1;

            return bTimestamp.compareTo(aTimestamp); // Descending order
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedRequests.length,
            itemBuilder: (context, index) {
              final request = sortedRequests[index];
              final data = request.data() as Map<String, dynamic>;
              final status = data['status'] as String? ?? 'pending';
              final patientName = data['patientName'] as String? ?? 'Unknown';
              final patientEmail = data['patientEmail'] as String? ?? '';
              final message = data['message'] as String? ?? '';
              final createdAt = data['createdAt'] as Timestamp?;
              final infoType = data['infoType'] as String? ?? 'basic';
              final chronicConditions = data['chronicConditions'] as List<dynamic>?;
              final allergies = data['allergies'] as List<dynamic>?;
              final medications = data['medications'] as List<dynamic>?;

              Color statusColor;
              IconData statusIcon;
              switch (status) {
                case 'approved':
                  statusColor = Colors.green;
                  statusIcon = Icons.check_circle;
                  break;
                case 'rejected':
                  statusColor = Colors.red;
                  statusIcon = Icons.cancel;
                  break;
                default:
                  statusColor = Colors.orange;
                  statusIcon = Icons.pending;
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: Text(
                              patientName[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  patientName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                if (createdAt != null)
                                  Text(
                                    _formatDate(createdAt.toDate()),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Chip(
                            avatar: Icon(
                              statusIcon,
                              size: 16,
                              color: statusColor,
                            ),
                            label: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            backgroundColor: statusColor.withValues(alpha: 0.1),
                          ),
                        ],
                      ),
                      // Patient Info Section
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'Patient Information',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Email: $patientEmail'),
                      Text('Info Type: ${infoType.toUpperCase()}'),
                      if (infoType == 'extensive') ...[
                        const SizedBox(height: 8),
                        if (chronicConditions != null && chronicConditions.isNotEmpty) ...[
                          const Text(
                            'Chronic Conditions:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          ...chronicConditions.map((condition) => Text('• $condition')),
                          const SizedBox(height: 4),
                        ],
                        if (allergies != null && allergies.isNotEmpty) ...[
                          const Text(
                            'Allergies:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          ...allergies.map((allergy) => Text('• $allergy')),
                          const SizedBox(height: 4),
                        ],
                        if (medications != null && medications.isNotEmpty) ...[
                          const Text(
                            'Current Medications:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          ...medications.map((med) => Text('• $med')),
                        ],
                      ],
                      if (message.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'Message:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(message),
                      ],
                      if (status == 'pending') ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _updateStatus(
                                context,
                                prescriptionService,
                                request.id,
                                'rejected',
                              ),
                              child: const Text('Reject'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final result = await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => GeneratePrescriptionScreen(
                                      requestId: request.id,
                                      requestData: data,
                                    ),
                                  ),
                                );
                                if (result == true && context.mounted) {
                                  // Prescription was generated successfully
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Prescription generated successfully!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.medical_services),
                              label: const Text('Generate Prescription'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
