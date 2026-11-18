import SwiftUI
import PhotosUI
import UIKit
import PencilKit

private enum PhotoShapeColor: String, CaseIterable, Identifiable {
    case yellow, red, orange, green, blue, purple, white, black

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .yellow: "Yellow"
        case .red: "Red"
        case .orange: "Orange"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .white: "White"
        case .black: "Black"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .yellow: .systemYellow
        case .red: .systemRed
        case .orange: .systemOrange
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .white: .white
        case .black: .black
        }
    }
}

private struct PhotoFieldMark: Identifiable {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint?
    let text: String
    var kind: String = "pin"
    var color: PhotoShapeColor = .yellow
}

/// Coordinates are fractions of the photo, so preview and shared output stay aligned.
struct PhotoFieldToolsView: View {
    let source: UIImage
    let isSharing: Bool
    let onShare: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tool: Tool = .draw
    @State private var shapeColor: PhotoShapeColor = .yellow
    @State private var drawing = PKDrawing()
    private enum Edit {
        case drawing(PKDrawing)
        case marks([PhotoFieldMark])
    }
    @State private var undoEdits: [Edit] = []
    @State private var redoEdits: [Edit] = []
    @State private var marks: [PhotoFieldMark] = []
    @State private var afterPhoto: UIImage?
    @State private var afterSelection: PhotosPickerItem?
    @State private var showAfterPicker = false
    @State private var loading = false
    @State private var error: String?
    @State private var showLabels = false
    @State private var job = ""
    @State private var location = ""
    @State private var author = ""
    @State private var includeDate = false
    @State private var date = Date()
    @State private var pendingStart: CGPoint?
    @State private var pendingEnd: CGPoint?
    @State private var annotationText = ""
    @State private var showTextEntry = false
    @GestureState private var drag: DragGesture.Value?
    @State private var showLayoutConfirmation = false

    private enum Tool: String, CaseIterable, Identifiable {
        case draw, pin, text, rectangle, ellipse, arrow
        var id: Self { self }
        var symbol: String {
            switch self {
            case .draw: "pencil.tip"
            case .pin: "mappin.circle"
            case .text: "textformat"
            case .rectangle: "rectangle"
            case .ellipse: "circle"
            case .arrow: "arrow.up.right"
            }
        }
        var annotationName: String {
            switch self {
            case .rectangle: AppLanguage.string("Rectangle")
            case .ellipse: AppLanguage.string("Circle")
            default: AppLanguage.string("Arrow")
            }
        }
        var title: LocalizedStringKey {
            switch self {
            case .draw: "Draw"
            case .text: "Text"
            case .rectangle: "Rectangle"
            case .ellipse: "Circle"
            case .arrow: "Arrow"
            case .pin: "Numbered Pin"
            }
        }
    }

