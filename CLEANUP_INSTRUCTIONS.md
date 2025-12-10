# Firebase Data Cleanup Instructions

## Option 1: Manual Cleanup via Firebase Console (Recommended)

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Navigate to **Firestore Database**
4. Delete the following collections:
   - `clinicians` (and all subcollections: `prescriptions`, `documents`)
   - `patients` (and all subcollections: `prescriptions`, `active_medications`, `medication_checkins`, `daily_tracking`, `appointment_attendance`, `medical_documents`)
   - `prescription_requests`

**Note:** Make sure to delete subcollections first, then parent documents.

## Option 2: Using the Cleanup Script

### Prerequisites:
- You must be logged into the app as an admin user
- The app must be running and connected to Firebase

### Steps:

1. **Log in to the app** (as admin or any user - the script will delete everything)

2. **Run the cleanup script:**
   ```bash
   cd vital_app
   flutter run lib/scripts/cleanup_firebase_data_standalone.dart
   ```

   Or if you have a main entry point:
   ```bash
   flutter run -t lib/scripts/cleanup_firebase_data_standalone.dart
   ```

3. **Wait for confirmation** - The script will:
   - Show a 3-second warning
   - Delete all prescription requests
   - Delete all clinicians and their subcollections
   - Delete all patients and their subcollections
   - Show a summary of deleted items

## What Gets Deleted:

✅ **Prescription Requests** - All pending/approved/rejected requests
✅ **Clinicians** - All clinician accounts and their:
   - Prescriptions history
   - Verification documents
✅ **Patients** - All patient accounts and their:
   - Prescriptions
   - Active medications
   - Medication check-ins
   - Daily tracking data
   - Appointment attendance
   - Medical documents

## What Stays:

- Firebase Authentication users (you'll need to delete these manually if needed)
- Any other collections not mentioned above

## After Cleanup:

1. Create fresh test accounts:
   - New patient account
   - New clinician account
   - Admin account (if needed)

2. Test the new prescription approval flow:
   - Patient requests prescription
   - Clinician generates prescription
   - Patient approves prescription
   - Medication tracking works

## Safety Notes:

⚠️ **This is a destructive operation!**
- Make sure you're working with a test/development project
- Don't run this on production data
- Consider backing up data first if you need it later

