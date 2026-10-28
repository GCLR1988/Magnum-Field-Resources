import SwiftUI

enum AppleDevice: String, CaseIterable, Identifiable {
    case iPhone
    case iPad

    var id: String { rawValue }
    var symbol: String { self == .iPhone ? "iphone" : "ipad" }

    var guides: [DeviceGuide] {
        [
            DeviceGuide(id: "setup", title: "Set up your device", detail: "Start here with activation and initial setup.", symbol: "power", path: "en-us/105132"),
            DeviceGuide(id: "wifi", title: "Connect to Wi-Fi", detail: "Get online at work, at home, or on the go.", symbol: "wifi", path: "en-us/111107"),
            DeviceGuide(id: "gestures", title: "Learn essential gestures", detail: "Get comfortable tapping, swiping, and zooming.", symbol: "hand.draw", path: self == .iPhone
                ? "guide/iphone/learn-basic-gestures-iph75e97af9b/ios"
                : "guide/ipad/learn-basic-gestures-ipad2c09c4d4/ipados"),
            DeviceGuide(id: "update", title: "Update your software", detail: "Keep your device up to date.", symbol: "arrow.triangle.2.circlepath", path: "en-us/118575"),
            DeviceGuide(id: "backup", title: "Back up with iCloud", detail: "Keep a backup of your important information.", symbol: "icloud", path: "en-us/108366"),
            DeviceGuide(id: "screenshot", title: "Take a screenshot", detail: "Capture and share what is on your screen.", symbol: "camera", path: self == .iPhone ? "en-us/102616" : "guide/ipad/take-a-screenshot-ipad08a40f3b/ipados"),
            DeviceGuide(id: "record", title: "Record your screen", detail: "Capture a demonstration to share with your team.", symbol: "record.circle", path: "en-us/102653"),
            DeviceGuide(id: "scan", title: "Scan and sign documents", detail: "Turn paper documents into scans using Notes.", symbol: "doc.viewfinder", path: "en-us/108963"),
            DeviceGuide(id: "airdrop", title: "Share with AirDrop", detail: "Send photos and documents to nearby Apple devices.", symbol: "airplayaudio", path: "en-us/119857"),
            DeviceGuide(id: "text", title: "Adjust text size", detail: "Make text easier to read on your device.", symbol: "textformat.size", path: "en-us/102453")
        ]
    }
}

struct DeviceGuide: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let symbol: String
    let path: String

    var url: URL {
        URL.httpsAppleSupport.appendingPathComponent(path)
    }
}

private extension URL {
    static var httpsAppleSupport: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "support.apple.com"
        // The scheme and host above are fixed, valid URL components.
        return components.url ?? URL(fileURLWithPath: "/")
    }
}

struct DeviceTile: View {
    @Environment(\.locale) private var locale
    let device: AppleDevice

    var body: some View {
        ResourceTile(title: device.rawValue, subtitle: AppLanguage.string("Getting started", locale: locale)) {
            ResourceFolderIcon(name: device.rawValue)
        }
    }
}

struct DeviceGettingStartedView: View {
    let device: AppleDevice

    var body: some View {
        List {
            Section {
                DeviceGuideIntroduction(device: device)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
            }
            Section {
                ForEach(WebGuideCatalog.guides(for: device)) { guide in
                    WebGuideRow(guide: guide)
                        .documentRowStyle()
                }
            } header: {
                Text("Start with the basics")
                    .textCase(nil)
            } footer: {
                Text("Guides open on Apple Support and require an internet connection. For a company-managed device, follow your organization's setup instructions.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(Color("WarmBackground"))
        .navigationTitle(device.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeviceGuideIntroduction: View {
    let device: AppleDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: device.symbol)
                .font(.largeTitle)
                .foregroundStyle(Color("AccentColor"))
                .accessibilityHidden(true)
            Text("Get to know your \(device.rawValue).")
                .font(.largeTitle.weight(.bold))
            Text("A few essentials to help you get set up and feel confident using your device.")
                .font(.body)
                .foregroundStyle(.secondary)
            Label("Guides from Apple Support", systemImage: "safari")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color("AccentColor"))
        }
        .padding(.vertical, 8)
    }
}