    private var base: UIImage { PhotoFieldRenderer.layout(source, after: afterPhoto) }
    private var labelLines: [String] {
        var lines: [String] = []
        if !job.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append(AppLanguage.string("Job: \(job)")) }
        if !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append(AppLanguage.string("Location: \(location)")) }
        if !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append(AppLanguage.string("By: \(author)")) }
        if includeDate { lines.append(date.formatted(date: .abbreviated, time: .omitted)) }
        return lines
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 8)], spacing: 8) {
                        ForEach(Tool.allCases) { option in
                            Button {
                                tool = option
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: option.symbol)
                                        .font(.title2)
                                        .accessibilityHidden(true)
                                    Text(option.title)
                                        .font(.caption.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .padding(8)
                                .foregroundStyle(tool == option ? Color.accentColor : Color.primary)
                                .background(
                                    tool == option ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(tool == option ? Color.accentColor : Color.clear, lineWidth: 2)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.title)
                            .accessibilityAddTraits(tool == option ? .isSelected : [])
                        }
                    }
                    if tool == .rectangle || tool == .ellipse {
                        shapeColorChoices
                    }
                    Text(instructions)
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Pinch to zoom. Use two fingers to move around the photo.")
                        .font(.caption).foregroundStyle(.secondary)
                    photoCanvas
                        .allowsHitTesting(!loading)
                    HStack {
                        Button("Undo", systemImage: "arrow.uturn.backward") {
                            guard let edit = undoEdits.popLast() else { return }
                            redoEdits.append(apply(edit))
                        }
                        .disabled(undoEdits.isEmpty || loading)
                        Button("Redo", systemImage: "arrow.uturn.forward") {
                            guard let edit = redoEdits.popLast() else { return }
                            undoEdits.append(apply(edit))
                        }
                        .disabled(redoEdits.isEmpty || loading)
                        Spacer()
                        Button("Photo Labels", systemImage: "text.below.photo") { showLabels = true }
                    }
                    .buttonStyle(.bordered)
                    if !labelLines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(labelLines.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.subheadline)
                            }
                        }
                    }
                    comparisonControls
                    if loading { ProgressView("Loading after photo…") }
                    if let error { Text(error).foregroundStyle(.red) }
                    if !marks.isEmpty {
                        DisclosureGroup("Remove Annotations") {
                            ForEach(marks) { mark in
                                HStack {
                                    Text(mark.kind == "pin" ? AppLanguage.string("Pin \(mark.text)") : mark.text)
                                    Spacer()
                                    Button("Remove", systemImage: "trash") {
                                        record(.marks(marks))
                                        marks.removeAll { $0.id == mark.id }
                                    }
                                    .labelStyle(.iconOnly)
                                    .accessibilityLabel(AppLanguage.string("Remove \(mark.text)"))
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                    Text("Use Draw for pens, highlighter, eraser, and ruler. Share includes all your edits and photo labels.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(AppStyle.background)
            .navigationTitle("Photo Markup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward") {
                        guard let edit = undoEdits.popLast() else { return }
                        redoEdits.append(apply(edit))
                    }
                    .disabled(undoEdits.isEmpty || loading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share", systemImage: "square.and.arrow.up") {
                        onShare(PhotoFieldRenderer.annotate(base, marks: marks, labels: labelLines, drawing: drawing))
                    }
                    .disabled(loading)
                }
            }
            .sheet(isPresented: $showLabels) { labelsForm }
            .alert("Add Text", isPresented: $showTextEntry) {
                TextField("Your note", text: $annotationText)
                Button("Cancel", role: .cancel) { clearPending() }
                Button("Add") {
                    if let start = pendingStart {
                        record(.marks(marks))
                        marks.append(PhotoFieldMark(start: start, end: pendingEnd,
                                                   text: annotationText.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   kind: "text"))
                    }
                    clearPending()
                }
                .disabled(annotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Tap the photo to position your note.")
            }
            .confirmationDialog("Changing the layout removes annotations and drawings so they do not point to the wrong location.",
                                isPresented: $showLayoutConfirmation, titleVisibility: .visible) {
                Button("Use Single Photo", role: .destructive) {
                    afterPhoto = nil
                    resetAnnotations()
                }
            }
            .task(id: afterSelection) {
                guard let selection = afterSelection else { return }
                loading = true
                error = nil
                defer { loading = false; afterSelection = nil }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                    try Task.checkCancellation()
                    afterPhoto = PhotoFieldRenderer.layout(image, after: nil)
                    // Existing coordinates refer to the previous layout.
                    resetAnnotations()
                } catch is CancellationError {
                } catch {
                    self.error = AppLanguage.string("Couldn't load the after photo. Please try again.")
                }
            }
        }
    }

    private var shapeColorChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shape Color").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                ForEach(PhotoShapeColor.allCases) { option in
                    Button {
                        shapeColor = option
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color(uiColor: option.uiColor))
                                .frame(width: 28, height: 28)
                                .overlay { Circle().strokeBorder(.gray, lineWidth: 1) }
                                .overlay {
                                    if shapeColor == option {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(option == .black || option == .blue || option == .purple ? .white : .black)
                                    }
                                }
                            Text(option.title)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .padding(4)
                        .background(shapeColor == option ? Color.accentColor.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(shapeColor == option ? .isSelected : [])
                }
            }
        }
    }

    private var instructions: LocalizedStringKey {
        switch tool {
        case .draw: "Draw on the photo. Use the drawing palette to choose a pen, color, or eraser."
        case .pin: "Tap the photo to add the next numbered pin."
        case .text: "Tap the photo where you want your text."
        case .rectangle: "Touch one corner, then drag to the opposite corner. The outline follows your finger."
        case .ellipse: "Touch one edge of the circle, then drag to the opposite edge to size it."
        case .arrow: "Drag from the tail toward the arrowhead."
        }
    }

    private func record(_ edit: Edit) {
        undoEdits.append(edit)
        redoEdits = []
    }

    private func apply(_ edit: Edit) -> Edit {
        switch edit {
        case .drawing(let previous):
            let inverse = Edit.drawing(drawing)
            drawing = previous
            return inverse
        case .marks(let previous):
            let inverse = Edit.marks(marks)
            marks = previous
            return inverse
        }
    }

    private func resetAnnotations() {
        marks = []
        drawing = PKDrawing()
        undoEdits = []
        redoEdits = []
    }

    private var photoCanvas: some View {
        let image = base
        return ZoomablePhotoCanvas {
            GeometryReader { geometry in
            ZStack {
                Image(uiImage: PhotoFieldRenderer.annotate(image, marks: marks, labels: []))
                    .resizable()
                    .scaledToFit()
                PhotoDrawingCanvas(drawing: $drawing, imageSize: image.size, enabled: tool == .draw && !showLabels && !showTextEntry && !showAfterPicker && !isSharing && !loading) { previous in
                    record(.drawing(previous))
                }
                .allowsHitTesting(tool == .draw)
                // Keep the gesture layer mounted when switching from PencilKit to shapes.
                Group {
                    Color.clear
                        .contentShape(Rectangle())
                        .overlay {
                            if let drag, tool != .pin && tool != .text {
                                Path { path in
                                    let start = normalized(drag.startLocation, in: geometry.size)
                                    let end = normalized(drag.location, in: geometry.size)
                                    let first = CGPoint(x: start.x * geometry.size.width, y: start.y * geometry.size.height)
                                    let last = CGPoint(x: end.x * geometry.size.width, y: end.y * geometry.size.height)
                                    if tool == .rectangle || tool == .ellipse {
                                        let rect = PhotoFieldRenderer.shapeRect(from: first, to: last, circle: tool == .ellipse)
                                        if tool == .ellipse { path.addEllipse(in: rect) }
                                        else { path.addRect(rect) }
                                    } else {
                                        path.move(to: first)
                                        path.addLine(to: last)
                                    }
                                }
                                .stroke(tool == .rectangle || tool == .ellipse ? Color(uiColor: shapeColor.uiColor) : .yellow,
                                        style: StrokeStyle(lineWidth: 3, dash: [6]))
                            }
                        }
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0)
                                .updating($drag) { value, state, _ in state = value }
                                .onEnded { value in
                                    guard tool != .draw else { return }
                                    let start = normalized(value.startLocation, in: geometry.size)
                                    let end = normalized(value.location, in: geometry.size)
                                    if tool == .pin {
                                        let next = (marks.filter { $0.kind == "pin" }.compactMap { Int($0.text) }.max() ?? 0) + 1
                                        record(.marks(marks))
                                        marks.append(PhotoFieldMark(start: end, end: nil, text: String(next)))
                                    } else if tool == .text {
                                        pendingStart = end
                                        pendingEnd = nil
                                        annotationText = ""
                                        showTextEntry = true
                                    } else if hypot(value.translation.width, value.translation.height) > 12 {
                                        record(.marks(marks))
                                        marks.append(PhotoFieldMark(start: start, end: end,
                                            text: tool.annotationName, kind: tool.rawValue,
                                            color: tool == .rectangle || tool == .ellipse ? shapeColor : .yellow))
                                    }
                                }
                        )
                }
                .allowsHitTesting(tool != .draw)
            }
            .clipped()
            .accessibilityLabel("Photo annotation canvas")
            }
        }
        .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
    }

    private var comparisonControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Before & After").font(.headline)
            Text(afterPhoto == nil ? "Your current photo is Before. Choose a second photo for After." : "Before is on the left. After is on the right.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                showAfterPicker = true
            } label: {
                Label(afterPhoto == nil ? "Choose After Photo" : "Replace After Photo", systemImage: "rectangle.split.2x1")
            }
            .disabled(loading || !marks.isEmpty || !drawing.strokes.isEmpty)
            .photosPicker(isPresented: $showAfterPicker, selection: $afterSelection, matching: .images)
            if !marks.isEmpty || !drawing.strokes.isEmpty {
                Text("Remove annotations and drawings before changing photos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if afterPhoto != nil {
                Button("Use Single Photo") {
                    if marks.isEmpty && drawing.strokes.isEmpty { afterPhoto = nil } else { showLayoutConfirmation = true }
                }
                .disabled(loading)
            }
        }
    }

    private var labelsForm: some View {
        NavigationStack {
            Form {
                Section("Photo Labels") {
                    TextField("Job name", text: $job)
                    TextField("Location", text: $location)
                    TextField("Your name", text: $author)
                    Toggle("Include date", isOn: $includeDate)
                    if includeDate { DatePicker("Date", selection: $date, displayedComponents: .date) }
                }
                Section {
                    Text("Labels appear below the photo in the shared image.")
                }
            }
            .navigationTitle("Photo Labels")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showLabels = false } }
            }
        }
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x / max(1, size.width))),
                y: min(1, max(0, point.y / max(1, size.height))))
    }

    private func clearPending() {
        pendingStart = nil
        pendingEnd = nil
        annotationText = ""
    }
}

