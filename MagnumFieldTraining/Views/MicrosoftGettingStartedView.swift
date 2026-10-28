import SwiftUI

enum MicrosoftTrainingApp: String, CaseIterable, Identifiable {
    case outlook = "Outlook"
    case teams = "Teams"

    var id: String { rawValue }
    var symbol: String { self == .outlook ? "envelope.fill" : "person.2.fill" }
    var monogram: String { self == .outlook ? "O" : "T" }
    var color: Color {
        self == .outlook
            ? Color(red: 0.02, green: 0.36, blue: 0.70)
            : Color(red: 0.34, green: 0.32, blue: 0.65)
    }

    var guides: [MicrosoftGuide] {
        switch self {
        case .outlook:
            [
                MicrosoftGuide(title: "Set up Outlook on iOS", detail: "Add your email account and sign in.", symbol: "person.crop.circle.badge.plus", path: "outlook/install-mobile/set-up-the-outlook-app-for-ios"),
                MicrosoftGuide(title: "Email and calendar basics", detail: "Find your way around messages and calendar events.", symbol: "envelope", path: "outlook/outlook-for-ios-and-android-quick-start"),
                MicrosoftGuide(title: "Organize your Focused Inbox", detail: "Keep important messages easy to find.", symbol: "tray", path: "outlook/training/focused-inbox-email-filter-in-outlook-mobile"),
                MicrosoftGuide(title: "Customize Outlook", detail: "Adjust swipe actions and other mobile settings.", symbol: "slider.horizontal.3", path: "outlook/optimize-the-outlook-mobile-app-for-your-ios-or-android-phone"),
                MicrosoftGuide(title: "Share and view calendars", detail: "Coordinate schedules with your coworkers.", symbol: "calendar", path: "outlook/training/calendar-sharing-in-outlook-mobile"),
                MicrosoftGuide(title: "Search email and files", detail: "Find messages, contacts, and attachments quickly.", symbol: "magnifyingglass", path: "outlook/training/search-made-simple-in-outlook-mobile"),
                MicrosoftGuide(title: "Schedule a meeting", detail: "Find a meeting time that works for your coworkers.", symbol: "calendar.badge.plus", path: "outlook/training/scheduling-made-easy-in-outlook-mobile"),
                MicrosoftGuide(title: "Set automatic replies", detail: "Let people know when you are away.", symbol: "arrowshape.turn.up.left", path: "outlook/how-do-i-enable-out-of-the-office-messages-for-each-of-my-accounts"),
                MicrosoftGuide(title: "Respond to meeting invitations", detail: "Accept, decline, or tentatively accept an invitation.", symbol: "checkmark.circle", path: "outlook/training/rsvp-to-invites-instantly-in-outlook-mobile")
            ]
        case .teams:
            [
                MicrosoftGuide(title: "Sign in to Teams", detail: "Get started with your work or school account.", symbol: "person.crop.circle", path: "teams/meetings/how-to-log-in-to-microsoft-teams"),
                MicrosoftGuide(title: "Manage your chats", detail: "Find shared content and manage mobile conversations.", symbol: "bubble.left.and.bubble.right", path: "teams/chat/manage-chats-with-the-teams-mobile-app"),
                MicrosoftGuide(title: "Join a meeting", detail: "Connect to a meeting from your phone or tablet.", symbol: "video", path: "teams/meetings/join-a-meeting-in-microsoft-teams"),
                MicrosoftGuide(title: "Use meeting controls", detail: "Manage your microphone, camera, and meeting chat.", symbol: "mic", path: "teams/meetings/use-meeting-controls-in-microsoft-teams"),
                MicrosoftGuide(title: "Share your screen", detail: "Present your iPhone or iPad screen during a meeting and learn how to stop sharing.", symbol: "rectangle.on.rectangle", path: "teams/meetings/present-content-in-microsoft-teams-meetings"),
                MicrosoftGuide(title: "Manage mobile notifications", detail: "Choose your alerts and troubleshoot missing notifications.", symbol: "bell", path: "teams/notifications-settings/troubleshoot-notifications-in-microsoft-teams-mobile-apps"),
                MicrosoftGuide(title: "Share files", detail: "Send documents in chats and channels from your device.", symbol: "paperclip", path: "teams/files/share-files-in-microsoft-teams"),
                MicrosoftGuide(title: "Set your status message", detail: "Let coworkers know your availability.", symbol: "person.crop.circle.badge.checkmark", path: "teams/notifications-settings/set-your-status-message-in-microsoft-teams"),
                MicrosoftGuide(title: "Make calls", detail: "Call contacts and learn about your available calling options.", symbol: "phone", path: "teams/calls-devices/use-the-dial-pad-to-make-a-call-in-microsoft-teams")
            ]
        }
    }
}

struct MicrosoftGuide: Identifiable {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let symbol: String
    let path: String

    var id: String { path }
    var url: URL? {
        URL(string: "https://support.microsoft.com/en-us/" + path)
    }
}

struct MicrosoftTrainingRow: View {
    let app: MicrosoftTrainingApp

    var body: some View {
        HStack(spacing: 16) {
            MicrosoftTrainingIcon(app: app, size: 44)
                .frame(width: 56, height: 56)
            Text(app.rawValue)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .trainingCard()
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityHint("Getting started guides for iOS from Microsoft")
    }
}

struct MicrosoftTrainingTile: View {
    @Environment(\.locale) private var locale
    let app: MicrosoftTrainingApp

    var body: some View {
        ResourceTile(title: app.rawValue, subtitle: AppLanguage.string("Getting started", locale: locale)) {
            MicrosoftTrainingIcon(app: app, size: 56)
        }
        .accessibilityHint("Opens Microsoft training guides")
    }
}

private struct MicrosoftTrainingIcon: View {
    let app: MicrosoftTrainingApp
    var size: CGFloat = 104

    var body: some View {
        Image(app == .outlook ? "OutlookIcon" : "TeamsIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 22 / 104))
        .accessibilityHidden(true)
    }
}

struct MicrosoftGettingStartedView: View {
    let app: MicrosoftTrainingApp

    var body: some View {
        List {
            Section {
                MicrosoftGuideIntroduction(app: app)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
            }
            Section {
                ForEach(WebGuideCatalog.guides(for: app)) { guide in
                    WebGuideRow(guide: guide)
                        .documentRowStyle()
                }
            } header: {
                Text("Start with the basics")
                    .textCase(nil)
            } footer: {
                Text("Guides open on Microsoft Support and require an internet connection. Select iOS or Mobile when a guide offers multiple platforms. Follow your organization's instructions for your work account.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(Color("WarmBackground"))
        .navigationTitle(app.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MicrosoftGuideIntroduction: View {
    let app: MicrosoftTrainingApp

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MicrosoftTrainingIcon(app: app)
                .padding(.leading, 10)
                .padding(.bottom, 8)
            Text("Get started with \(app.rawValue).")
                .font(.largeTitle.weight(.bold))
            Text("The essentials for using \(app.rawValue) on your iPhone or iPad.")
                .font(.body)
                .foregroundStyle(.secondary)
            Label("Guides from Microsoft Support", systemImage: "safari")
                .font(.caption.weight(.medium))
                .foregroundStyle(app.color)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        MicrosoftGettingStartedView(app: .outlook)
            .environmentObject(PinnedStore())
    }
}
