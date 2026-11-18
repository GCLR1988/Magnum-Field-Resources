# Connecting a Program to Dropbox

## Xcode Cloud builds

The project compiles `MagnumFieldTraining/Sync/StagingCredentials.local.swift`.
This file is intentionally ignored by Git, so it is unavailable in a fresh cloud
checkout. Do not commit the credentials file to fix a missing-input build error.

The executable `ci_scripts/ci_post_clone.sh` runs after Xcode Cloud clones the
repository. Its Swift helper generates the required file from these workflow
environment variables:

| Secret environment variable | Value from the existing local credentials file |
| --- | --- |
| `DROPBOX_APP_KEY` | `StagingCredentials.appKey` |
| `DROPBOX_APP_SECRET` | `StagingCredentials.appSecret` |
| `DROPBOX_REFRESH_TOKEN` | `StagingCredentials.refreshToken` |

In Xcode Cloud, edit the workflow's Environment settings and add all three
variables, marking each **Secret** (or **Keep value redacted** in Xcode).
Copy only the string values, without Swift quotation marks. Use the credentials
for the same Dropbox source as the local app. Despite the historical filename,
both Debug and Release currently use this source.

Commit and push both files in `ci_scripts` along with the intended app changes,
then start a build from that updated commit. Retrying the old commit will not
include the fix. The script fails early with the missing variable's name if
configuration is incomplete; it never prints credential values.

This keeps secrets out of Git and build logs. It preserves the existing app
architecture, which embeds those credentials in the compiled application.

Apple reference: https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

This lets you drop a PDF into a Dropbox folder and have it show up in the
app automatically -- no rebuild needed. The app authenticates as itself
(no one has to sign in), and can only ever see one dedicated folder.

## 1. Create a Dropbox app

1. Go to https://www.dropbox.com/developers/apps and click **Create app**.
2. Choose **Scoped access**.
3. Choose **App folder** access type -- this is what keeps the app limited
   to one dedicated folder instead of your whole Dropbox. Dropbox will
   create a folder like `Apps/Training Depot` for it.
4. Name the app (e.g. "Training Depot") and create it.

No admin approval is needed for this -- it's tied to whichever Dropbox
account creates it (use whichever account should "own" the training files).

## 2. Set permissions

1. In the app's **Permissions** tab, enable:
   - `files.metadata.read`
   - `files.content.read`
2. Click **Submit** to save.

## 3. Get an app key and secret

On the app's **Settings** tab, copy the **App key** and **App secret**.

## 4. Get a refresh token (one-time authorization)

This is the one interactive step -- it happens once, not per foreman. It
links the app to the Dropbox account holding the files and gives the app
a refresh token that keeps working indefinitely afterward.

1. In a browser, visit this URL (replace `YOUR_APP_KEY`):
   ```
   https://www.dropbox.com/oauth2/authorize?client_id=YOUR_APP_KEY&response_type=code&token_access_type=offline
   ```
2. Sign in and click **Allow**. Dropbox will show you an authorization code -- copy it.
3. Exchange that code for a refresh token. From any terminal with internet
   access (your Mac's Terminal app works fine):
   ```
   curl https://api.dropboxapi.com/oauth2/token \
     -d code=YOUR_AUTH_CODE \
     -d grant_type=authorization_code \
     -d client_id=YOUR_APP_KEY \
     -d client_secret=YOUR_APP_SECRET
   ```
4. The response includes a `"refresh_token"` field -- copy that value.

## 5. Fill in the app's config

Open `MagnumFieldTraining/Sync/DropboxConfig.swift` and fill in the three values:

```swift
static let appKey = "..."         // App key from step 3
static let appSecret = "..."      // App secret from step 3
static let refreshToken = "..."   // refresh_token from step 4
```

## 6. Add folders and point each program at one

Supported file types in a program's folder: `.pdf`, `.mp4`, `.mov`, `.m4v`
-- everything else is ignored. Since videos are much bigger than PDFs and
get downloaded automatically during sync (same as PDFs), keep an eye on
folder size if you're on a limited data plan when testing.

1. In the Dropbox app folder (`Apps/Training Depot`), create a
   subfolder per program: `Procore`, `BusyBusy`, `Bluebeam Revu`,
   `Autodesk Build` (or whatever names you want).
2. Open `MagnumFieldTraining/Data/ProgramData.swift` and make sure each
   program's path matches, e.g. `.dropbox(path: "/Procore")`.
3. Optional: within a program's folder, you can add subfolders too (e.g.
   `Procore/Estimating`) to organize a large set of walkthroughs -- they
   show up as tappable folders inside that program, nested to any depth.
4. Optional: to give a program its own logo on the home screen instead of
   the generic folder icon, drop a `logo.png` (or `.jpg`/`.jpeg`) into
   that program's own top-level subfolder (not inside a nested folder),
   alongside its PDFs and videos. It picks it up the next time that
   program syncs -- no rebuild needed.

## 7. Build & test

Run the app. The very first time it's ever opened, it fetches the current
file list from each configured Dropbox folder and downloads everything
right away, so it's fully usable offline from that point on. Every launch
after that (and every pull-to-refresh) just checks what's changed -- fast,
since it's not re-downloading anything -- and shows a "New Content
Available! / Download Now" banner in the bottom-right corner if it finds
something new or updated, rather than making you wait for it on open. If
something's off, the program's screen will show a red banner with the
error Dropbox returned -- most commonly a wrong folder path, or
permissions not saved in step 2.

## Announcement banner

### Full-featured announcements (recommended)

