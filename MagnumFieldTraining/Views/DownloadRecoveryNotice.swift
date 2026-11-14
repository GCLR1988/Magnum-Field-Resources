import SwiftUI

/// A floating progress control that does not reserve a full-width banner.
struct DownloadProgressIndicator: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @State private var showsProgress = false

    var body: some View {
        Group {
            if !catalogStore.activeDownloads.isEmpty {
                let progress = catalogStore.downloadProgress
                let fraction = progress.total > 0
                    ? min(1, max(0, Double(progress.completed) / Double(progress.total))) : 0
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        showsProgress = true
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(AppStyle.accent.opacity(0.15), lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: fraction)
                                .stroke(AppStyle.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppStyle.accent)
                        }
                        .frame(width: 32, height: 32)
                        .padding(8)
                        .background(AppStyle.surface, in: Circle())
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Downloading files")
                    .accessibilityValue(Text("\(progress.completed) of \(progress.total)"))
                    .popover(isPresented: $showsProgress) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Downloading files")
                                .font(.headline)
                            Text("\(progress.completed) of \(progress.total)")
                                .font(.subheadline.monospacedDigit())
                            ProgressView(value: fraction)
                                .tint(AppStyle.accent)
                        }
                        .padding()
                        .presentationCompactAdaptation(.popover)
                    }
                }
                .padding(.trailing, AppStyle.inset)
                .padding(.vertical, 6)
            }
        }
        .onChange(of: catalogStore.activeDownloads.isEmpty) { _, isEmpty in
            if isEmpty { showsProgress = false }
        }
    }
}

struct DownloadRecoveryNotice: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if catalogStore.activeDownloads.isEmpty && !catalogStore.failedDownloads.isEmpty {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Label("\(catalogStore.failedDownloads.count) downloads need attention", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if catalogStore.isDownloadingPending {
                    ProgressView()
                        .accessibilityLabel("Retrying downloads")
                } else {
                    Button("Retry") {
                        Task { await catalogStore.retryFailedDownloads() }
                    }
                    .buttonStyle(.bordered)
                    .tint(AppStyle.accent)
                    .frame(minHeight: 44)
                    .disabled(catalogStore.isClearingCache)
                }
            }
            .padding(AppStyle.inset)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .background(AppStyle.surface)
        }
    }
}
