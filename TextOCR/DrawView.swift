//
//  DrawView.swift
//  TextOCR
//
//  Created by rei8 on 2021/05/18.
//

import UIKit

class DrawView: UIView {

    var penColor = UIColor.black
    var penSize: CGFloat = 3.0
    var usePenForce = true
    var usePenShading = true
    var useFinger: Bool = false
    
    private lazy var frozenContext: CGContext = {
        var size = bounds.size
        size.width *= window!.screen.scale
        size.height *= window!.screen.scale
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let context: CGContext = CGContext(data: nil,
                                           width: Int(size.width),
                                           height: Int(size.height),
                                           bitsPerComponent: 8,
                                           bytesPerRow: 0,
                                           space: colorSpace,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let transform = CGAffineTransform(scaleX: window!.screen.scale, y: window!.screen.scale)
        context.concatenate(transform)
        return context
    }()
    private var frozenImage: CGImage?

    var snapshotImage: UIImage? {
        guard let frozenImage = frozenImage else {
            return nil
        }
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image(actions: { rendererContext in
            rendererContext.cgContext.setFillColor(UIColor.white.cgColor)
            rendererContext.cgContext.fill(.infinite)
            rendererContext.cgContext.draw(frozenImage, in: bounds)
        })
    }

    // Holds a map of `UITouch` objects to `Line` objects whose touch has not ended yet.
    private var activeLines: [UITouch: Line] = [:]
    
    // Holds a map of `UITouch` objects to `Line` objects whose touch has ended but still has points awaiting updates.
    private var pendingLines: [UITouch: Line] = [:]
    
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()!
        
        if let frozenImage = frozenImage {
            context.draw(frozenImage, in: self.bounds)
        }

        for (_,obj) in self.activeLines {
            obj.drawInContext(context)
        }
        for (_,obj) in self.pendingLines {
            obj.drawInContext(context)
        }
    }

    // MARK: Actions
    func clear(keepActive: Bool = false) {
        frozenImage = nil
        frozenContext.clear(bounds)
        activeLines.removeAll()
        pendingLines.removeAll()
        setNeedsDisplay()
    }

    func drawText(str: String) {
        UIGraphicsPushContext(frozenContext)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (str as NSString).draw(in: bounds, withAttributes: [
            .font: UIFont.systemFont(ofSize: 200),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph,
        ])
        UIGraphicsPopContext()
        frozenImage = frozenContext.makeImage()
        setNeedsDisplay()
    }
    
    // MARK: Convenience
    func drawTouches(_ touches: Set<UITouch>, withEvent event: UIEvent?) {
        var updateRect = CGRect.null

        for touch in touches {
            // Retrieve a line from `activeLines`. If no line exists, create one.
            let line: Line = activeLines[touch] ?? addActiveLineForTouch(touch)

            /*
                Remove prior predicted points and update the `updateRect` based on the removals. The touches
                used to create these points are predictions provided to offer additional data. They are stale
                by the time of the next event for this touch.
            */
            updateRect = updateRect.union(line.removePointsWithType(.predicted))

            /*
                Incorporate coalesced touch data. The data in the last touch in the returned array will match
                the data of the touch supplied to `coalescedTouchesForTouch(_:)`
            */
            let coalescedTouches = event?.coalescedTouches(for: touch) ?? []
            let coalescedRect = addPointsOfType(.coalesced, for: coalescedTouches, to: line, in: updateRect)
            updateRect = updateRect.union(coalescedRect)

            /*
                Incorporate predicted touch data. This sample draws predicted touches differently; however,
                you may want to use them as inputs to smoothing algorithms rather than directly drawing them.
                Points derived from predicted touches should be removed from the line at the next event for
                this touch.
            */
            let predictedTouches = event?.predictedTouches(for: touch) ?? []
            let predictedRect = addPointsOfType(.predicted, for: predictedTouches, to: line, in: updateRect)
            updateRect = updateRect.union(predictedRect)
        }

        setNeedsDisplay(updateRect)
    }

