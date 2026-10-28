import SwiftUI

struct DownloadRecoveryNotice: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if !catalogStore.activeDownloads.isEmpty {
            let progress = catalogStore.downloadProgress
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))
            VStack(alignment: .leading, spacing: 8) {
                layout {
                    Label("Downloading files", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(progress.completed) of \(progress.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if progress.total > 0 {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                        .tint(AppStyle.accent)
                } else {
                    ProgressView().tint(AppStyle.accent)
                }
            }
            .padding(AppStyle.inset)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .background(AppStyle.surface)
        } else if !catalogStore.failedDownloads.isEmpty {
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