@MainActor
private enum PhotoFieldRenderer {
    static func layout(_ before: UIImage, after: UIImage?) -> UIImage {
        let size: CGSize
        if after != nil {
            size = CGSize(width: 2000, height: 1300)
        } else {
            let scale = min(1, 2000 / max(before.size.width, before.size.height))
            size = CGSize(width: max(1, before.size.width * scale), height: max(1, before.size.height * scale))
        }
        return renderer(size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if let after {
                drawFit(before, in: CGRect(x: 20, y: 100, width: 970, height: 1180))
                drawFit(after, in: CGRect(x: 1010, y: 100, width: 970, height: 1180))
                drawText(AppLanguage.string("Before"), rect: CGRect(x: 20, y: 20, width: 970, height: 65), size: 44)
                drawText(AppLanguage.string("After"), rect: CGRect(x: 1010, y: 20, width: 970, height: 65), size: 44)
            } else {
                before.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }

    // A circle's initial touch and current touch are opposite ends of its diameter.
    static func shapeRect(from start: CGPoint, to end: CGPoint, circle: Bool) -> CGRect {
        if circle {
            let diameter = hypot(end.x - start.x, end.y - start.y)
            return CGRect(x: (start.x + end.x - diameter) / 2,
                          y: (start.y + end.y - diameter) / 2,
                          width: diameter, height: diameter)
        }
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                      width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    static func annotate(_ image: UIImage, marks: [PhotoFieldMark], labels: [String], drawing: PKDrawing = PKDrawing()) -> UIImage {
        let unit = max(image.size.width, image.size.height) / 1000
        let fontSize = 24 * unit
        let padding = 16 * unit
        let labelWidth = image.size.width - padding * 2
        let heights = labels.map { text in
            (text as NSString).boundingRect(with: CGSize(width: labelWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: UIFont.systemFont(ofSize: fontSize)], context: nil).height + padding
        }
        let footer = labels.isEmpty ? 0 : heights.reduce(padding, +)
        return renderer(CGSize(width: image.size.width, height: image.size.height + footer)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height + footer))
            image.draw(at: .zero)
            for mark in marks {
                let start = CGPoint(x: mark.start.x * image.size.width, y: mark.start.y * image.size.height)
                if mark.kind == "text" {
                    let width = min(image.size.width * 0.8, max(160 * unit, CGFloat(mark.text.count) * 14 * unit))
                    let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: fontSize)]
                    let height = (mark.text as NSString).boundingRect(
                        with: CGSize(width: width - padding, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height + padding
                    let rect = CGRect(x: min(start.x, image.size.width - width),
                                      y: max(0, min(start.y, image.size.height - height)), width: width, height: height)
                    UIColor.white.setFill()
                    UIBezierPath(roundedRect: rect, cornerRadius: 6 * unit).fill()
                    (mark.text as NSString).draw(in: rect.insetBy(dx: padding / 2, dy: padding / 2),
                        withAttributes: [.font: UIFont.boldSystemFont(ofSize: fontSize), .foregroundColor: UIColor.black])
                } else if let endpoint = mark.end {
                    let end = CGPoint(x: endpoint.x * image.size.width, y: endpoint.y * image.size.height)
                    if mark.kind == "rectangle" || mark.kind == "ellipse" {
                        let rect = shapeRect(from: start, to: end, circle: mark.kind == "ellipse")
                        let shape = mark.kind == "ellipse" ? UIBezierPath(ovalIn: rect) : UIBezierPath(rect: rect)
                        (mark.color == .black ? UIColor.white : UIColor.black).setStroke()
                        shape.lineWidth = 7 * unit
                        shape.stroke()
                        mark.color.uiColor.setStroke()
                        shape.lineWidth = 4 * unit
                        shape.stroke()
                        continue
                    }
                    let angle = atan2(end.y - start.y, end.x - start.x)
                    let path = UIBezierPath()
                    path.move(to: start)
                    path.addLine(to: end)
                    let heads = mark.kind == "arrow" ? [(end, angle + .pi)] : [(start, angle), (end, angle + .pi)]
                    for (point, direction) in heads {
                        for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                            path.move(to: point)
                            path.addLine(to: CGPoint(x: point.x + cos(direction + offset) * 20 * unit,
                                                    y: point.y + sin(direction + offset) * 20 * unit))
                        }
                    }
                    UIColor.black.setStroke()
                    path.lineWidth = 7 * unit
                    path.stroke()
                    UIColor.systemYellow.setStroke()
                    path.lineWidth = 4 * unit
                    path.stroke()
                    if mark.kind == "arrow" { continue }
                    let textSize = (mark.text as NSString).size(withAttributes: [.font: UIFont.boldSystemFont(ofSize: fontSize)])
                    let width = min(image.size.width, textSize.width + padding * 2)
                    let rect = CGRect(x: min(max(0, (start.x + end.x - width) / 2), image.size.width - width),
                                      y: min(max(0, (start.y + end.y) / 2 - 20 * unit), max(0, image.size.height - 44 * unit)),
                                      width: width, height: 44 * unit)
                    UIColor.white.setFill()
                    UIBezierPath(roundedRect: rect, cornerRadius: 6 * unit).fill()
                    drawText(mark.text, rect: rect.insetBy(dx: 5 * unit, dy: 6 * unit), size: fontSize)
                } else {
                    let radius = 22 * unit
                    let center = CGPoint(x: min(max(radius, start.x), image.size.width - radius),
                                         y: min(max(radius, start.y), image.size.height - radius))
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    UIColor.systemRed.setFill()
                    let circle = UIBezierPath(ovalIn: rect)
                    circle.fill()
                    UIColor.white.setStroke()
                    circle.lineWidth = 3 * unit
                    circle.stroke()
                    drawText(mark.text, rect: rect.insetBy(dx: 2 * unit, dy: 6 * unit), size: fontSize, color: .white)
                }
            }
            drawing.image(from: CGRect(origin: .zero, size: image.size), scale: 1)
                .draw(in: CGRect(origin: .zero, size: image.size))
            var y = image.size.height + padding
            for (line, height) in zip(labels, heights) {
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize), .foregroundColor: UIColor.black]
                (line as NSString).draw(in: CGRect(x: padding, y: y, width: labelWidth, height: height), withAttributes: attributes)
                y += height
            }
        }
    }

    private static func renderer(_ size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    private static func drawFit(_ image: UIImage, in rect: CGRect) {
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }

    private static func drawText(_ text: String, rect: CGRect, size: CGFloat, color: UIColor = .black) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: UIFont.boldSystemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: style
        ])
    }
}


