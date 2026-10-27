# Privacy policy

*Last updated: 27 October 2026*

This policy covers the AI-ML Refresher apps for macOS, Windows and Android, including official
releases built from this repository.

## In short

The app has no servers, accounts or analytics. Your data stays on your devices and, if you turn on
sync, in your own Google Drive. The developer never receives it.

## What the app does

- **Daily brief.** Once a day the app downloads public lists from GitHub, Hugging Face, Hacker News,
  Reddit and a set of blogs, and ranks them on your device. These requests carry no personal
  information; the sites see an ordinary request from your device, as when you visit them.
- **Your collection.** Items you save, with your tags, notes and read state, are stored in files on
  your device.
- **Notifications** are created on your device. Nothing is sent to a notification service.

## Sync with Google (optional)

If you choose **Sync with Google**, the app asks Google for permission to use your Google Drive with
the `drive.file` scope. This lets the app create and use **only the files it creates itself**. It
can't see, read or change any other file in your Drive.

With that permission the app:

- creates one file, "AI-ML Refresher library.json", in your Drive, containing your saved
  items, tags, notes, read state and when you removed items;
- reads and updates that file to keep your devices in sync;
- reads your Google account's email address, only to show which account you're syncing with.

The app talks to Google directly from your device. The developer has no server and never receives
your data or your Google sign-in. The sign-in is stored on your device (in the system keychain or
credential store), and you can remove it at any time with **Stop syncing** in Settings. You can also
remove the app's access in your Google Account under *Security → Third-party apps & services*.
Deleting the file from your Drive deletes the synced copy.

The app's use and transfer of information received from Google APIs adheres to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including the Limited Use requirements. The data is used only to sync your collection between your
own devices. It isn't sold, used for advertising, shared with anyone or used to train AI models.

## Deleting your data

Uninstalling the app deletes its files on that device. If you used sync, delete
"AI-ML Refresher library.json" from your Google Drive and remove the app's access as described above.

## Contact

Questions about this policy: open an issue at
https://github.com/MMFreitas1/AI-ML-refresher/issues.

## Changes

Changes to this policy are published in this file; its history is on GitHub.
