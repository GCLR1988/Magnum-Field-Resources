# Connecting a Program to Dropbox

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

## Notes / limits

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