Use `Announcement.json` to control expiration, a link, and English/Spanish
content. The blue banner remains below the main home-screen banner.

1. Install the updated app build.
2. Open the connected Dropbox app folder that contains your program folders.
3. Create a UTF-8 plain-text file named exactly `Announcement.json`, using
   the template below. In TextEdit, use **Format > Make Plain Text** first.
   Alternatively, ask an LLM to generate a downloadable JSON file from this template.
4. Replace the ID, text, and expiration date. Use `null` for no expiration
   or no link. Keep quotes and commas as shown; do not include Markdown fences.
5. Upload the file alongside the program folders. Remove the old
   `Announcement.txt` to avoid it returning if the JSON file is later deleted.
6. Wait for Dropbox to upload, then open Home and pull down to refresh.
7. Switch the app to Spanish to verify the Spanish content. Tap the X to
   dismiss it; relaunching should keep it hidden. To publish another notice,
   change `id` to a new unique value and refresh.

```json
{
  "id": "safety-training-2026-11-20",
  "enabled": true,
  "expiresAt": "2026-11-20T17:00:00-08:00",
  "link": null,
  "en": {
    "title": "Safety Reminder",
    "message": "Please complete your fall protection training by Friday."
  },
  "es": {
    "title": "Recordatorio de seguridad",
    "message": "Completa la capacitación sobre protección contra caídas antes del viernes."
  }
}
```

- **Expiration:** The example expires November 20, 2026, at 5 p.m. Pacific
  Standard Time. Use a full ISO 8601 timestamp with an explicit time-zone
  offset. Pacific Standard Time uses `-08:00`; Pacific Daylight Time uses
  `-07:00`. Expiration works from the downloaded copy while offline, using
  the device clock. Set `expiresAt` to `null` for no expiration.
- **Dismissal:** The X hides that ID on that device, including after relaunch.
  Keep the ID for typo corrections; change it for a new announcement that
  everyone should see. Switching languages does not reset dismissal.
- **Links:** Replace `null` with a quoted URL such as
  `"https://example.com/training.pdf"`. The “Learn more” control opens an
  HTTP/HTTPS webpage or document link in the system handler. For Dropbox
  documents, use a shared link that your audience can access, not a local
  file path. Linked content may need internet access or a separate sign-in.
- **Languages:** `en` is required; `es` is optional. The app selects Spanish
  when its language toggle is Spanish, falling back to English if `es` is
  missing or its title is blank. Supply the translations yourself; the app
  does not automatically translate the announcement.
- **Hide for everyone:** Set `enabled` to `false` and refresh. Alternatively,
  delete both announcement files. Devices must sync to receive this change.
  A downloaded expiration date still takes effect without syncing.
- **Format:** Keep the file below 64 KB. Use `\n` inside a message for line
  breaks. Invalid JSON, invalid dates, or unsupported links preserve the
  previous valid announcement until a corrected file syncs.
- **Priority:** If both formats exist, JSON wins, even when disabled or
  expired. An invalid JSON file does not fall back to the text file.

### Simple text announcements (still supported)

The home screen reads `Announcement.txt` from the root of the connected
Dropbox app folder when no `Announcement.json` exists. This is an in-app
banner; it does not send push notifications.

1. Install the app build that includes the announcement banner.
2. Open the Dropbox folder that already contains your app's program folders
   (for example, `Apps/Training Depot`). Use the folder for the build you are
   running if your live and staging builds connect to different Dropbox apps.
3. Upload the sample `Announcement.txt` from this project's root directly into
   that folder, alongside the program folders, not inside one of them.
4. To change the announcement on your Mac, open the file in TextEdit. Choose
   **Format > Make Plain Text** if the document is in rich-text mode. Save as
   `Announcement.txt` with UTF-8 encoding. Keep the file under 64 KB.
5. Put the title on the first line and the message on the following lines:

   ```text
   Safety Reminder
   Please complete your fall protection training by Friday.
   ```

6. Save it to your synced Dropbox folder, or upload it to Dropbox and replace
   the existing `Announcement.txt`. Wait for the upload to finish.
7. Open the app's Home screen and pull down to refresh. The banner appears
   below the introduction. The app also checks when it becomes active.
8. To remove the banner, empty the file or delete it from Dropbox, then refresh.

The last successfully downloaded announcement remains available offline.
Deletion or clearing takes effect on each device after its next successful
sync. Network errors or invalid text leave the previous announcement intact.
Text appears exactly as written, regardless of the app's selected language;
use the JSON format above for separate language versions. Text announcements
can also be dismissed; editing their text makes them appear again.
No new Dropbox permissions,
shared links, or developer-console changes are needed for an already connected app.

If the banner does not appear, check that the file is named `Announcement.txt`
(not `.rtf` or `.txt.txt`), is in the correct app folder, and has finished
uploading. Confirm that the app can refresh its other Dropbox content.

## Connection notes / limits

- **The refresh token doesn't expire on its own** (unlike a SharePoint
  client secret), so there's no forced rotation schedule -- it only stops
  working if someone revokes the app's access from the Dropbox account's
  connected-apps settings.
- **Security trade-off**: this embeds credentials in the shipped app so no
  one has to sign in. "App folder" access limits the blast radius if the
  app is ever reverse engineered to just that one dedicated folder -- but
  it's not zero-risk. If these PDFs become sensitive later, it's worth
  moving to a small backend proxy instead (ask and I can build that version).
- **I couldn't test this against a live Dropbox account** -- I don't have
  one to test with. The API calls follow Dropbox's documented formats, but
  if you hit an unexpected error, send it to me and I'll adjust the code.
