import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:developer';

class GoogleSignInService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<UserCredential?> signInWithGoogle() async {
    try {
      // Initialize Google Sign-In
      await _googleSignIn.initialize();

      // Trigger the Google Sign-In flow
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      // Create a new credential
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        // accessToken: googleAuth.accessToken, // TODO: Check if available in current version
      );

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      // Create or update user document in Firestore
      await _createOrUpdateUserDocument(userCredential.user!);

      return userCredential;
    } catch (e) {
      log('Google Sign-In Error: $e');
      return null;
    }
  }

  static Future<void> _createOrUpdateUserDocument(User user) async {
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);

    // Check if user document already exists to preserve companySetup status
    final existingDoc = await userRef.get();
    final bool isNewUser = !existingDoc.exists;

    // Build the base update payload — never overwrite companySetup for existing users
    final Map<String, dynamic> data = {
      'uid': user.uid,
      'email': (user.email ?? '').toLowerCase(),
      'displayName': user.displayName ?? '',
      'photoURL': user.photoURL ?? '',
      'provider': 'google',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Only set companySetup: false for genuinely new users.
    // Existing users (e.g. previously signed up with email+password and
    // now signing in with Google) must retain their existing companySetup value.
    if (isNewUser) {
      data['companySetup'] = false;
      data['preferredTheme'] = 'dark';
      data['createdAt'] = FieldValue.serverTimestamp();
    }

    await userRef.set(data, SetOptions(merge: true));
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