    private func addActiveLineForTouch(_ touch: UITouch) -> Line {
        let newLine = Line(color: penColor, width: penSize, force: usePenForce, shading: usePenShading)

        activeLines[touch] = newLine

        return newLine
    }

    private func addPointsOfType(_ type: LinePoint.PointType, for touches: [UITouch], to line: Line, in updateRect: CGRect) -> CGRect {
        var accumulatedRect = CGRect.null
        var type = type

        for (idx, touch) in touches.enumerated() {
            let isPencil = touch.type == .pencil

            // The visualization displays non-`.pencil` touches differently.
            if !isPencil {
                type.formUnion(.finger)
            }

            // Touches with estimated properties require updates; add this information to the `PointType`.
            if !touch.estimatedProperties.isEmpty {
                type.formUnion(.needsUpdate)
            }

            // The last touch in a set of `.coalesced` touches is the originating touch. Track it differently.
            if type.contains(.coalesced) && idx == touches.count - 1 {
                type.subtract(.coalesced)
                type.formUnion(.standard)
            }

            let touchRect = line.addPointOfType(type, for: touch, in: self)
            accumulatedRect = accumulatedRect.union(touchRect)
        }

        return updateRect.union(accumulatedRect)
    }

    func endTouches(_ touches: Set<UITouch>, cancel: Bool) {
        var updateRect = CGRect.null

        for touch in touches {
            // Skip over touches that do not correspond to an active line.
            guard let line = activeLines[touch] else { continue }

            // If this is a touch cancellation, cancel the associated line.
            if cancel { updateRect = updateRect.union(line.cancel()) }

            // If the line is complete (no points needing updates) or updating isn't enabled, move the line to the `frozenImage`.
            if line.isComplete {
                finishLine(line)
            }
            // Otherwise, add the line to our map of touches to lines pending update.
            else {
                pendingLines[touch] = line
            }

            // This touch is ending, remove the line corresponding to it from `activeLines`.
            activeLines.removeValue(forKey: touch)
        }

        setNeedsDisplay(updateRect)
    }

    func updateEstimatedPropertiesForTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            var isPending = false

            // Look to retrieve a line from `activeLines`. If no line exists, look it up in `pendingLines`.
            let possibleLine: Line? = activeLines[touch] ?? {
                let pendingLine = pendingLines[touch]
                isPending = pendingLine != nil
                return pendingLine
            }()

            // If no line is related to the touch, return as there is no additional work to do.
            guard let line = possibleLine else { return }

            switch line.updateWithTouch(touch) {
                case (true, let updateRect):
                    setNeedsDisplay(updateRect)
                default:
                    ()
            }

            // If this update updated the last point requiring an update, move the line to the `frozenImage`.
            if isPending && line.isComplete {
                finishLine(line)
                pendingLines.removeValue(forKey: touch)
            }
        }
    }

    private func finishLine(_ line: Line) {
        // Have the line draw any remaining segments into the `frozenContext`. All should be fixed now.
        line.finalizePoints()

        // Save to database
        line.drawFrozenContext(in: frozenContext)
        frozenImage = frozenContext.makeImage()
        setNeedsDisplay()
    }

    // MARK: Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        if !useFinger {
            drawTouches(touches.filter { $0.type == .pencil }, withEvent: event)
        }
        else {
            drawTouches(touches, withEvent: event)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        if !useFinger {
            drawTouches(touches.filter { $0.type == .pencil }, withEvent: event)
        }
        else {
            drawTouches(touches, withEvent: event)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        if !useFinger {
            drawTouches(touches.filter { $0.type == .pencil }, withEvent: event)
            endTouches(touches.filter { $0.type == .pencil }, cancel: false)
        }
        else {
            drawTouches(touches, withEvent: event)
            endTouches(touches, cancel: false)
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
    
        if !useFinger {
            endTouches(touches.filter { $0.type == .pencil }, cancel: true)
        }
        else {
            endTouches(touches, cancel: true)
        }
    }
    
    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        super.touchesEstimatedPropertiesUpdated(touches)
        
        updateEstimatedPropertiesForTouches(touches)
    }

}
