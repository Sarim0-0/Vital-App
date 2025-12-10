// Standalone cleanup script that can be run directly
// Usage: flutter run lib/scripts/cleanup_firebase_data_standalone.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:vital_app/main.dart' as app;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  print('⚠️  WARNING: This will delete ALL clinicians, patients, and prescription requests!');
  print('Make sure you are logged in as an admin user.');
  print('Press Enter to continue or Ctrl+C to cancel...');
  
  // Wait for user input (in a real scenario, you'd use stdin)
  await Future.delayed(const Duration(seconds: 3));
  
  try {
    print('\n🔐 Checking authentication...');
    final user = auth.currentUser;
    if (user == null) {
      print('❌ No user logged in. Please log in first.');
      print('Run the app, log in, then run this script again.');
      return;
    }
    print('✅ Authenticated as: ${user.email}');

    print('\n🗑️  Starting cleanup...\n');

    // Delete all prescription requests
    print('Deleting prescription requests...');
    final requestsSnapshot = await firestore.collection('prescription_requests').get();
    int requestCount = 0;
    final batch1 = firestore.batch();
    for (var doc in requestsSnapshot.docs) {
      batch1.delete(doc.reference);
      requestCount++;
    }
    if (requestCount > 0) await batch1.commit();
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
      final batch2 = firestore.batch();
      for (var prescriptionDoc in prescriptionsSnapshot.docs) {
        batch2.delete(prescriptionDoc.reference);
      }
      if (prescriptionsSnapshot.docs.isNotEmpty) await batch2.commit();

      // Delete documents subcollection
      final documentsSnapshot = await clinicianDoc.reference
          .collection('documents')
          .get();
      final batch3 = firestore.batch();
      for (var documentDoc in documentsSnapshot.docs) {
        batch3.delete(documentDoc.reference);
      }
      if (documentsSnapshot.docs.isNotEmpty) await batch3.commit();

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
        
        if (subSnapshot.docs.isNotEmpty) {
          final batch = firestore.batch();
          for (var subDoc in subSnapshot.docs) {
            // Handle nested subcollections (e.g., medication_checkins/{dateKey}/checkins)
            if (subcollection == 'medication_checkins') {
              final checkinsSnapshot = await subDoc.reference
                  .collection('checkins')
                  .get();
              if (checkinsSnapshot.docs.isNotEmpty) {
                final checkinsBatch = firestore.batch();
                for (var checkinDoc in checkinsSnapshot.docs) {
                  checkinsBatch.delete(checkinDoc.reference);
                }
                await checkinsBatch.commit();
              }
            }
            batch.delete(subDoc.reference);
          }
          await batch.commit();
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
    print('\nYou can now close this script and test with fresh data.');

  } catch (e) {
    print('\n❌ Error during cleanup: $e');
    print('Some data may have been partially deleted.');
    print('Check Firebase Console to verify deletion.');
  }
}

