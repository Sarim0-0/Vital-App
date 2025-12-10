import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PrescriptionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Search clinicians by name (prefix matching)
  Future<List<Map<String, dynamic>>> searchClinicians(String query) async {
    if (query.isEmpty) {
      // Return all clinicians if query is empty
      final snapshot = await _firestore
          .collection('clinicians')
          .orderBy('name')
          .limit(20)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? '',
          'email': data['email'] ?? '',
        };
      }).toList();
    }

    // Prefix search: convert query to lowercase for case-insensitive search
    final queryLower = query.toLowerCase();
    final queryUpper =
        queryLower.substring(0, queryLower.length - 1) +
        String.fromCharCode(queryLower.codeUnitAt(queryLower.length - 1) + 1);

    final snapshot = await _firestore
        .collection('clinicians')
        .orderBy('name')
        .startAt([queryLower])
        .endAt([queryUpper])
        .limit(20)
        .get();

    // Client-side fuzzy filtering for better results
    final results = snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': data['name'] ?? '',
        'email': data['email'] ?? '',
      };
    }).toList();

    // Fuzzy match: check if query appears anywhere in the name
    return results.where((clinician) {
      final name = (clinician['name'] as String).toLowerCase();
      return name.contains(queryLower);
    }).toList();
  }

  // Create a prescription request
  Future<void> createRequest({
    required String patientId,
    required String patientName,
    required String patientEmail,
    required String clinicianId,
    required String clinicianName,
    String? message,
    String infoType = 'basic', // 'basic' or 'extensive'
    List<String>? chronicConditions,
    List<String>? allergies,
    List<String>? medications,
  }) async {
    final requestData = <String, dynamic>{
      'patientId': patientId,
      'patientName': patientName,
      'patientEmail': patientEmail,
      'clinicianId': clinicianId,
      'clinicianName': clinicianName,
      'message': message ?? '',
      'infoType': infoType,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Add extensive info if provided
    if (infoType == 'extensive') {
      if (chronicConditions != null && chronicConditions.isNotEmpty) {
        requestData['chronicConditions'] = chronicConditions;
      }
      if (allergies != null && allergies.isNotEmpty) {
        requestData['allergies'] = allergies;
      }
      if (medications != null && medications.isNotEmpty) {
        requestData['medications'] = medications;
      }
    }

    await _firestore.collection('prescription_requests').add(requestData);
  }

  // Get all requests for a clinician
  // Note: We don't use orderBy here to avoid requiring a composite index
  // Results will be sorted client-side instead
  Stream<QuerySnapshot> getRequestsForClinician(String clinicianId) {
    return _firestore
        .collection('prescription_requests')
        .where('clinicianId', isEqualTo: clinicianId)
        .snapshots();
  }

  // Get all requests for a patient
  Stream<QuerySnapshot> getRequestsForPatient(String patientId) {
    return _firestore
        .collection('prescription_requests')
        .where('patientId', isEqualTo: patientId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Update request status
  Future<void> updateRequestStatus({
    required String requestId,
    required String status, // 'approved' or 'rejected'
  }) async {
    await _firestore.collection('prescription_requests').doc(requestId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Create a prescription
  Future<void> createPrescription({
    required String requestId,
    required String patientId,
    required String patientName,
    required String patientEmail,
    required String clinicianId,
    required String clinicianName,
    required List<String> recommendedFoods,
    required List<String> recommendedExercises,
    required List<Map<String, dynamic>> medicines,
    required List<Map<String, dynamic>> appointments,
  }) async {
    final prescriptionData = <String, dynamic>{
      'requestId': requestId,
      'patientId': patientId,
      'patientName': patientName,
      'patientEmail': patientEmail,
      'clinicianId': clinicianId,
      'clinicianName': clinicianName,
      'recommendedFoods': recommendedFoods,
      'recommendedExercises': recommendedExercises,
      'medicines': medicines,
      'appointments': appointments,
      'createdAt': FieldValue.serverTimestamp(),
    };

    // Store prescription in clinician's log
    await _firestore
        .collection('clinicians')
        .doc(clinicianId)
        .collection('prescriptions')
        .add(prescriptionData);

    // Store prescription for patient (marked as pending approval)
    final patientPrescriptionData = Map<String, dynamic>.from(prescriptionData);
    patientPrescriptionData['approved'] = false; // Patient needs to approve
    patientPrescriptionData['rejected'] = false;
    
    await _firestore
        .collection('patients')
        .doc(patientId)
        .collection('prescriptions')
        .add(patientPrescriptionData);

    // Update request status to approved
    await updateRequestStatus(requestId: requestId, status: 'approved');
  }

  // Get prescriptions for a clinician (log view)
  Stream<QuerySnapshot> getPrescriptionsForClinician(String clinicianId) {
    return _firestore
        .collection('clinicians')
        .doc(clinicianId)
        .collection('prescriptions')
        .snapshots();
  }

  // Get prescriptions for a patient
  Stream<QuerySnapshot> getPrescriptionsForPatient(String patientId) {
    return _firestore
        .collection('patients')
        .doc(patientId)
        .collection('prescriptions')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Approve prescription (patient action)
  Future<void> approvePrescription(String prescriptionId) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('prescriptions')
        .doc(prescriptionId)
        .update({
      'approved': true,
      'approvedAt': FieldValue.serverTimestamp(),
    });
  }

  // Reject prescription (patient action)
  Future<void> rejectPrescription(String prescriptionId) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('prescriptions')
        .doc(prescriptionId)
        .update({
      'approved': false,
      'rejected': true,
      'rejectedAt': FieldValue.serverTimestamp(),
    });
  }

  // Get current user
  User? get currentUser => _auth.currentUser;
}
