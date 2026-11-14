import SwiftUI

struct SavedFormRow: View {
    let form: SavedForm

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: form.kind == .template ? "doc.on.doc" : "doc.text")
                .font(.title3.weight(.medium))
                .foregroundStyle(form.kind == .template ? AppStyle.accent : Color.green)
                .frame(width: 42, height: 48)
                .background((form.kind == .template ? AppStyle.accent : Color.green).opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(form.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(form.kind == .template ? "Use Template" : "Continue Editing")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(form.modifiedAt, format: .dateTime.month().day().year())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
