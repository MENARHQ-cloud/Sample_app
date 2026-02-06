# Gmail Statement Reader

A beautiful Flutter Android app that connects to your Gmail account via IMAP to view and download statement emails with PDF attachments.

## Features

✨ **Beautiful Dark UI** - Premium dark theme with gradient backgrounds and smooth animations  
🔐 **Secure IMAP Connection** - Connect to Gmail using your email and app password  
📧 **Smart Email Filtering** - Automatically finds emails with "statement" in subject and PDF attachments  
👥 **Sender Grouping** - View all senders who have sent statement emails, sorted by count  
📱 **Latest Email View** - See the latest statement email from any sender  
📎 **PDF Download** - Download and open PDF attachments directly from the app  

## Screenshots

The app features:
- **Login Screen** - Animated login with Gmail email and app password fields
- **Senders List** - Shows all senders with colorful avatars and email counts
- **Email Detail** - Displays subject, date, body, and PDF attachments

## Setup Instructions

### Prerequisites

1. **Gmail Account** with 2-Step Verification enabled
2. **App Password** generated from Google Account Security settings

### How to Get Gmail App Password

1. Go to [Google Account Security](https://myaccount.google.com/security)
2. Enable **2-Step Verification** if not already enabled
3. Search for "App passwords"
4. Create a new app password for "Mail"
5. Copy the 16-character code (spaces will be ignored)

### Installation

1. Download the APK from the releases section or build it yourself
2. Install on your Android device (enable "Install from Unknown Sources" if needed)
3. Open the app and enter your Gmail credentials:
   - **Gmail Address**: your.email@gmail.com
   - **App Password**: Your 16-character app password

## Building from Source

### Requirements

- Flutter SDK 3.24.0 or higher
- Android SDK with platform-tools and build-tools
- Java JDK 17

### Build Steps

```bash
# Install dependencies
flutter pub get

# Build release APK
flutter build apk --release

# Or build app bundle
flutter build appbundle --release
```

The APK will be located at: `build/app/outputs/flutter-apk/app-release.apk`

## Dependencies

- **enough_mail** (^2.1.6) - IMAP email client
- **intl** (^0.19.0) - Date formatting
- **path_provider** (^2.1.2) - File system access
- **open_file** (^3.3.2) - Open downloaded PDFs
- **permission_handler** (^11.3.0) - Storage permissions

## Technical Details

### Architecture

- **IMAP Connection**: Uses Gmail's IMAP server (imap.gmail.com:993)
- **Email Search**: Searches for emails with "statement" in subject
- **PDF Detection**: Filters emails that have PDF attachments
- **Grouping**: Groups emails by sender with count
- **Latest Email**: Fetches the most recent email from each sender

### Security

- App passwords are **not stored** - they're only used for authentication
- All communication uses **secure TLS/SSL** connection
- Credentials remain in-memory only

## Permissions

The app requires the following Android permissions:

- `INTERNET` - To connect to Gmail IMAP server
- `ACCESS_NETWORK_STATE` - To check network connectivity
- `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` - To save PDF attachments

## Troubleshooting

### Authentication Failed

- Verify 2-Step Verification is enabled on your Google account
- Ensure you're using an **App Password**, not your main Gmail password
- Check that the app password is entered correctly (spaces are auto-removed)

### No Emails Found

- Verify you have emails with "statement" in the subject line
- Ensure those emails have PDF attachments
- Try refreshing the list

### Cannot Download PDF

- Check storage permissions are granted
- Ensure you have enough storage space

## License

This project is open source and available under the MIT License.

## Developer

Built with ❤️ using Flutter

---

**Note**: This app is for personal use only. Always keep your app passwords secure and never share them with anyone.
