R4M DOWNLOADER — BUILD YOUR APK WITH GITHUB

IMPORTANT:
This project builds an installable DEBUG APK for testing/sharing.
The Android app currently downloads direct HTTP/HTTPS media-file links only.
Pasting a normal video webpage URL (for example a YouTube watch page) will NOT
work in this Android starter. It does not bypass DRM, paywalls, login restrictions,
private content, or website access controls.

EASY STEPS

1. Open https://github.com/new and sign in.
2. Repository name: R4M-Downloader
3. Choose Public or Private. Keep "Add a README" unchecked.
4. Click "Create repository".
5. On the empty repository page, choose "uploading an existing file".
6. Extract this ZIP on your PC. Open the extracted R4M_Downloader_GitHub folder.
7. Upload the CONTENTS of that folder (including the hidden .github folder).
   If Windows hides .github, enable View > Show > Hidden items in File Explorer.
8. Commit the files to the main branch.
9. Open the repository's Actions tab. Select "Build R4M Downloader APK".
10. If prompted, click "I understand my workflows, go ahead and enable them".
11. Open the running/completed workflow. When it finishes with a green check,
    scroll to Artifacts and download "R4M-Downloader-APK".
12. Extract the downloaded artifact ZIP. Inside is app-debug.apk.
    Transfer app-debug.apk to your Android phone and tap it to install.
    Android may ask you to allow installs from that source.

If you cannot see the .github folder:
In File Explorer, select View > Show > Hidden items, then upload it too.

APP LIMITS / HONEST NOTES
- APK build is automated by GitHub Actions; this ZIP is not itself an APK.
- The app supports direct HTTP(S) media-file URLs on Android.
- The quality/format selectors are currently basic UI preferences; the app does
  not transcode or extract video from arbitrary website pages on Android.
- This is a debug build for testing, not a signed Play Store release.
- Do not use it to bypass DRM, paywalls, private content, or access restrictions.
