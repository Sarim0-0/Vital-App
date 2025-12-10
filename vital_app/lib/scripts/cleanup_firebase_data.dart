import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// WARNING: This script will DELETE ALL data from:
/// - clinicians collection
/// - patients collection  
/// - prescription_requests collection
/// 
/// Run this script with: dart run lib/scripts/cleanup_firebase_data.dart
/// Make sure you're authenticated as an admin user

Future<void> main() async {
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  print('⚠️  WARNING: This will delete ALL clinicians, patients, and prescription requests!');
  print('Press Ctrl+C to cancel, or wait 5 seconds to continue...');
  
  await Future.delayed(const Duration(seconds: 5));
  
  try {
    print('\n🔐 Checking authentication...');
    final user = auth.currentUser;
    if (user == null) {
      print('❌ No user logged in. Please authenticate first.');
      return;
    }
    print('✅ Authenticated as: ${user.email}');

    print('\n🗑️  Starting cleanup...\n');

    // Delete all prescription requests
    print('Deleting prescription requests...');
    final requestsSnapshot = await firestore.collection('prescription_requests').get();
    int requestCount = 0;
    for (var doc in requestsSnapshot.docs) {
      await doc.reference.delete();
      requestCount++;
    }
    print('✅ Deleted $requestCount prescription requests');

    // Delete all clinicians and their subcollections
    print('\nDeleting clinicians...');
    final cliniciansSnapshot = await firestore.collection('clinicians').get();
    int clinicianCount = 0;
    for (var clinicianDoc in cliniciansSnapshot.docs) {
      // Delete prescriptions subcollection
      final prescriptionsSnapshot = await clinicianDoc.reference
          .collection('prescriptions')
          .get();
      for (var prescriptionDoc in prescriptionsSnapshot.docs) {
        await prescriptionDoc.reference.delete();
      }

      // Delete documents subcollection
      final documentsSnapshot = await clinicianDoc.reference
          .collection('documents')
          .get();
      for (var documentDoc in documentsSnapshot.docs) {
        await documentDoc.reference.delete();
      }

      // Delete clinician document
      await clinicianDoc.reference.delete();
      clinicianCount++;
    }
    print('✅ Deleted $clinicianCount clinicians');

    // Delete all patients and their subcollections
    print('\nDeleting patients...');
    final patientsSnapshot = await firestore.collection('patients').get();
    int patientCount = 0;
    for (var patientDoc in patientsSnapshot.docs) {
      // Delete all subcollections
      final subcollections = [
        'prescriptions',
        'active_medications',
        'medication_checkins',
        'daily_tracking',
        'appointment_attendance',
        'medical_documents',
      ];

      for (var subcollection in subcollections) {
        final subSnapshot = await patientDoc.reference
            .collection(subcollection)
            .get();
        
        for (var subDoc in subSnapshot.docs) {
          // Handle nested subcollections (e.g., medication_checkins/{dateKey}/checkins)
          if (subcollection == 'medication_checkins') {
            final checkinsSnapshot = await subDoc.reference
                .collection('checkins')
                .get();
            for (var checkinDoc in checkinsSnapshot.docs) {
              await checkinDoc.reference.delete();
            }
          }
          await subDoc.reference.delete();
        }
      }

      // Delete patient document
      await patientDoc.reference.delete();
      patientCount++;
    }
    print('✅ Deleted $patientCount patients');

    print('\n✨ Cleanup completed successfully!');
    print('Total deleted:');
    print('  - $requestCount prescription requests');
    print('  - $clinicianCount clinicians');
    print('  - $patientCount patients');

  } catch (e) {
    print('\n❌ Error during cleanup: $e');
    print('Some data may have been partially deleted.');
  }
}

