import Foundation

/// Programs are discovered automatically from the top-level folders inside
/// this app's dedicated Dropbox folder -- create a new folder there (e.g.
/// "Milwaukee Tool") and it shows up as a new program the next time the
/// app syncs (on launch or pull-to-refresh). No code change or rebuild
/// needed. Each folder's PDFs and videos (.pdf, .mp4, .mov, .m4v) become
/// that program's walkthroughs.
///
/// Use this file only for `.local` programs -- ones bundled directly into
/// the app instead of synced from Dropbox (fully offline, but needs a
/// rebuild to change). Leave the list empty if every program should come
/// from Dropbox. Example:
///
/// ```swift
/// static let programs: [Program] = [
///     Program(name: "Emergency Contacts", source: .local([
///         WalkthroughResource(title: "Site Safety Plan", location: .bundled(filename: "Site Safety Plan.pdf")),
///     ])),
/// ]
/// ```
enum ProgramData {
    static let programs: [Program] = []
}
