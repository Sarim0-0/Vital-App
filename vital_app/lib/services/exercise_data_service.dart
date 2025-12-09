import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ExerciseDataService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get today's date as a string key (YYYY-MM-DD)
  String _getTodayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // Store daily exercise data
  Future<void> storeDailyExerciseData({
    required List<Map<String, dynamic>> exercises,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw 'No user logged in';
    }

    final dateKey = _getTodayKey();
    final exerciseData = <String, dynamic>{
      'date': dateKey,
      'timestamp': FieldValue.serverTimestamp(),
      'exercises': exercises,
    };

    // Store in patients/{userId}/exercise_data/{dateKey}
    await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('exercise_data')
        .doc(dateKey)
        .set(exerciseData, SetOptions(merge: true));
  }

  // Get today's exercise data
  Future<Map<String, dynamic>?> getTodayExerciseData() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw 'No user logged in';
    }

    final dateKey = _getTodayKey();
    final doc = await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('exercise_data')
        .doc(dateKey)
        .get();

    if (doc.exists) {
      return doc.data();
    }
    return null;
  }

  // Get exercise data for a specific date
  Future<Map<String, dynamic>?> getExerciseDataForDate(String dateKey) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw 'No user logged in';
    }

    final doc = await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('exercise_data')
        .doc(dateKey)
        .get();

    if (doc.exists) {
      return doc.data();
    }
    return null;
  }

  // Get exercise data for a date range
  Future<List<Map<String, dynamic>>> getExerciseDataRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw 'No user logged in';
    }

    final querySnapshot = await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('exercise_data')
        .where('date', isGreaterThanOrEqualTo: _formatDate(startDate))
        .where('date', isLessThanOrEqualTo: _formatDate(endDate))
        .orderBy('date', descending: false)
        .get();

    return querySnapshot.docs.map((doc) => doc.data()).toList();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

