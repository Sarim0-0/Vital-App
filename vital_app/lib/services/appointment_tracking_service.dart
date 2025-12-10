import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'prescription_service.dart';

class AppointmentTrackingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PrescriptionService _prescriptionService = PrescriptionService();

  // Get all appointments from prescriptions
  Future<List<Map<String, dynamic>>> getAllAppointments() async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final snapshot = await _prescriptionService.getPrescriptionsForPatient(user.uid).first;
    final List<Map<String, dynamic>> allAppointments = [];

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final prescriptionId = doc.id;
      final appointments = List<Map<String, dynamic>>.from(data['appointments'] ?? []);

      for (var appointment in appointments) {
        final title = appointment['title'] as String? ?? 'Untitled';
        Timestamp? dateTimestamp;
        if (appointment['date'] is Timestamp) {
          dateTimestamp = appointment['date'] as Timestamp;
        }
        
        if (dateTimestamp != null) {
          allAppointments.add({
            'prescriptionId': prescriptionId,
            'appointmentId': '${prescriptionId}_${allAppointments.length}', // Unique ID
            'title': title,
            'date': dateTimestamp.toDate(),
            'clinicianName': data['clinicianName'] as String? ?? 'Unknown',
          });
        }
      }
    }

    // Sort by date
    allAppointments.sort((a, b) {
      final aDate = a['date'] as DateTime;
      final bDate = b['date'] as DateTime;
      return aDate.compareTo(bDate);
    });

    return allAppointments;
  }

  // Mark appointment as attended
  Future<void> markAppointmentAttended({
    required String prescriptionId,
    required String appointmentId,
    required DateTime appointmentDate,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final attendanceData = {
      'prescriptionId': prescriptionId,
      'appointmentId': appointmentId,
      'appointmentDate': Timestamp.fromDate(appointmentDate),
      'attended': true,
      'checkedAt': FieldValue.serverTimestamp(),
    };

    // Store in patients/{userId}/appointment_attendance/{appointmentId}
    await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('appointment_attendance')
        .doc(appointmentId)
        .set(attendanceData, SetOptions(merge: true));
  }

  // Check if appointment was attended
  Future<bool> isAppointmentAttended(String appointmentId) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final doc = await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('appointment_attendance')
        .doc(appointmentId)
        .get();

    if (!doc.exists) return false;
    return doc.data()?['attended'] == true;
  }

  // Get appointment status (upcoming/attended/missed)
  Future<List<Map<String, dynamic>>> getAppointmentsWithStatus() async {
    final appointments = await getAllAppointments();
    final today = DateTime.now();
    final List<Map<String, dynamic>> appointmentsWithStatus = [];

    for (var appointment in appointments) {
      final appointmentId = appointment['appointmentId'] as String;
      final appointmentDate = appointment['date'] as DateTime;
      final isAttended = await isAppointmentAttended(appointmentId);
      
      final isUpcoming = appointmentDate.isAfter(today);
      final isMissed = !isAttended && appointmentDate.isBefore(today) && 
                      !appointmentDate.isAtSameMomentAs(today.copyWith(hour: 0, minute: 0, second: 0, millisecond: 0));

      appointmentsWithStatus.add({
        ...appointment,
        'isAttended': isAttended,
        'isUpcoming': isUpcoming,
        'isMissed': isMissed,
        'status': isAttended 
            ? 'attended' 
            : isUpcoming 
                ? 'upcoming' 
                : 'missed',
      });
    }

    return appointmentsWithStatus;
  }

  // Get upcoming appointments
  Future<List<Map<String, dynamic>>> getUpcomingAppointments() async {
    final allAppointments = await getAppointmentsWithStatus();
    return allAppointments.where((appt) => appt['isUpcoming'] == true).toList();
  }

  // Get missed appointments
  Future<List<Map<String, dynamic>>> getMissedAppointments() async {
    final allAppointments = await getAppointmentsWithStatus();
    return allAppointments.where((appt) => appt['isMissed'] == true).toList();
  }

  // Get appointments for a specific date range
  Future<List<Map<String, dynamic>>> getAppointmentsForDateRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final allAppointments = await getAppointmentsWithStatus();
    return allAppointments.where((appt) {
      final apptDate = appt['date'] as DateTime;
      return (apptDate.isAfter(startDate) || apptDate.isAtSameMomentAs(startDate)) &&
             (apptDate.isBefore(endDate) || apptDate.isAtSameMomentAs(endDate));
    }).toList();
  }
}

