import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class DailyTrackingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get date key in YYYY-MM-DD format
  String _getDateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  // Process approved prescription and create daily tracking documents
  Future<void> processApprovedPrescription({
    required String prescriptionId,
    required DateTime prescriptionDate,
    required List<Map<String, dynamic>> medicines,
    required List<Map<String, dynamic>> appointments,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final prescriptionDateOnly = DateTime(
      prescriptionDate.year,
      prescriptionDate.month,
      prescriptionDate.day,
    );

    // Collect all unique dates that need to be updated
    final Map<String, Map<String, dynamic>> dateDocuments = {};

    // Process each medicine
    for (var medicine in medicines) {
      final medicineName = medicine['name'] as String? ?? 'Unknown';
      final duration = medicine['duration'] as int? ?? 0;
      final timesPerDay = medicine['timesPerDay'] as int? ?? 0;

      if (duration <= 0 || timesPerDay <= 0) continue;

      // Create documents for each day of the medication duration
      for (int day = 0; day < duration; day++) {
        final currentDate = prescriptionDateOnly.add(Duration(days: day));
        final dateKey = _getDateKey(currentDate);

        // Initialize document data if not exists
        if (!dateDocuments.containsKey(dateKey)) {
          dateDocuments[dateKey] = {
            'date': Timestamp.fromDate(currentDate),
            'medications': <String, dynamic>{},
            'appointments': <String>[],
            'prescriptionIds': <String>[],
          };
        }

        final docData = dateDocuments[dateKey]!;
        final medications = docData['medications'] as Map<String, dynamic>;

        // Initialize medicine entry if it doesn't exist
        if (!medications.containsKey(medicineName)) {
          medications[medicineName] = <String, String>{};
        }

        final medicineEntries = medications[medicineName] as Map<String, String>;

        // Add time slots for this medicine (e.g., panadol_1, panadol_2, etc.)
        for (int timeIndex = 1; timeIndex <= timesPerDay; timeIndex++) {
          final timeKey = '${medicineName}_$timeIndex';
          // Only set if not already exists (to preserve existing status)
          if (!medicineEntries.containsKey(timeKey)) {
            medicineEntries[timeKey] = 'not_taken';
          }
        }

        // Add prescription ID if not already present
        final prescriptionIds = docData['prescriptionIds'] as List<String>;
        if (!prescriptionIds.contains(prescriptionId)) {
          prescriptionIds.add(prescriptionId);
        }
      }
    }

    // Process appointments
    for (var appointment in appointments) {
      final appointmentDate = (appointment['date'] as Timestamp).toDate();
      final appointmentDateOnly = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
      );
      final dateKey = _getDateKey(appointmentDateOnly);
      final appointmentTitle = appointment['title'] as String? ?? 'Appointment';

      // Initialize document data if not exists
      if (!dateDocuments.containsKey(dateKey)) {
        dateDocuments[dateKey] = {
          'date': Timestamp.fromDate(appointmentDateOnly),
          'medications': <String, dynamic>{},
          'appointments': <String>[],
          'prescriptionIds': <String>[],
        };
      }

      final docData = dateDocuments[dateKey]!;
      final appointmentsList = docData['appointments'] as List<String>;

      // Add appointment if not already exists
      if (!appointmentsList.contains(appointmentTitle)) {
        appointmentsList.add(appointmentTitle);
      }

      // Add prescription ID if not already present
      final prescriptionIds = docData['prescriptionIds'] as List<String>;
      if (!prescriptionIds.contains(prescriptionId)) {
        prescriptionIds.add(prescriptionId);
      }
    }

    // First, fetch all existing documents
    final Map<String, DocumentSnapshot> existingDocs = {};
    final List<Future<void>> fetchFutures = [];

    for (var dateKey in dateDocuments.keys) {
      final docRef = _firestore
          .collection('patients')
          .doc(user.uid)
          .collection('daily_tracking')
          .doc(dateKey);
      
      fetchFutures.add(docRef.get().then((doc) {
        existingDocs[dateKey] = doc;
      }));
    }

    // Wait for all fetches to complete
    await Future.wait(fetchFutures);

    // Now create batch and add all operations synchronously
    final batch = _firestore.batch();

    for (var entry in dateDocuments.entries) {
      final dateKey = entry.key;
      final newData = entry.value;
      final docRef = _firestore
          .collection('patients')
          .doc(user.uid)
          .collection('daily_tracking')
          .doc(dateKey);

      final existingDoc = existingDocs[dateKey];
      
      if (existingDoc != null && existingDoc.exists) {
        final existingData = existingDoc.data() as Map<String, dynamic>;
        
        // Merge medications
        final existingMedications = Map<String, dynamic>.from(
          existingData['medications'] ?? {},
        );
        final newMedications = newData['medications'] as Map<String, dynamic>;
        
        // Merge each medicine
        for (var medicineEntry in newMedications.entries) {
          if (existingMedications.containsKey(medicineEntry.key)) {
            // Merge time slots, preserving existing status
            final existingSlots = Map<String, String>.from(
              existingMedications[medicineEntry.key] as Map? ?? {},
            );
            final newSlots = medicineEntry.value as Map<String, String>;
            // Only add new slots, don't overwrite existing ones
            for (var slotEntry in newSlots.entries) {
              if (!existingSlots.containsKey(slotEntry.key)) {
                existingSlots[slotEntry.key] = slotEntry.value;
              }
            }
            existingMedications[medicineEntry.key] = existingSlots;
          } else {
            existingMedications[medicineEntry.key] = medicineEntry.value;
          }
        }

        // Merge appointments
        final existingAppointments = List<String>.from(
          existingData['appointments'] ?? [],
        );
        final newAppointments = newData['appointments'] as List<String>;
        for (var appt in newAppointments) {
          if (!existingAppointments.contains(appt)) {
            existingAppointments.add(appt);
          }
        }

        // Merge prescription IDs
        final existingPrescriptionIds = List<String>.from(
          existingData['prescriptionIds'] ?? [],
        );
        final newPrescriptionIds = newData['prescriptionIds'] as List<String>;
        for (var id in newPrescriptionIds) {
          if (!existingPrescriptionIds.contains(id)) {
            existingPrescriptionIds.add(id);
          }
        }

        batch.set(docRef, {
          'date': newData['date'],
          'medications': existingMedications,
          'appointments': existingAppointments,
          'prescriptionIds': existingPrescriptionIds,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        // New document
        batch.set(docRef, {
          ...newData,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    // Commit all changes
    await batch.commit();
  }

  // Get daily tracking for a specific date
  Future<Map<String, dynamic>?> getDailyTracking(DateTime date) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final dateKey = _getDateKey(date);
    final doc = await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('daily_tracking')
        .doc(dateKey)
        .get();

    if (!doc.exists) return null;

    final data = doc.data() as Map<String, dynamic>;
    return {
      'date': date,
      'medications': Map<String, dynamic>.from(data['medications'] ?? {}),
      'appointments': List<String>.from(data['appointments'] ?? []),
      'prescriptionIds': List<String>.from(data['prescriptionIds'] ?? []),
    };
  }

  // Stream of daily tracking for a specific date
  Stream<Map<String, dynamic>?> getDailyTrackingStream(DateTime date) {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final dateKey = _getDateKey(date);
    return _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('daily_tracking')
        .doc(dateKey)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;

      final data = doc.data() as Map<String, dynamic>;
      return {
        'date': date,
        'medications': Map<String, dynamic>.from(data['medications'] ?? {}),
        'appointments': List<String>.from(data['appointments'] ?? []),
        'prescriptionIds': List<String>.from(data['prescriptionIds'] ?? []),
      };
    });
  }

  // Update medication status for a specific time slot
  Future<void> updateMedicationStatus({
    required DateTime date,
    required String medicineName,
    required int timeIndex,
    required String status, // 'not_taken', 'checked', 'missed'
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final dateKey = _getDateKey(date);
    final timeKey = '${medicineName}_$timeIndex';

    await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('daily_tracking')
        .doc(dateKey)
        .update({
      'medications.$medicineName.$timeKey': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Mark appointment as attended
  Future<void> markAppointmentAttended({
    required DateTime date,
    required String appointmentTitle,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final dateKey = _getDateKey(date);
    final docRef = _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('daily_tracking')
        .doc(dateKey);

    final doc = await docRef.get();
    if (!doc.exists) return;

    final data = doc.data() as Map<String, dynamic>;
    final appointments = List<String>.from(data['appointments'] ?? []);

    // Store attended appointments separately
    final attendedAppointments = List<String>.from(
      data['attendedAppointments'] ?? [],
    );

    if (appointments.contains(appointmentTitle) &&
        !attendedAppointments.contains(appointmentTitle)) {
      attendedAppointments.add(appointmentTitle);
      await docRef.update({
        'attendedAppointments': attendedAppointments,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Get all dates with tracking data
  Stream<List<DateTime>> getTrackingDatesStream() {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    return _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('daily_tracking')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final date = (data['date'] as Timestamp).toDate();
        return date;
      }).toList();
    });
  }

  // Check and mark missed medications/appointments for past dates
  Future<void> checkAndMarkMissed(DateTime date) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final now = DateTime.now();
    final dateOnly = DateTime(date.year, date.month, date.day);
    final todayOnly = DateTime(now.year, now.month, now.day);

    // Only check past dates
    if (!dateOnly.isBefore(todayOnly)) return;

    final tracking = await getDailyTracking(date);
    if (tracking == null) return;

    final medications = tracking['medications'] as Map<String, dynamic>;
    bool hasChanges = false;
    final updates = <String, dynamic>{};

    // Check each medicine
    for (var medicineEntry in medications.entries) {
      final medicineName = medicineEntry.key;
      final timeSlots = medicineEntry.value as Map<String, dynamic>;

      for (var timeSlotEntry in timeSlots.entries) {
        final status = timeSlotEntry.value as String;
        if (status == 'not_taken') {
          updates['medications.$medicineName.${timeSlotEntry.key}'] = 'missed';
          hasChanges = true;
        }
      }
    }

    // Check appointments
    final appointments = tracking['appointments'] as List<String>;
    final attendedAppointments = List<String>.from(
      tracking['attendedAppointments'] ?? [],
    );

    for (var appointment in appointments) {
      if (!attendedAppointments.contains(appointment)) {
        // Mark as missed (we can add a missedAppointments field if needed)
        // For now, we'll just track attended ones
      }
    }

    if (hasChanges) {
      final dateKey = _getDateKey(date);
      await _firestore
          .collection('patients')
          .doc(user.uid)
          .collection('daily_tracking')
          .doc(dateKey)
          .update(updates);
    }
  }
}