/// Zoom the photo and every annotation together without changing their stored coordinates.
private struct ZoomablePhotoCanvas<Content: View>: UIViewControllerRepresentable {
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> ZoomController {
        ZoomController(rootView: content())
    }

    func updateUIViewController(_ controller: ZoomController, context: Context) {
        controller.host.rootView = content()
    }

    final class ZoomController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        let host: UIHostingController<Content>
        private let scroll = UIScrollView()
        private let zoomContent = UIView()
        private var canvasSize = CGSize.zero
        private var initialZoom: CGFloat = 1
        private var pinchAnchor = CGPoint.zero
        private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))

        init(rootView: Content) {
            host = UIHostingController(rootView: rootView)
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            scroll.backgroundColor = .clear
            scroll.delegate = self
            scroll.minimumZoomScale = 1
            scroll.maximumZoomScale = 5
            scroll.bouncesZoom = false
            scroll.contentInsetAdjustmentBehavior = .never
            scroll.showsHorizontalScrollIndicator = false
            scroll.showsVerticalScrollIndicator = false
            // One finger remains available for drawing and placing annotations.
            scroll.panGestureRecognizer.minimumNumberOfTouches = 2
            scroll.delaysContentTouches = false
            scroll.canCancelContentTouches = true
            // Recognize pinches alongside the markup layer's single-finger gestures.
            scroll.pinchGestureRecognizer?.isEnabled = false
            pinch.delegate = self
            scroll.addGestureRecognizer(pinch)
            view.addSubview(scroll)
            scroll.addSubview(zoomContent)
            addChild(host)
            host.view.backgroundColor = .clear
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            zoomContent.addSubview(host.view)
            host.didMove(toParent: self)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            scroll.frame = view.bounds
            guard canvasSize != view.bounds.size else { return }
            canvasSize = view.bounds.size
            // Reset only when the viewport changes, never when an annotation changes.
            scroll.setZoomScale(1, animated: false)
            zoomContent.frame = CGRect(origin: .zero, size: canvasSize)
            host.view.frame = zoomContent.bounds
            scroll.contentSize = canvasSize
            scroll.contentOffset = .zero
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            // Hosting updates must not change the view that owns the zoom transform.
            zoomContent
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer === pinch
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                initialZoom = scroll.zoomScale
                pinchAnchor = recognizer.location(in: zoomContent)
                // Cancel a single-finger annotation when the user starts pinching.
                host.view.isUserInteractionEnabled = false
                scroll.panGestureRecognizer.isEnabled = false
            case .changed:
                let location = recognizer.location(in: view)
                let scale = min(scroll.maximumZoomScale, max(scroll.minimumZoomScale,
                                                             initialZoom * recognizer.scale))
                scroll.setZoomScale(scale, animated: false)
                let maximumX = max(0, canvasSize.width * scale - scroll.bounds.width)
                let maximumY = max(0, canvasSize.height * scale - scroll.bounds.height)
                scroll.contentOffset = CGPoint(
                    x: min(maximumX, max(0, pinchAnchor.x * scale - location.x)),
                    y: min(maximumY, max(0, pinchAnchor.y * scale - location.y))
                )
            case .ended, .cancelled, .failed:
                host.view.isUserInteractionEnabled = true
                scroll.panGestureRecognizer.isEnabled = true
            default:
                break
            }
        }
    }
}

