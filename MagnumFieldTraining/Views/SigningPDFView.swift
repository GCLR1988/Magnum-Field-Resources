import UIKit
import PDFKit

enum FormDrawingTool {
    case pen
    case eraser
}

/// Stores reversible edits separately from the template's annotations.
final class SigningPDFView: PDFView {
    var onHistoryChange: ((Int, Int) -> Void)?
    var drawingTool: FormDrawingTool = .pen {
        didSet { if oldValue != drawingTool { finishStroke() } }
    }
    var drawingEnabled = false {
        didSet {
            guard oldValue != drawingEnabled else { return }
            finishStroke()
            inkSurface.isHidden = !drawingEnabled
            if drawingEnabled { bringSubviewToFront(inkSurface) }
        }
    }

    private struct InkRecord {
        let page: PDFPage
        let annotation: PDFAnnotation
    }
    private struct InkChange {
        let record: InkRecord
        let added: Bool
    }
    private var undoHistory: [[InkChange]] = []
    private var redoHistory: [[InkChange]] = []
    private var sessionInk: [InkRecord] = []
    private var erasedInGesture: [InkChange] = []
    private var activePage: PDFPage?
    private var activeAnnotation: PDFAnnotation?
    private var activePath: UIBezierPath?

    private let inkSurface = FormInkSurface()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureInkSurface()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureInkSurface()
    }

    private func configureInkSurface() {
        inkSurface.owner = self
        inkSurface.backgroundColor = .clear
        inkSurface.isHidden = true
        inkSurface.isMultipleTouchEnabled = false
        inkSurface.accessibilityLabel = "Signature drawing area"
        addSubview(inkSurface)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        inkSurface.frame = bounds
        if drawingEnabled { bringSubviewToFront(inkSurface) }
    }

    func beginStroke(at location: CGPoint) {
        finishStroke()
        if drawingTool == .eraser {
            erase(at: location)
            return
        }
        guard let page = page(for: location, nearest: false) else { return }
        let point = convert(location, to: page)
        guard page.bounds(for: .cropBox).contains(point) else { return }
        activePage = page
        let path = UIBezierPath()
        path.move(to: point)
        path.addLine(to: CGPoint(x: point.x + 0.1, y: point.y))
        activePath = path
        redrawStroke()
    }

    func continueStroke(at location: CGPoint) {
        if drawingTool == .eraser {
            erase(at: location)
            return
        }
        guard let page = activePage, let path = activePath else { return }
        let point = convert(location, to: page)
        guard page.bounds(for: .cropBox).contains(point) else { return }
        path.addLine(to: point)
        redrawStroke()
    }

    private func redrawStroke() {
        guard let page = activePage, let path = activePath else { return }
        if let activeAnnotation { page.removeAnnotation(activeAnnotation) }
        // Tight bounds avoid intercepting other fields across the entire PDF page.
        let bounds = path.bounds.insetBy(dx: -2, dy: -2)
        let localPath = UIBezierPath(cgPath: path.cgPath)
        localPath.apply(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.color = .black
        let border = PDFBorder()
        border.lineWidth = 1.5
        annotation.border = border
        annotation.shouldPrint = true
        annotation.add(localPath)
        page.addAnnotation(annotation)
        activeAnnotation = annotation
        setNeedsDisplay()
    }

    private func erase(at location: CGPoint) {
        guard let page = page(for: location, nearest: false) else { return }
        let point = convert(location, to: page)
        let tolerance = 10 / max(scaleFactor, 0.1)
        // Only ink added during this session is erasable; form fields and printed content stay intact.
        for record in sessionInk.reversed() where record.annotation.page === page {
            let annotation = record.annotation
            guard annotation.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { continue }
            let localPoint = CGPoint(x: point.x - annotation.bounds.minX, y: point.y - annotation.bounds.minY)
            let hit = annotation.paths?.contains { path in
                path.cgPath.copy(strokingWithWidth: tolerance * 2, lineCap: .round,
                                 lineJoin: .round, miterLimit: 0).contains(localPoint)
            } ?? false
            if hit {
                page.removeAnnotation(annotation)
                erasedInGesture.append(InkChange(record: record, added: false))
            }
        }
        setNeedsDisplay()
    }

    func finishStroke() {
        var changes = erasedInGesture
        if let page = activePage, let annotation = activeAnnotation {
            let record = InkRecord(page: page, annotation: annotation)
            sessionInk.append(record)
            changes.append(InkChange(record: record, added: true))
        }
        activePage = nil
        activeAnnotation = nil
        activePath = nil
        erasedInGesture = []
        if !changes.isEmpty {
            undoHistory.append(changes)
            redoHistory.removeAll()
            publishHistory()
        }
    }

    func cancelStroke() {
        if let activeAnnotation { activeAnnotation.page?.removeAnnotation(activeAnnotation) }
        for change in erasedInGesture { change.record.page.addAnnotation(change.record.annotation) }
        activePage = nil
        activeAnnotation = nil
        activePath = nil
        erasedInGesture = []
        setNeedsDisplay()
    }

    func undoStroke() {
        finishStroke()
        guard let changes = undoHistory.popLast() else { return }
        for change in changes.reversed() { apply(change, forward: false) }
        redoHistory.append(changes)
        publishHistory()
    }

    func redoStroke() {
        finishStroke()
        guard let changes = redoHistory.popLast() else { return }
        for change in changes { apply(change, forward: true) }
        undoHistory.append(changes)
        publishHistory()
    }

    private func apply(_ change: InkChange, forward: Bool) {
        if change.added == forward {
            change.record.page.addAnnotation(change.record.annotation)
        } else {
            change.record.page.removeAnnotation(change.record.annotation)
        }
        setNeedsDisplay()
    }

    private func publishHistory() {
        onHistoryChange?(undoHistory.count, redoHistory.count)
    }

    func clearDrawingHistory() {
        cancelStroke()
        for record in sessionInk { record.annotation.page?.removeAnnotation(record.annotation) }
        sessionInk.removeAll()
        undoHistory.removeAll()
        redoHistory.removeAll()
        publishHistory()
    }
}

/// The overlay isolates drawing touches from PDF scrolling and interactive form fields.
private final class FormInkSurface: UIView {
    weak var owner: SigningPDFView?
    private weak var drawingTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard drawingTouch == nil, let touch = touches.first, let owner else { return }
        drawingTouch = touch
        owner.beginStroke(at: touch.location(in: owner))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = drawingTouch, touches.contains(touch), let owner else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            owner.continueStroke(at: sample.location(in: owner))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = drawingTouch, touches.contains(touch), let owner else { return }
        owner.continueStroke(at: touch.location(in: owner))
        owner.finishStroke()
        drawingTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        owner?.cancelStroke()
        drawingTouch = nil
    }
}
