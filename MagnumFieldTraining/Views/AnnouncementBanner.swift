import SwiftUI

/// Owns visibility so dismissed or expired notices leave no empty list section.
struct AnnouncementSection: View {
    let announcement: Announcement
    @AppStorage("dismissedAnnouncementIDs") private var dismissedData = Data()
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()

    private var dismissedIDs: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: dismissedData)) ?? []
    }

    var body: some View {
        Group {
            if announcement.isVisible(at: now, dismissedIDs: dismissedIDs) {
                Section {
                    AnnouncementBanner(announcement: announcement) {
                        var ids = dismissedIDs
                        ids.insert(announcement.dismissalID)
                        if let data = try? JSONEncoder().encode(ids) { dismissedData = data }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .task(id: announcement.expiresAt) {
            // Recheck wall-clock time periodically to handle device clock changes offline.
            now = Date()
            guard let expiration = announcement.expiresAt else { return }
            while now < expiration {
                do {
                    try await Task.sleep(for: .seconds(min(60, expiration.timeIntervalSince(now))))
                } catch { return }
                now = Date()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
    }
}

struct AnnouncementBanner: View {
    let announcement: Announcement
    let dismiss: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        let content = announcement.translation(for: locale)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "megaphone.fill")
                .font(.title2)
                .padding(.top, 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: content.title)
                        .font(.headline)
                    if !content.message.isEmpty {
                        Text(verbatim: content.message)
                            .font(.subheadline)
                    }
                }
                .accessibilityElement(children: .combine)
                if let link = announcement.link {
                    Link(destination: link) {
                        Label("Learn more", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                            .underline()
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss announcement")
        }
        .padding(12)
        .foregroundStyle(.white)
        .tint(.white)
        .background(Color(red: 24 / 255, green: 78 / 255, blue: 139 / 255),
                    in: RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
    }
}
