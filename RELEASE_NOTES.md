## Shredder v1.0.0

The first public release of Shredder, a native macOS utility that securely overwrites files and folders before removing them.

### First launch

Shredder is not signed with an Apple Developer ID, so macOS may block it the first time you open it.

1. Right-click (or Control-click) **Shredder.app**, choose **Open**, then click **Open**.
2. If that is blocked on newer macOS versions, open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** for Shredder.
3. Terminal fallback:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Shredder.app
   ```
