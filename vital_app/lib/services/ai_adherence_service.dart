import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'daily_tracking_service.dart';
import 'health_data_service.dart';
import 'food_data_service.dart';
import 'exercise_data_service.dart';
import 'auth_service.dart';

class AIAdherenceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DailyTrackingService _dailyTrackingService = DailyTrackingService();
  final HealthDataService _healthDataService = HealthDataService();
  final FoodDataService _foodDataService = FoodDataService();
  final ExerciseDataService _exerciseDataService = ExerciseDataService();
  final AuthService _authService = AuthService();

  // Ensure Gemini is initialized
  void _ensureInitialized() {
    // Check if dotenv is loaded
    try {
      final apiKey = dotenv.env['API_KEY'];

      // Debug: Check if API key was found
      if (apiKey == null) {
        throw 'API key not found in environment variables. Make sure the .env file is loaded and contains API_KEY=your_key';
      }

      if (apiKey.isEmpty) {
        throw 'API key is empty in .env file. Please set API_KEY=your_gemini_api_key';
      }

      if (apiKey == 'your_gemini_api_key_here') {
        throw 'API key not configured. Please replace "your_gemini_api_key_here" with your actual API key in the .env file';
      }

      // Validate API key format (Google API keys typically start with "AIza")
      if (!apiKey.startsWith('AIza')) {
        throw 'API key format appears invalid. Google API keys typically start with "AIza". Please verify your API key in the .env file.';
      }

      try {
        // Initialize Gemini - this should be safe to call multiple times
        // Note: Gemini.init() doesn't throw, but accessing Gemini.instance will throw NotInitializedError if not initialized
        Gemini.init(apiKey: apiKey);

        // Verify that the instance is accessible
        // This will throw NotInitializedError if initialization failed
        try {
          // Access the instance to verify initialization
          // This will throw NotInitializedError if not initialized
          Gemini.instance;
          // If we get here without exception, initialization was successful
        } catch (instanceError) {
          final instanceErrorStr = instanceError.toString();
          if (instanceErrorStr.contains('NotInitialized') ||
              instanceErrorStr.contains('NotInitializedError') ||
              instanceErrorStr.contains('not initialized')) {
            // The initialization might have failed silently
            // Try re-initializing with the same key
            try {
              Gemini.init(apiKey: apiKey);
              // Try accessing instance again
              Gemini.instance;
            } catch (retryError) {
              // If it still fails, the API key might be invalid or there's a deeper issue
              throw 'Gemini API failed to initialize. Please verify:\n'
                  '1. Your API key is valid (check at https://makersuite.google.com/app/apikey)\n'
                  '2. Your API key has the correct format (should start with AIza...)\n'
                  '3. You have internet connectivity\n'
                  'Error details: $instanceError';
            }
          } else {
            rethrow;
          }
        }
      } catch (e) {
        final errorStr = e.toString();
        if (errorStr.contains('NotInitialized') ||
            errorStr.contains('not initialized') ||
            errorStr.contains('not accessible')) {
          throw 'Gemini API not initialized. Please check your API_KEY in the .env file. Error: $e';
        }
        throw 'Failed to initialize Gemini API. Please check your API_KEY in the .env file. Error: $e';
      }
    } catch (e) {
      // Re-throw our custom error messages
      final errorStr = e.toString();
      if (errorStr.contains('API key') ||
          errorStr.contains('not initialized') ||
          errorStr.contains('not accessible') ||
          errorStr.contains('Environment variables')) {
        rethrow;
      }
      throw 'Error initializing Gemini API: $e';
    }
  }

  // Get date key in YYYY-MM-DD format
  String _getDateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  // Get the prompt that would be sent (for debugging)
  Future<String> getPromptForDate(DateTime date) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    // Collect all necessary data (same as generateAdherenceReport)
    final dateKey = _getDateKey(date);

    // 1. Get user profile (excluding identifiers)
    final profile = await _authService.getUserProfile(user.uid, 'patient');
    if (profile == null) {
      throw 'User profile not found. Please complete your profile first.';
    }

    final profileData = {
      'age': profile['age'],
      'gender': profile['gender'],
      'height': profile['height'],
      'weight': profile['weight'],
      'bmi': profile['bmi'],
      'activityLevel': profile['activityLevel'],
      'healthGoals': profile['healthGoals'],
      'chronicConditions': profile['chronicConditions'],
      'allergies': profile['allergies'],
      'medications': profile['medications'],
      'stepGoal': profile['stepGoal'],
      'calorieGoal': profile['calorieGoal'],
    };

    // 2. Get daily tracking (medications, appointments)
    final dailyTracking = await _dailyTrackingService.getDailyTracking(date);
    final medications =
        dailyTracking?['medications'] as Map<String, dynamic>? ??
        <String, dynamic>{};

    // Count medication adherence
    int totalMedicationSlots = 0;
    int checkedMedicationSlots = 0;
    final medicationDetails = <String, Map<String, dynamic>>{};

    medications.forEach((medicineName, timeSlots) {
      final slots = timeSlots as Map<String, dynamic>;
      final medicineData = <String, dynamic>{
        'total': 0,
        'checked': 0,
        'missed': 0,
        'not_taken': 0,
      };

      slots.forEach((timeKey, status) {
        totalMedicationSlots++;
        medicineData['total'] = (medicineData['total'] as int) + 1;

        if (status == 'checked') {
          checkedMedicationSlots++;
          medicineData['checked'] = (medicineData['checked'] as int) + 1;
        } else if (status == 'missed') {
          medicineData['missed'] = (medicineData['missed'] as int) + 1;
        } else {
          medicineData['not_taken'] = (medicineData['not_taken'] as int) + 1;
        }
      });

      medicationDetails[medicineName] = medicineData;
    });

    // 3. Get health metrics for the date
    final healthData = await _healthDataService.getHealthDataForDate(dateKey);
    final steps = healthData?['steps'] as int? ?? 0;
    final caloriesBurned =
        (healthData?['caloriesBurned'] as num?)?.toDouble() ?? 0.0;
    final hoursSlept = (healthData?['hoursSlept'] as num?)?.toDouble() ?? 0.0;
    final heartRate = (healthData?['heartRate'] as num?)?.toDouble() ?? 0.0;

    // 4. Get food data for the date
    final foodData = await _foodDataService.getFoodDataForDate(dateKey);
    final totalCaloriesEaten =
        (foodData?['totalCalories'] as num?)?.toDouble() ?? 0.0;
    final foodsEaten = foodData?['foods'] ?? [];

    // 5. Get exercise data for the date
    final exerciseData = await _exerciseDataService.getExerciseDataForDate(
      dateKey,
    );
    final exercisesDone = exerciseData?['exercises'] ?? [];

    // 6. Get recommended foods and exercises from prescriptions
    final prescriptionsSnapshot = await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('prescriptions')
        .where('approved', isEqualTo: true)
        .get();

    final List<String> recommendedFoods = [];
    final List<String> recommendedExercises = [];

    for (var doc in prescriptionsSnapshot.docs) {
      final data = doc.data();
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
      if (createdAt != null) {
        final prescriptionDateOnly = DateTime(
          createdAt.year,
          createdAt.month,
          createdAt.day,
        );
        final dateOnly = DateTime(date.year, date.month, date.day);

        // Check if prescription is active on this date
        final medicines = List<Map<String, dynamic>>.from(
          data['medicines'] ?? [],
        );
        bool isActive = false;
        for (var med in medicines) {
          final duration = med['duration'] as int? ?? 0;
          final endDate = prescriptionDateOnly.add(Duration(days: duration));
          if (dateOnly.isBefore(endDate) ||
              dateOnly.isAtSameMomentAs(endDate)) {
            isActive = true;
            break;
          }
        }

        if (isActive) {
          recommendedFoods.addAll(
            List<String>.from(data['recommendedFoods'] ?? []),
          );
          recommendedExercises.addAll(
            List<String>.from(data['recommendedExercises'] ?? []),
          );
        }
      }
    }

    // Build and return the prompt
    return _buildAdherencePrompt(
      date: date,
      profileData: profileData,
      medicationDetails: medicationDetails,
      totalMedicationSlots: totalMedicationSlots,
      checkedMedicationSlots: checkedMedicationSlots,
      recommendedFoods: recommendedFoods.toSet().toList(),
      recommendedExercises: recommendedExercises.toSet().toList(),
      foodsEaten: List<Map<String, dynamic>>.from(foodsEaten),
      exercisesDone: List<Map<String, dynamic>>.from(exercisesDone),
      steps: steps,
      caloriesBurned: caloriesBurned.toInt(),
      caloriesEaten: totalCaloriesEaten.toInt(),
      hoursSlept: hoursSlept,
      heartRate: heartRate,
      stepGoal: profileData['stepGoal'] as int? ?? 0,
      calorieGoal: profileData['calorieGoal'] as int? ?? 0,
    );
  }

  // Generate AI adherence report for a specific date
  Future<Map<String, dynamic>> generateAdherenceReport(DateTime date) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    _ensureInitialized();

    // Collect all necessary data
    final dateKey = _getDateKey(date);

    // 1. Get user profile (excluding identifiers)
    final profile = await _authService.getUserProfile(user.uid, 'patient');
    if (profile == null) {
      throw 'User profile not found. Please complete your profile first.';
    }

    final profileData = {
      'age': profile['age'],
      'gender': profile['gender'],
      'height': profile['height'],
      'weight': profile['weight'],
      'bmi': profile['bmi'],
      'activityLevel': profile['activityLevel'],
      'healthGoals': profile['healthGoals'],
      'chronicConditions': profile['chronicConditions'],
      'allergies': profile['allergies'],
      'medications': profile['medications'],
      'stepGoal': profile['stepGoal'],
      'calorieGoal': profile['calorieGoal'],
    };

    // 2. Get daily tracking (medications, appointments)
    final dailyTracking = await _dailyTrackingService.getDailyTracking(date);
    final medications =
        dailyTracking?['medications'] as Map<String, dynamic>? ??
        <String, dynamic>{};

    // Count medication adherence
    int totalMedicationSlots = 0;
    int checkedMedicationSlots = 0;
    final medicationDetails = <String, Map<String, dynamic>>{};

    medications.forEach((medicineName, timeSlots) {
      final slots = timeSlots as Map<String, dynamic>;
      final medicineData = <String, dynamic>{
        'total': 0,
        'checked': 0,
        'missed': 0,
        'not_taken': 0,
      };

      slots.forEach((timeKey, status) {
        totalMedicationSlots++;
        medicineData['total'] = (medicineData['total'] as int) + 1;

        if (status == 'checked') {
          checkedMedicationSlots++;
          medicineData['checked'] = (medicineData['checked'] as int) + 1;
        } else if (status == 'missed') {
          medicineData['missed'] = (medicineData['missed'] as int) + 1;
        } else {
          medicineData['not_taken'] = (medicineData['not_taken'] as int) + 1;
        }
      });

      medicationDetails[medicineName] = medicineData;
    });

    // 3. Get health metrics for the date
    final healthData = await _healthDataService.getHealthDataForDate(dateKey);
    final steps = healthData?['steps'] as int? ?? 0;
    final caloriesBurned =
        (healthData?['caloriesBurned'] as num?)?.toDouble() ?? 0.0;
    final hoursSlept = (healthData?['hoursSlept'] as num?)?.toDouble() ?? 0.0;
    final heartRate = (healthData?['heartRate'] as num?)?.toDouble() ?? 0.0;

    // 4. Get food data for the date
    final foodData = await _foodDataService.getFoodDataForDate(dateKey);
    final totalCaloriesEaten =
        (foodData?['totalCalories'] as num?)?.toDouble() ?? 0.0;
    final foodsEaten = foodData?['foods'] ?? [];

    // 5. Get exercise data for the date
    final exerciseData = await _exerciseDataService.getExerciseDataForDate(
      dateKey,
    );
    final exercisesDone = exerciseData?['exercises'] ?? [];

    // 6. Get recommended foods and exercises from prescriptions
    final prescriptionsSnapshot = await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('prescriptions')
        .where('approved', isEqualTo: true)
        .get();

    final List<String> recommendedFoods = [];
    final List<String> recommendedExercises = [];

    for (var doc in prescriptionsSnapshot.docs) {
      final data = doc.data();
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
      if (createdAt != null) {
        final prescriptionDateOnly = DateTime(
          createdAt.year,
          createdAt.month,
          createdAt.day,
        );
        final dateOnly = DateTime(date.year, date.month, date.day);

        // Check if prescription is active on this date
        final medicines = List<Map<String, dynamic>>.from(
          data['medicines'] ?? [],
        );
        bool isActive = false;
        for (var med in medicines) {
          final duration = med['duration'] as int? ?? 0;
          final endDate = prescriptionDateOnly.add(Duration(days: duration));
          if (dateOnly.isBefore(endDate) ||
              dateOnly.isAtSameMomentAs(endDate)) {
            isActive = true;
            break;
          }
        }

        if (isActive) {
          recommendedFoods.addAll(
            List<String>.from(data['recommendedFoods'] ?? []),
          );
          recommendedExercises.addAll(
            List<String>.from(data['recommendedExercises'] ?? []),
          );
        }
      }
    }

    // Build the prompt for Gemini
    final prompt = _buildAdherencePrompt(
      date: date,
      profileData: profileData,
      medicationDetails: medicationDetails,
      totalMedicationSlots: totalMedicationSlots,
      checkedMedicationSlots: checkedMedicationSlots,
      recommendedFoods: recommendedFoods.toSet().toList(),
      recommendedExercises: recommendedExercises.toSet().toList(),
      foodsEaten: List<Map<String, dynamic>>.from(foodsEaten),
      exercisesDone: List<Map<String, dynamic>>.from(exercisesDone),
      steps: steps,
      caloriesBurned: caloriesBurned.toInt(),
      caloriesEaten: totalCaloriesEaten.toInt(),
      hoursSlept: hoursSlept,
      heartRate: heartRate,
      stepGoal: profileData['stepGoal'] as int? ?? 0,
      calorieGoal: profileData['calorieGoal'] as int? ?? 0,
    );

    // Call Gemini API
    try {
      // Ensure initialization before accessing instance (called again here for safety)
      _ensureInitialized();

      // Access Gemini.instance with error handling for NotInitializedError
      Gemini gemini;
      try {
        gemini = Gemini.instance;
      } catch (e) {
        final errorStr = e.toString();
        if (errorStr.contains('NotInitialized') ||
            errorStr.contains('NotInitializedError')) {
          // Try to re-initialize
          final apiKey = dotenv.env['API_KEY'];
          if (apiKey != null && apiKey.isNotEmpty) {
            Gemini.init(apiKey: apiKey);
            // Try accessing instance again
            gemini = Gemini.instance;
          } else {
            throw 'Gemini API not initialized. API key not found in environment variables.';
          }
        } else {
          rethrow;
        }
      }

      final response = await gemini.prompt(parts: [Part.text(prompt.trim())]);

      // Extract text from response
      String responseText = '';
      if (response?.output != null && response!.output!.isNotEmpty) {
        responseText = response.output!;
      } else if (response?.content?.parts != null &&
          response!.content!.parts!.isNotEmpty) {
        final lastPart = response.content!.parts!.last;
        if (lastPart is TextPart && lastPart.text.isNotEmpty) {
          responseText = lastPart.text;
        }
      }

      if (responseText.isEmpty) {
        throw 'No response received from AI';
      }

      // Parse JSON response
      final jsonResponse = _parseGeminiResponse(responseText);

      // Store the report
      await _storeAdherenceReport(date, jsonResponse);

      return jsonResponse;
    } catch (e) {
      // Handle various error types
      final errorString = e.toString();

      // Handle NotInitialized exception specifically
      if (errorString.contains('NotInitialized') ||
          errorString.contains('NotInitializedError') ||
          errorString.contains('not initialized')) {
        throw 'Gemini API not initialized. Please ensure your API_KEY in the .env file is valid and the app has been restarted after adding it.';
      }

      // Handle API key configuration errors
      if (errorString.contains('API key not configured') ||
          errorString.contains('Environment variables not loaded')) {
        throw e.toString(); // Re-throw the original error message
      }

      // Handle API errors
      if (errorString.contains('401') || errorString.contains('403')) {
        throw 'Invalid API key. Please check your API_KEY in the .env file.';
      }

      if (errorString.contains('429')) {
        throw 'API quota exceeded. Please check your usage limits.';
      }

      // Generic error
      throw 'Failed to generate adherence report: $e';
    }
  }

  String _buildAdherencePrompt({
    required DateTime date,
    required Map<String, dynamic> profileData,
    required Map<String, Map<String, dynamic>> medicationDetails,
    required int totalMedicationSlots,
    required int checkedMedicationSlots,
    required List<String> recommendedFoods,
    required List<String> recommendedExercises,
    required List<Map<String, dynamic>> foodsEaten,
    required List<Map<String, dynamic>> exercisesDone,
    required int steps,
    required int caloriesBurned,
    required int caloriesEaten,
    required double hoursSlept,
    required double heartRate,
    required int stepGoal,
    required int calorieGoal,
  }) {
    final dateStr = DateFormat('MMMM dd, yyyy').format(date);
    final medicationAdherenceRate = totalMedicationSlots > 0
        ? (checkedMedicationSlots / totalMedicationSlots * 100).toStringAsFixed(
            1,
          )
        : '0.0';

    return '''You are a healthcare AI assistant analyzing patient adherence to their treatment plan. Analyze the following data and provide a strict JSON response.

PATIENT PROFILE:
- Age: ${profileData['age'] ?? 'N/A'}
- Gender: ${profileData['gender'] ?? 'N/A'}
- BMI: ${profileData['bmi'] ?? 'N/A'}
- Activity Level: ${profileData['activityLevel'] ?? 'N/A'}
- Health Goals: ${profileData['healthGoals'] ?? 'None'}
- Chronic Conditions: ${(profileData['chronicConditions'] as List?)?.join(', ') ?? 'None'}
- Allergies: ${(profileData['allergies'] as List?)?.join(', ') ?? 'None'}
- Current Medications: ${(profileData['medications'] as List?)?.join(', ') ?? 'None'}
- Step Goal: $stepGoal steps/day
- Calorie Goal: $calorieGoal calories/day

DATE: $dateStr

MEDICATION ADHERENCE:
- Total Medication Slots: $totalMedicationSlots
- Checked (Taken): $checkedMedicationSlots
- Adherence Rate: $medicationAdherenceRate%
- Medication Details: ${medicationDetails.entries.map((e) => '${e.key}: ${e.value['checked']}/${e.value['total']} taken, ${e.value['missed']} missed, ${e.value['not_taken']} pending').join('; ')}

RECOMMENDED FOODS: ${recommendedFoods.isEmpty ? 'None' : recommendedFoods.join(', ')}
FOODS EATEN: ${foodsEaten.isEmpty ? 'None' : foodsEaten.map((f) => '${f['name']} (${f['quantity']} ${f['quantityType']})').join(', ')}
CALORIES EATEN: $caloriesEaten / $calorieGoal

RECOMMENDED EXERCISES: ${recommendedExercises.isEmpty ? 'None' : recommendedExercises.join(', ')}
EXERCISES DONE: ${exercisesDone.isEmpty ? 'None' : exercisesDone.map((e) => '${e['type']}${e['reps'] != null ? ' (${e['reps']} reps, ${e['sets']} sets)' : ''}${e['duration'] != null ? ' (${e['duration']} min)' : ''}').join(', ')}

HEALTH METRICS:
- Steps: $steps / $stepGoal
- Calories Burned: $caloriesBurned
- Hours Slept: ${hoursSlept.toStringAsFixed(1)}
- Heart Rate: ${heartRate > 0 ? '$heartRate bpm' : 'Not recorded'}

INSTRUCTIONS:
1. Analyze adherence across medications, diet, exercise, and health goals
2. Consider the patient's chronic conditions and health goals
3. If data seems incomplete or early in the day, mention this in the report
4. Provide an adherence score from 0-10 (10 = perfect adherence)
5. Generate a concise, actionable report

RESPONSE FORMAT (STRICT JSON ONLY, NO MARKDOWN, NO CODE BLOCKS):
{
  "title": "10-20 word title summarizing adherence",
  "score": <number between 0-10>,
  "report": "Short text report (2-4 sentences) analyzing adherence, mentioning any concerns, and if data appears incomplete or early"
}

IMPORTANT: Return ONLY valid JSON. No explanations, no markdown formatting, no code blocks. Just the JSON object.''';
  }

  Map<String, dynamic> _parseGeminiResponse(String response) {
    // Clean the response - remove markdown code blocks if present
    String cleaned = response.trim();

    // Remove markdown code blocks
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }

    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }

    cleaned = cleaned.trim();

    // Try to find JSON object
    final jsonStart = cleaned.indexOf('{');
    final jsonEnd = cleaned.lastIndexOf('}');

    if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
      throw 'Invalid JSON response from AI. Response: ${response.substring(0, response.length > 200 ? 200 : response.length)}';
    }

    final jsonStr = cleaned.substring(jsonStart, jsonEnd + 1);

    try {
      // Use dart:convert for proper JSON parsing (handles escaped quotes, etc.)
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;

      return {
        'title': decoded['title'] as String? ?? 'Adherence Report',
        'score': (decoded['score'] as num?)?.toDouble() ?? 5.0,
        'report': decoded['report'] as String? ?? 'Unable to generate report.',
      };
    } catch (e) {
      // If JSON parsing fails, try regex as fallback
      try {
        final Map<String, dynamic> result = {};

        // Extract title - handle escaped quotes
        final titlePattern = RegExp(r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"');
        final titleMatch = titlePattern.firstMatch(jsonStr);
        if (titleMatch != null) {
          result['title'] = titleMatch
              .group(1)!
              .replaceAll('\\"', '"')
              .replaceAll('\\n', '\n');
        } else {
          result['title'] = 'Adherence Report';
        }

        // Extract score
        final scoreMatch = RegExp(
          r'"score"\s*:\s*(\d+(?:\.\d+)?)',
        ).firstMatch(jsonStr);
        if (scoreMatch != null) {
          result['score'] = double.parse(scoreMatch.group(1)!);
        } else {
          result['score'] = 5.0;
        }

        // Extract report - handle escaped quotes
        final reportPattern = RegExp(r'"report"\s*:\s*"((?:[^"\\]|\\.)*)"');
        final reportMatch = reportPattern.firstMatch(jsonStr);
        if (reportMatch != null) {
          result['report'] = reportMatch
              .group(1)!
              .replaceAll('\\"', '"')
              .replaceAll('\\n', '\n');
        } else {
          result['report'] = 'Unable to generate report.';
        }

        return result;
      } catch (e2) {
        // Final fallback
        throw 'Failed to parse JSON response. Error: $e2. Response: ${jsonStr.substring(0, jsonStr.length > 300 ? 300 : jsonStr.length)}';
      }
    }
  }

  Future<void> _storeAdherenceReport(
    DateTime date,
    Map<String, dynamic> reportData,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final dateKey = _getDateKey(date);

    await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('ai_reports')
        .doc(dateKey)
        .set({
          'date': Timestamp.fromDate(date),
          'title': reportData['title'],
          'score': reportData['score'],
          'report': reportData['report'],
          'generatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  // Get adherence report for a specific date
  Future<Map<String, dynamic>?> getAdherenceReport(DateTime date) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final dateKey = _getDateKey(date);
    final doc = await _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('ai_reports')
        .doc(dateKey)
        .get();

    if (!doc.exists) return null;

    final data = doc.data() as Map<String, dynamic>;
    return {
      'date': date,
      'title': data['title'],
      'score': data['score'],
      'report': data['report'],
      'generatedAt': (data['generatedAt'] as Timestamp?)?.toDate(),
    };
  }

  // Stream of adherence reports
  Stream<Map<String, dynamic>?> getAdherenceReportStream(DateTime date) {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in';

    final dateKey = _getDateKey(date);
    return _firestore
        .collection('patients')
        .doc(user.uid)
        .collection('ai_reports')
        .doc(dateKey)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;

          final data = doc.data() as Map<String, dynamic>;
          return {
            'date': date,
            'title': data['title'],
            'score': data['score'],
            'report': data['report'],
            'generatedAt': (data['generatedAt'] as Timestamp?)?.toDate(),
          };
        });
  }
}
