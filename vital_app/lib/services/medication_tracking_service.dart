import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'prescription_service.dart';

class MedicationTrackingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get today's date key (YYYY-MM-DD)
  String _getDateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  // Sync all existing prescriptions to denormalized collection (one-time migration)
  Future<void> syncAllExistingPrescriptions() async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    try {
      final prescriptionService = PrescriptionService();
      final snapshot = await prescriptionService.getPrescriptionsForPatient(user.uid).first;
      
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        await syncMedicationsFromPrescription(doc.id, data);
      }
    } catch (e) {
      // Silently fail - this is just for optimization
      debugPrint('Warning: Failed to sync existing prescriptions: $e');
    }
  }

  // Sync medications to denormalized collection for faster access
  Future<void> syncMedicationsFromPrescription(String prescriptionId, Map<String, dynamic> prescriptionData) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    // Handle both Timestamp and DateTime for createdAt
    DateTime createdAt;
    if (prescriptionData['createdAt'] is Timestamp) {
      createdAt = (prescriptionData['createdAt'] as Timestamp).toDate();
    } else if (prescriptionData['createdAt'] is DateTime) {
      createdAt = prescriptionData['createdAt'] as DateTime;
    } else {
      createdAt = DateTime.now();
    }

    final medicines = List<Map<String, dynamic>>.from(prescriptionData['medicines'] ?? []);
    final clinicianName = prescriptionData['clinicianName'] as String? ?? 'Unknown';

    if (medicines.isEmpty) {
      return; // No medicines to sync
    }

    final batch = _firestore.batch();
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    for (var medicine in medicines) {
      final name = medicine['name'] as String? ?? 'Unknown';
      final duration = medicine['duration'] as int? ?? 0;
      final timesPerDay = medicine['timesPerDay'] as int? ?? 0;
      
      if (duration <= 0 || timesPerDay <= 0) {
        continue; // Skip invalid medications
      }

      final endDate = createdAt.add(Duration(days: duration));
      final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);

      // Only sync if medication is still active (end date is today or in the future)
      if (endDateOnly.isAfter(todayOnly) || endDateOnly.isAtSameMomentAs(todayOnly)) {
        // Create unique ID using prescription ID and medicine name (sanitize name)
        final sanitizedName = name.replaceAll(' ', '_').replaceAll(RegExp(r'[^\w]'), '');
        final medicationId = '${prescriptionId}_$sanitizedName';
        final medicationRef = _firestore
            .collection('patients')
            .doc(user.uid)
            .collection('active_medications')
            .doc(medicationId);

        batch.set(medicationRef, {
          'prescriptionId': prescriptionId,
          'medicineName': name,
          'duration': duration,
          'timesPerDay': timesPerDay,
          'startDate': Timestamp.fromDate(createdAt),
          'endDate': Timestamp.fromDate(endDate),
          'clinicianName': clinicianName,
          'syncedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)); // Use merge to avoid overwriting if exists
      }
    }

    try {
      await batch.commit();
    } catch (e) {
      debugPrint('Error committing medication sync batch: $e');
      rethrow;
    }
  }

  // Get all active medications from denormalized collection (faster)
  // Falls back to prescriptions if denormalized collection is empty
  Future<List<Map<String, dynamic>>> getActiveMedications() async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    
    // Get all and filter client-side to avoid index requirement
    final snapshot = await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('active_medications')
        .get();

    final denormalized = snapshot.docs
        .map((doc) {
          final data = doc.data();
          final endDate = (data['endDate'] as Timestamp).toDate();
          final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
          // Filter active medications client-side
          if (endDateOnly.isAfter(todayOnly) || endDateOnly.isAtSameMomentAs(todayOnly)) {
            return {
              'prescriptionId': data['prescriptionId'],
              'medicineName': data['medicineName'],
              'duration': data['duration'],
              'timesPerDay': data['timesPerDay'],
              'startDate': (data['startDate'] as Timestamp).toDate(),
              'endDate': endDate,
              'clinicianName': data['clinicianName'],
            };
          }
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    // If denormalized collection is empty, sync from prescriptions (backward compatibility)
    if (denormalized.isEmpty) {
      try {
        await syncAllExistingPrescriptions();
        // Try again after sync
        final retrySnapshot = await _firestore
            .collection('patients')
            .doc(user.uid)
            .collection('active_medications')
            .get();
        
        final todayOnlyRetry = DateTime(today.year, today.month, today.day);
        return retrySnapshot.docs
            .map((doc) {
              final data = doc.data();
              final endDate = (data['endDate'] as Timestamp).toDate();
              final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
              if (endDateOnly.isAfter(todayOnlyRetry) || endDateOnly.isAtSameMomentAs(todayOnlyRetry)) {
                return {
                  'prescriptionId': data['prescriptionId'],
                  'medicineName': data['medicineName'],
                  'duration': data['duration'],
                  'timesPerDay': data['timesPerDay'],
                  'startDate': (data['startDate'] as Timestamp).toDate(),
                  'endDate': endDate,
                  'clinicianName': data['clinicianName'],
                };
              }
              return null;
            })
            .whereType<Map<String, dynamic>>()
            .toList();
      } catch (e) {
        debugPrint('Warning: Failed to sync prescriptions: $e');
      }
    }

    return denormalized;
  }

  // Stream of active medications for real-time updates
  Stream<List<Map<String, dynamic>>> getActiveMedicationsStream() {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final today = DateTime.now();
    // Get all and filter client-side to avoid index requirement
    return _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('active_medications')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) {
            final data = doc.data();
            final endDate = (data['endDate'] as Timestamp).toDate();
            // Filter active medications client-side
            if (today.isBefore(endDate) || today.isAtSameMomentAs(endDate)) {
              return {
                'prescriptionId': data['prescriptionId'],
                'medicineName': data['medicineName'],
                'duration': data['duration'],
                'timesPerDay': data['timesPerDay'],
                'startDate': (data['startDate'] as Timestamp).toDate(),
                'endDate': endDate,
                'clinicianName': data['clinicianName'],
              };
            }
            return null;
          })
          .whereType<Map<String, dynamic>>()
          .toList();
    });
  }

  // Mark medication as taken for a specific date and time
  Future<void> markMedicationTaken({
    required String prescriptionId,
    required String medicineName,
    required DateTime date,
    required int timeIndex, // 0-based index for which time of day (e.g., 0 = first time, 1 = second time)
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final dateKey = _getDateKey(date);
    final checkInData = {
      'prescriptionId': prescriptionId,
      'medicineName': medicineName,
      'date': dateKey,
      'timeIndex': timeIndex,
      'checkedAt': FieldValue.serverTimestamp(),
    };

    // Store in patients/{userId}/medication_checkins/{dateKey}/{checkInId}
    await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('medication_checkins')
        .doc(dateKey)
        .collection('checkins')
        .add(checkInData);
  }

  // Get medication check-ins for a specific date
  Future<List<Map<String, dynamic>>> getCheckInsForDate(DateTime date) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final dateKey = _getDateKey(date);
    final snapshot = await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('medication_checkins')
        .doc(dateKey)
        .collection('checkins')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'prescriptionId': data['prescriptionId'],
        'medicineName': data['medicineName'],
        'timeIndex': data['timeIndex'],
        'checkedAt': (data['checkedAt'] as Timestamp?)?.toDate(),
      };
    }).toList();
  }

  // Check if medication was taken for a specific date and time
  Future<bool> isMedicationTaken({
    required String prescriptionId,
    required String medicineName,
    required DateTime date,
    required int timeIndex,
  }) async {
    final checkIns = await getCheckInsForDate(date);
    return checkIns.any((checkIn) =>
        checkIn['prescriptionId'] == prescriptionId &&
        checkIn['medicineName'] == medicineName &&
        checkIn['timeIndex'] == timeIndex);
  }

  // Get medication status for a specific date (taken/missed/pending) - optimized
  Future<Map<String, dynamic>> getMedicationStatusForDate(DateTime date) async {
    // Load both in parallel for faster performance
    final results = await Future.wait([
      getActiveMedications(),
      getCheckInsForDate(date),
    ]);
    
    final activeMedications = results[0];
    final checkIns = results[1];
    final dateKey = _getDateKey(date);

    final List<Map<String, dynamic>> medicationsWithStatus = [];

    for (var medication in activeMedications) {
      final prescriptionId = medication['prescriptionId'] as String;
      final medicineName = medication['medicineName'] as String;
      final timesPerDay = medication['timesPerDay'] as int;
      final startDate = medication['startDate'] as DateTime;
      final endDate = medication['endDate'] as DateTime;

      // Check if medication should be active on this date
      final dateOnly = DateTime(date.year, date.month, date.day);
      final startDateOnly = DateTime(startDate.year, startDate.month, startDate.day);
      final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
      
      if (dateOnly.isBefore(startDateOnly) || dateOnly.isAfter(endDateOnly)) {
        continue; // Skip if not active on this date
      }

      final List<Map<String, dynamic>> timeSlots = [];
      for (int i = 0; i < timesPerDay; i++) {
        final isTaken = checkIns.any((checkIn) =>
            checkIn['prescriptionId'] == prescriptionId &&
            checkIn['medicineName'] == medicineName &&
            checkIn['timeIndex'] == i);

        // Check if missed: date is in the past and medication wasn't taken
        final now = DateTime.now();
        final dateOnly = DateTime(date.year, date.month, date.day);
        final todayOnly = DateTime(now.year, now.month, now.day);
        final isMissed = !isTaken && dateOnly.isBefore(todayOnly);

        timeSlots.add({
          'timeIndex': i,
          'isTaken': isTaken,
          'isMissed': isMissed,
        });
      }

      medicationsWithStatus.add({
        ...medication,
        'timeSlots': timeSlots,
        'allTaken': timeSlots.every((slot) => slot['isTaken'] == true),
        'hasMissed': timeSlots.any((slot) => slot['isMissed'] == true),
      });
    }

    return {
      'date': dateKey,
      'medications': medicationsWithStatus,
    };
  }

  // Get all missed medications (past dates where medication wasn't taken)
  Future<List<Map<String, dynamic>>> getMissedMedications() async {
    final today = DateTime.now();
    final List<Map<String, dynamic>> missed = [];

    // Check last 30 days for missed medications
    for (int i = 1; i <= 30; i++) {
      final checkDate = today.subtract(Duration(days: i));
      final status = await getMedicationStatusForDate(checkDate);

      for (var medication in status['medications'] as List) {
        if (medication['hasMissed'] == true) {
          final timeSlots = medication['timeSlots'] as List;
          final missedSlots = timeSlots.where((slot) => slot['isMissed'] == true).toList();
          
          for (var slot in missedSlots) {
            missed.add({
              'prescriptionId': medication['prescriptionId'],
              'medicineName': medication['medicineName'],
              'date': checkDate,
              'timeIndex': slot['timeIndex'],
              'timesPerDay': medication['timesPerDay'],
              'clinicianName': medication['clinicianName'],
            });
          }
        }
      }
    }

    return missed;
  }
}

