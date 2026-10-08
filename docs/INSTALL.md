# Install Codex Sidecar 0.1.0

This is an early, unsigned Apple Silicon release. It has no Apple Developer ID
signature or notarization. macOS may block its first launch. Intel is not included.
The declared minimum is macOS 14, but native acceptance was performed only on
Apple Silicon macOS 27.0.1; older macOS versions are unverified.

## Download and launch

1. Download `Codex-Sidecar-0.1.0-macos-arm64.zip` from the
   [official GitHub release](https://github.com/Gerionil/codex-sidecar/releases/tag/v0.1.0).
   The GitHub-generated source-code archives are not the ready-to-run application.
2. Optionally verify the archive against the release's `SHA256SUMS.txt`:

   ```sh
   shasum -a 256 -c SHA256SUMS.txt
   ```

3. Extract the ZIP and move **Codex Sidecar.app** into **Applications**.
4. Open the application. If macOS blocks it because the developer cannot be
   verified, and you trust this download, open **System Settings → Privacy &
   Security** and use **Open Anyway** for Codex Sidecar. Follow macOS's confirmation
   prompts. See [Apple's explanation](https://support.apple.com/102445).
   Managed-device policies may prohibit exceptions. You can also build from source.
5. Click the Sidecar menu-bar icon or use its companion window.

Do not disable Gatekeeper globally. This release does not install a background
service or start automatically at login.

## First setup

1. Have Codex installed and signed in for account quota access. The checked CLI
   profile is `0.160.1`; other versions are labeled unvalidated.
2. Open Sidecar **Settings** using the gear button. Normally it discovers the
   local Codex data folder and executable. If discovery fails, set the Codex root
   and executable overrides to your installed locations.
3. Choose **System**, **Light**, or **Dark** appearance.
4. Select a chat from **Selected chat**. The choice is manual and stays pinned.
5. Leave **Offline** off to allow passive account quota reads, or turn it on for
   local usage only. Offline does not stop local session updates.

Sidecar never creates model requests. Quotas are account-wide, while observed
usage belongs to the selected chat. Missing or partial records remain unavailable
or partial. Exact current context usage is not supported.

Closing the companion window keeps the menu-bar application running. Use **Open
window** in the panel to reopen it, or **Quit** to stop Sidecar.

## Updating and removing

Quit Sidecar before replacing its app with a newer release. Updates are manual.
To remove the application, quit it and move **Codex Sidecar.app** to Trash. This
does not delete your Codex chats. Sidecar preferences are stored separately.

## Problems

Use [GitHub Issues](https://github.com/Gerionil/codex-sidecar/issues) for bugs.
Include Sidecar, macOS and Codex CLI versions and reproduction steps. Do not
attach credentials, raw Codex logs, private prompts or unsanitized screenshots.