/// Store strokes in image coordinates, independent of the editor's screen size.
private struct PhotoDrawingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let imageSize: CGSize
    let enabled: Bool
    let onEdit: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> DrawingSurface {
        let surface = DrawingSurface()
        context.coordinator.surface = surface
        surface.canvas.delegate = context.coordinator
        surface.onLayout = { [weak coordinator = context.coordinator] in coordinator?.apply() }
        context.coordinator.apply()
        return surface
    }

    func updateUIView(_ surface: DrawingSurface, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply()
    }

    static func dismantleUIView(_ surface: DrawingSurface, coordinator: Coordinator) {
        surface.picker.setVisible(false, forFirstResponder: surface.canvas)
        surface.picker.removeObserver(surface.canvas)
        surface.canvas.resignFirstResponder()
    }

    final class DrawingSurface: UIView {
        let canvas = PKCanvasView()
        let picker = PKToolPicker()
        var onLayout: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.drawingPolicy = .anyInput
            canvas.isScrollEnabled = false
            canvas.contentInsetAdjustmentBehavior = .never
            addSubview(canvas)
            picker.addObserver(canvas)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            canvas.frame = bounds
            onLayout?()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onLayout?()
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PhotoDrawingCanvas
        weak var surface: DrawingSurface?
        private var applying = false
        private var displayedScale: CGFloat = 0
        private var displayedData: Data?
        private var displayedCanvasData: Data?
        private var beforeStroke: PKDrawing?
        private var paletteVisible = false

        init(_ parent: PhotoDrawingCanvas) { self.parent = parent }

        func apply() {
            guard let surface, surface.bounds.width > 0 else { return }
            let scale = surface.bounds.width / max(1, parent.imageSize.width)
            let data = parent.drawing.dataRepresentation()
            if displayedScale != scale || displayedData != data {
                applying = true
                surface.canvas.drawing = parent.drawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
                displayedScale = scale
                displayedData = data
                displayedCanvasData = surface.canvas.drawing.dataRepresentation()
                applying = false
            }
            surface.canvas.isUserInteractionEnabled = parent.enabled
            if surface.window != nil && paletteVisible != parent.enabled {
                paletteVisible = parent.enabled
                surface.picker.setVisible(parent.enabled, forFirstResponder: surface.canvas)
                if parent.enabled {
                    if !surface.canvas.isFirstResponder { surface.canvas.becomeFirstResponder() }
                } else {
                    surface.canvas.resignFirstResponder()
                }
            }
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            beforeStroke = parent.drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !applying, displayedScale > 0 else { return }
            let canvasData = canvasView.drawing.dataRepresentation()
            // Ignore delayed callbacks from assigning a drawing during app Undo/Redo.
            guard canvasData != displayedCanvasData else { return }
            displayedCanvasData = canvasData
            let canonical = canvasView.drawing.transformed(using: CGAffineTransform(
                scaleX: 1 / displayedScale, y: 1 / displayedScale))
            let data = canonical.dataRepresentation()
            guard data != displayedData else { return }
            // PencilKit can deliver the final drawing after the tool-ended callback.
            // Record the edit when its contents arrive, including palette undo/redo.
            let previous = beforeStroke ?? parent.drawing
            beforeStroke = nil
            displayedData = data
            parent.onEdit(previous)
            parent.drawing = canonical
        }
    }
}
