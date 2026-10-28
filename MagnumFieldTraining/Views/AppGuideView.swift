import SwiftUI

struct AppGuideView: View {
    var body: some View {
        List {
            FormGuideSection()
            AppBasicsGuideSection()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color("WarmBackground"))
        .navigationTitle("How to Use This App")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FormGuideSection: View {
    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Save before closing").font(.headline)
                    Text("Unfinished forms are not saved as drafts. Save or send your completed copy before tapping Close. Opening the form again starts with a fresh template.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(AppStyle.accent)
            }
            .padding(.vertical, 4)
        }
        Section("Fill out a form") {
            AppGuideStep(number: "1", title: "Open the form",
                         detail: "Open Downloadable Forms or your forms folder, then tap the form’s name. The download and share buttons beside the name export the blank template; tap the name to fill it out.")
            AppGuideStep(number: "2", title: "Enter your information",
                         detail: "Tap a fillable text field to type, or tap a checkbox to select it. Pinch to zoom and swipe to move between pages. If an area does not accept typing, use Markup to write on it.")
            AppGuideStep(number: "3", title: "Sign or write with Markup",
                         detail: "Zoom to the area first, then tap the Markup pencil near the top. Choose Pen and draw your signature, initials, or notes with your finger or Apple Pencil. Tap Done Markup to type, scroll, or zoom again.")
            AppGuideStep(number: "4", title: "Correct a mistake",
                         detail: "Use Eraser to remove marks you drew, or Undo and Redo to step through markup changes. These tools do not erase the printed form or typed field values. To change typed text, leave Markup and tap the field.")
            AppGuideStep(number: "5", title: "Review every page",
                         detail: "Check your entries and signature on every page in the editor. Make any corrections before sharing.")
            AppGuideStep(number: "6", title: "Save or send your completed copy",
                         detail: "Tap Share at the top of the editor. Choose Save to Files, pick a folder, and tap Save; or choose Mail, Messages, AirDrop, or another available app and finish sending there. Sharing does not automatically submit the form to your company.")
        }
    }
}

private struct AppBasicsGuideSection: View {
    var body: some View {
        Section("Everyday shortcuts") {
            AppGuideTip(title: "Find and bookmark resources", symbol: "bookmark",
                        detail: "Open a folder or use the Home search. Touch and hold an item, then choose Bookmark. Find saved items under Bookmarked on Home. Touch and hold again and choose Remove Bookmark to remove one.")
            AppGuideTip(title: "Use the Company Directory", symbol: "person.crop.rectangle",
                        detail: "Search by name, email, or phone number. Tap a phone number to call or an email address to write a message. Use the small person-plus button on the right to review and save someone to Apple Contacts.")
            AppGuideTip(title: "Scan paper documents", symbol: "doc.viewfinder",
                        detail: "Open Scan & Send from navigation, then tap Scan Document. Capture your pages and check their corners. After scanning, use Markup if needed, then tap Share to save the PDF to Files or send it before closing.")
        }
        Section("Downloads and offline use") {
            AppGuideTip(title: "Download automatically on Wi-Fi", symbol: "wifi",
                        detail: "In Settings, turn on Auto-Download All on Wi-Fi. New and updated files download when the app is active on Wi-Fi. Reopen the app to continue downloads after iOS pauses it in the background.")
            AppGuideTip(title: "Prepare before heading to the field", symbol: "arrow.down.circle",
                        detail: "While connected, open the files you need or use a folder’s download button. Wait for downloads to finish. Downloaded files can be opened offline; web guides and online links still need internet.")
            AppGuideTip(title: "Refresh or retry", symbol: "arrow.clockwise",
                        detail: "Pull down on Home or a folder to check for updates. If a file will not open, check your connection and try again. With Wi-Fi Only for Videos enabled, connect to Wi-Fi or choose Download Anyway when offered.")
            AppGuideTip(title: "Free up storage", symbol: "internaldrive",
                        detail: "Clear Cached Files in Settings removes downloaded library copies. You will need internet to download them again. Save completed forms separately in Files before closing the editor.")
        }
    }
}

private struct AppGuideStep: View {
    let number: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(AppStyle.accent)
                .frame(minWidth: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct AppGuideTip: View {
    let title: LocalizedStringKey
    let symbol: String
    let detail: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(AppStyle.accent)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        AppGuideView()
    }
}
