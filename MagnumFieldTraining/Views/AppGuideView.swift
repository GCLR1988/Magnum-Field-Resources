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
                    Text("Pick up where you left off").font(.headline)
                    Text("Library forms appear in My Forms & Templates only after you add them. Fill in your information, tap the red Add to My Forms & Templates button, and choose Save Form. Your current entries and markup are included. Changes to forms already saved there are kept automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(AppStyle.accent)
            }
            .padding(.vertical, 4)
        }
        Section("Personal templates") {
            AppGuideTip(title: "Reuse your usual information", symbol: "doc.on.doc",
                        detail: "Fill out a form, tap the red Add to My Forms & Templates button at the bottom, and choose Save as Reusable Template. Under Resources, open My Forms & Templates and tap your template to create a separate form with its saved information. Update the date and any other details, review signatures, then share. Touch and hold a saved item to rename or delete it, or edit a template.")
        }
        Section("Fill out a form") {
            AppGuideStep(number: "1", title: "Open the form",
                         detail: "Open Safety Forms or Payroll Forms, then tap a form’s name to fill it out. The menu beside the name lets you save or share the blank form.")
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
                        detail: "Use Home search to find names and text inside downloaded PDFs. Filter by forms, videos, guides, or downloaded files. Tap a content result to open its matching page. Scanned PDFs without a text layer cannot be searched. Touch and hold a resource to bookmark it.")
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
                        detail: "Clear Cached Files in Settings removes downloaded library copies. Your form drafts and personal templates are kept separately and remain on this device. You will need internet to download library files again.")
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
