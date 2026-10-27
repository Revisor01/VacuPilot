import SwiftUI
import UIKit

// MARK: - Interactive Map View
struct InteractiveMapView: View {
    let map: RobotMap
    let segments: [Segment]
    @Binding var selectedSegmentIds: [String]
    let viewSize: CGSize
    var staticLayerImage: CGImage?

    // Drawing overlays
    var drawnZones: [CleaningZone] = []
    var drawnNoGoAreas: [NoGoArea] = []
    var drawnNoMopAreas: [NoMopArea] = []
    var drawnVirtualWalls: [VirtualWall] = []
    var drawnAnnotations: [MapAnnotation] = []
    var existingRestrictions: VirtualRestrictions?
    var existingAnnotations: [MapAnnotation] = []
    var annotationTypeToDraw: MapAnnotationType = .threshold
    var currentDrawStart: CGPoint?
    var currentDrawEnd: CGPoint?
    var editMode: MapEditMode = .none
    var showRoomLabels: Bool = true
    var segmentPixelSets: [String: Set<Int>] = [:]
    var cachedSegmentInfos: [SegmentInfo] = []

    // Soft pastel room colors
    private let segmentColors: [Color] = [
        Color(red: 0.65, green: 0.80, blue: 0.92),  // Soft sky blue
        Color(red: 0.70, green: 0.88, blue: 0.75),  // Soft mint green
        Color(red: 0.92, green: 0.78, blue: 0.72),  // Soft peach
        Color(red: 0.82, green: 0.75, blue: 0.90),  // Soft lavender
        Color(red: 0.90, green: 0.85, blue: 0.65),  // Soft gold
        Color(red: 0.70, green: 0.85, blue: 0.85),  // Soft teal
        Color(red: 0.90, green: 0.72, blue: 0.78),  // Soft rose
        Color(red: 0.78, green: 0.88, blue: 0.72),  // Soft sage
    ]

    var body: some View {
        Canvas { context, size in
            let pixelSize = map.pixelSize ?? 5
            guard let layers = map.layers, !layers.isEmpty else {
                let text = Text("No map layers")
                context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }

            let params = calculateMapParams(layers: layers, pixelSize: pixelSize, size: size)
            guard let p = params else {
                let text = Text("Map calculation failed")
                context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }

            // STATIC: Pre-rendered floor + segments + walls
            if let img = staticLayerImage {
                context.draw(
                    Image(decorative: img, scale: UIScreen.main.scale),
                    in: CGRect(origin: .zero, size: size)
                )
            } else {
                // Fallback: pixel-by-pixel when CGImage not yet ready
                drawLayersDecompressed(context: context, layers: layers, type: "floor", color: Color(white: 0.92), params: p, pixelSize: pixelSize)
                for layer in layers where layer.type == "segment" {
                    let pixels = layer.decompressedPixels
                    guard !pixels.isEmpty else { continue }
                    let segmentId = layer.metaData?.segmentId
                    let baseColor = segmentColor(segmentId: segmentId)
                    let color = baseColor.opacity(0.6)
                    let material = layer.metaData?.material
                    drawPixelsWithMaterial(context: context, pixels: pixels, color: color, material: material, params: p, pixelSize: pixelSize)
                }
                drawWalls(context: context, layers: layers, color: Color(white: 0.25), params: p, pixelSize: pixelSize)
            }

            // DYNAMIC: Selection borders (only for selected segments, drawn over static image)
            for layer in layers where layer.type == "segment" {
                let segmentId = layer.metaData?.segmentId
                let isSelected = segmentId.map { selectedSegmentIds.contains($0) } ?? false
                if isSelected {
                    let pixels = layer.decompressedPixels
                    guard !pixels.isEmpty else { continue }

                    let baseColor = segmentColor(segmentId: segmentId)
                    let selectedColor = baseColor.opacity(0.9)
                    drawPixels(context: context, pixels: pixels, color: selectedColor, params: p, pixelSize: pixelSize)
                    drawSegmentBorder(context: context, pixels: pixels, params: p, pixelSize: pixelSize)
                }
            }

            // DYNAMIC: Entities (path, charger, robot)
            if let entities = map.entities {
                for entity in entities where entity.type == "path" || entity.type == "predicted_path" {
                    drawPath(context: context, entity: entity, params: p, pixelSize: pixelSize)
                }
                for entity in entities where entity.type == "charger_location" {
                    drawCharger(context: context, entity: entity, params: p, pixelSize: pixelSize)
                }
                for entity in entities where entity.type == "robot_position" {
                    drawRobot(context: context, entity: entity, params: p, pixelSize: pixelSize)
                }
            }

            // DYNAMIC: Existing restrictions
            if let restrictions = existingRestrictions {
                for wall in restrictions.virtualWalls {
                    drawVirtualWall(context: context, wall: wall, params: p, pixelSize: pixelSize, isNew: false)
                }
                for area in restrictions.restrictedZones {
                    drawRestrictedZone(context: context, area: area, params: p, pixelSize: pixelSize, color: .red.opacity(0.3), isNew: false)
                }
                for area in restrictions.noMopZones {
                    drawRestrictedZone(context: context, area: area, params: p, pixelSize: pixelSize, color: .blue.opacity(0.3), isNew: false)
                }
            }

            // DYNAMIC: Existing map annotations
            for annotation in existingAnnotations {
                drawAnnotation(context: context, annotation: annotation, params: p, pixelSize: pixelSize, isNew: false)
            }

            // DYNAMIC: New zones/restrictions + drawing preview
            for zone in drawnZones {
                drawCleaningZone(context: context, zone: zone, params: p, pixelSize: pixelSize)
            }
            for area in drawnNoGoAreas {
                drawRestrictedZone(context: context, area: area, params: p, pixelSize: pixelSize, color: .red.opacity(0.4), isNew: true)
            }
            for area in drawnNoMopAreas {
                drawRestrictedZone(context: context, area: area, params: p, pixelSize: pixelSize, color: .blue.opacity(0.4), isNew: true)
            }
            for wall in drawnVirtualWalls {
                drawVirtualWall(context: context, wall: wall, params: p, pixelSize: pixelSize, isNew: true)
            }
            for annotation in drawnAnnotations {
                drawAnnotation(context: context, annotation: annotation, params: p, pixelSize: pixelSize, isNew: true)
            }

            if let start = currentDrawStart, let end = currentDrawEnd, editMode != .goTo && editMode != .savePreset {
                drawCurrentDrawing(context: context, start: start, end: end, mode: editMode, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "map.canvas_label"))
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    handleCanvasTap(at: value.location, size: viewSize)
                }
        )
        .overlay {
            // Tap targets and labels (only when visible)
            if showRoomLabels {
                tapTargetsOverlay
            }
        }
        .overlay {
            annotationLabelsOverlay
        }
        .overlay {
            orderBadgesOverlay
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(canvasAccessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    private var canvasAccessibilityLabel: String {
        if segments.isEmpty {
            return String(localized: "map.accessibility_label_no_rooms")
        }
        let roomCount = segments.count
        let selectedCount = selectedSegmentIds.count
        if selectedCount > 0 {
            return String(localized: "map.accessibility_label_rooms_selected \(roomCount) \(selectedCount)")
        }
        return String(localized: "map.accessibility_label_rooms \(roomCount)")
    }

    // MARK: - Tap Targets
    @ViewBuilder
    private var tapTargetsOverlay: some View {
        GeometryReader { geometry in
            let params = calculateMapParams(
                layers: map.layers ?? [],
                pixelSize: map.pixelSize ?? 5,
                size: geometry.size
            )

            if let p = params {
                // Room labels only
                ForEach(cachedSegmentInfos, id: \.id) { info in
                    let x = CGFloat(info.midX) * p.scale + p.offsetX
                    let y = CGFloat(info.midY) * p.scale + p.offsetY
                    let isSelected = selectedSegmentIds.contains(info.id)

                    Button {
                        toggleSegment(info.id)
                    } label: {
                        HStack(spacing: 4) {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white, .blue)
                            }
                            VStack(spacing: 1) {
                                Text(info.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(isSelected ? .white : .primary)
                                // The floor texture alone is hard to tell apart, so the material is named too.
                                if let material = info.material, material != "generic" {
                                    Text(FloorMaterial.displayName(for: material))
                                        .font(.system(size: 9))
                                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            isSelected
                                ? Color.blue
                                : Color(.systemBackground).opacity(0.9)
                        )
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                    .accessibilityLabel(info.name)
                    .accessibilityHint(isSelected
                        ? String(localized: "map.room_deselect_hint")
                        : String(localized: "map.room_select_hint"))
                    .buttonStyle(.plain)
                    .position(x: x, y: y)
                }
            }
        }
    }

    // MARK: - Annotation Labels

    /// Labels each annotation, which also gives thin thresholds a comfortable tap target.
    @ViewBuilder
    private var annotationLabelsOverlay: some View {
        let all = existingAnnotations + drawnAnnotations
        // In delete mode the delete buttons take these spots.
        if !all.isEmpty, editMode != .deleteAnnotation {
            GeometryReader { geometry in
                let params = calculateMapParams(
                    layers: map.layers ?? [],
                    pixelSize: map.pixelSize ?? 5,
                    size: geometry.size
                )

                if let p = params {
                    let ps = CGFloat(map.pixelSize ?? 5)
                    ForEach(all) { annotation in
                        let sumX = annotation.points.reduce(0) { $0 + $1.x }
                        let sumY = annotation.points.reduce(0) { $0 + $1.y }
                        let count = max(annotation.points.count, 1)
                        let x = CGFloat(sumX) / CGFloat(count) / ps * p.scale + p.offsetX
                        let y = CGFloat(sumY) / CGFloat(count) / ps * p.scale + p.offsetY

                        HStack(spacing: 3) {
                            Image(systemName: annotation.type.icon)
                                .font(.system(size: 9, weight: .semibold))
                            Text(annotation.type.displayName)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(.systemBackground).opacity(0.9))
                        .foregroundStyle(annotationColor(annotation.type))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        .position(x: x, y: y)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    // MARK: - Order Badges
    @ViewBuilder
    private var orderBadgesOverlay: some View {
        if editMode == .none, !selectedSegmentIds.isEmpty {
            GeometryReader { geometry in
                let params = calculateMapParams(
                    layers: map.layers ?? [],
                    pixelSize: map.pixelSize ?? 5,
                    size: geometry.size
                )

                if let p = params {
                    ForEach(Array(selectedSegmentIds.enumerated()), id: \.element) { index, segmentId in
                        if let info = cachedSegmentInfos.first(where: { $0.id == segmentId }) {
                            let x = CGFloat(info.midX) * p.scale + p.offsetX
                            let y = CGFloat(info.midY) * p.scale + p.offsetY

                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 24, height: 24)
                                Text("\(index + 1)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .position(x: x, y: y - 20)
                        }
                    }
                }
            }
        }
    }

    private func toggleSegment(_ id: String) {
        if selectedSegmentIds.contains(id) {
            selectedSegmentIds.removeAll(where: { $0 == id })
        } else {
            selectedSegmentIds.append(id)
        }
    }

    // MARK: - Canvas Tap Hit-Testing
    private func handleCanvasTap(at location: CGPoint, size: CGSize) {
        guard editMode == .none || editMode == .roomEdit else { return }
        guard let layers = map.layers else { return }

        let pixelSize = map.pixelSize ?? 5
        guard let p = calculateMapParams(layers: layers, pixelSize: pixelSize, size: size) else { return }

        let pixelX = Int(((location.x - p.offsetX) / p.scale).rounded())
        let pixelY = Int(((location.y - p.offsetY) / p.scale).rounded())

        // O(1) lookup per segment statt linearem Pixel-Scan
        let key = pixelX &<< 16 | pixelY
        for (segmentId, pixelSet) in segmentPixelSets {
            if pixelSet.contains(key) {
                toggleSegment(segmentId)
                return
            }
        }
        // No hit — no toggle, no unintended state change
    }

    // MARK: - Drawing Functions
    private func drawLayersDecompressed(context: GraphicsContext, layers: [MapLayer], type: String, color: Color, params: MapParams, pixelSize: Int) {
        for layer in layers where layer.type == type {
            let pixels = layer.decompressedPixels
            guard !pixels.isEmpty else { continue }
            drawPixels(context: context, pixels: pixels, color: color, params: params, pixelSize: pixelSize)
        }
    }

    private func drawWalls(context: GraphicsContext, layers: [MapLayer], color: Color, params: MapParams, pixelSize: Int) {
        let normalScale = params.scale * CGFloat(pixelSize)
        let wallScale = normalScale * 0.2  // 20% - very thin
        for layer in layers where layer.type == "wall" {
            let pixels = layer.decompressedPixels
            guard !pixels.isEmpty else { continue }
            var i = 0
            while i < pixels.count - 1 {
                let x = CGFloat(pixels[i]) * params.scale + params.offsetX + normalScale * 0.4
                let y = CGFloat(pixels[i + 1]) * params.scale + params.offsetY + normalScale * 0.4
                let rect = CGRect(x: x, y: y, width: wallScale, height: wallScale)
                context.fill(Path(rect), with: .color(color))
                i += 2
            }
        }
    }

    private func drawPixels(context: GraphicsContext, pixels: [Int], color: Color, params: MapParams, pixelSize: Int) {
        let pixelScale = params.scale * CGFloat(pixelSize)
        var i = 0
        while i < pixels.count - 1 {
            let x = CGFloat(pixels[i]) * params.scale + params.offsetX
            let y = CGFloat(pixels[i + 1]) * params.scale + params.offsetY
            let rect = CGRect(x: x, y: y, width: pixelScale + 0.5, height: pixelScale + 0.5)
            context.fill(Path(rect), with: .color(color))
            i += 2
        }
    }

    private func drawPixelsWithMaterial(context: GraphicsContext, pixels: [Int], color: Color, material: String?, params: MapParams, pixelSize: Int) {
        let pixelScale = params.scale * CGFloat(pixelSize)
        var i = 0

        // Wide spacing and differing contrast, see MapViewModel.
        let textureInterval: Int
        let isHorizontal: Bool
        let isVertical: Bool
        let accentStrength: Double

        switch material {
        case "tile":
            textureInterval = 8
            isHorizontal = true
            isVertical = true
            accentStrength = 0.75
        case "wood", "wood_horizontal":
            textureInterval = 6
            isHorizontal = true
            isVertical = false
            accentStrength = 0.75
        case "wood_vertical":
            textureInterval = 6
            isHorizontal = false
            isVertical = true
            accentStrength = 0.75
        case "carpet", "carpet_low", "carpet_high":
            textureInterval = 4
            isHorizontal = true
            isVertical = true
            accentStrength = 0.45
        default:
            // Generic or unknown - just draw plain pixels
            textureInterval = 0
            isHorizontal = false
            isVertical = false
            accentStrength = 1.0
        }

        // Darken, don't fade: a more transparent colour reads lighter.
        let accentColor = Color(MapViewModel.darken(UIColor(color), by: accentStrength))

        while i < pixels.count - 1 {
            let px = pixels[i]
            let py = pixels[i + 1]
            let x = CGFloat(px) * params.scale + params.offsetX
            let y = CGFloat(py) * params.scale + params.offsetY
            let rect = CGRect(x: x, y: y, width: pixelScale + 0.5, height: pixelScale + 0.5)

            // Check if this pixel should be accented for texture
            let shouldAccent: Bool
            if textureInterval > 0 {
                let hMatch = isHorizontal && (py % textureInterval == 0)
                let vMatch = isVertical && (px % textureInterval == 0)
                shouldAccent = hMatch || vMatch
            } else {
                shouldAccent = false
            }

            context.fill(Path(rect), with: .color(shouldAccent ? accentColor : color))
            i += 2
        }
    }

    private func drawSegmentBorder(context: GraphicsContext, pixels: [Int], params: MapParams, pixelSize: Int) {
        // Simple approach: draw a subtle glow around selected segments
        let pixelScale = params.scale * CGFloat(pixelSize)
        var i = 0
        while i < pixels.count - 1 {
            let x = CGFloat(pixels[i]) * params.scale + params.offsetX
            let y = CGFloat(pixels[i + 1]) * params.scale + params.offsetY
            let rect = CGRect(x: x - 1, y: y - 1, width: pixelScale + 2, height: pixelScale + 2)
            context.stroke(Path(rect), with: .color(.blue.opacity(0.3)), lineWidth: 0.5)
            i += 2
        }
    }

    private func segmentColor(segmentId: String?) -> Color {
        if let id = segmentId, let num = Int(id) {
            return segmentColors[num % segmentColors.count]
        }
        return segmentColors[0]
    }

    private func drawPath(context: GraphicsContext, entity: MapEntity, params: MapParams, pixelSize: Int) {
        guard let points = entity.points, points.count >= 4 else { return }
        let ps = CGFloat(pixelSize)

        var path = Path()
        path.move(to: CGPoint(
            x: CGFloat(points[0]) / ps * params.scale + params.offsetX,
            y: CGFloat(points[1]) / ps * params.scale + params.offsetY
        ))

        var i = 2
        while i < points.count - 1 {
            path.addLine(to: CGPoint(
                x: CGFloat(points[i]) / ps * params.scale + params.offsetX,
                y: CGFloat(points[i + 1]) / ps * params.scale + params.offsetY
            ))
            i += 2
        }

        let isPredicted = entity.type == "predicted_path"
        let color = isPredicted ? Color(white: 0.4).opacity(0.5) : Color(white: 0.35).opacity(0.8)
        let style = isPredicted ?
            StrokeStyle(lineWidth: 1, dash: [3, 2]) :
            StrokeStyle(lineWidth: 1)

        context.stroke(path, with: .color(color), style: style)
    }

    private func drawCharger(context: GraphicsContext, entity: MapEntity, params: MapParams, pixelSize: Int) {
        guard let points = entity.points, points.count >= 2 else { return }
        let ps = CGFloat(pixelSize)

        let x = CGFloat(points[0]) / ps * params.scale + params.offsetX
        let y = CGFloat(points[1]) / ps * params.scale + params.offsetY
        let size: CGFloat = 14

        let glowRect = CGRect(x: x - size/2 - 2, y: y - size/2 - 2, width: size + 4, height: size + 4)
        context.fill(RoundedRectangle(cornerRadius: 4).path(in: glowRect), with: .color(Color(white: 0.2).opacity(0.3)))

        let rect = CGRect(x: x - size/2, y: y - size/2, width: size, height: size)
        context.fill(RoundedRectangle(cornerRadius: 3).path(in: rect), with: .color(Color(white: 0.2)))

        // House shape for dock
        var house = Path()
        house.move(to: CGPoint(x: x, y: y - 4))
        house.addLine(to: CGPoint(x: x + 4, y: y))
        house.addLine(to: CGPoint(x: x + 2.5, y: y))
        house.addLine(to: CGPoint(x: x + 2.5, y: y + 3))
        house.addLine(to: CGPoint(x: x - 2.5, y: y + 3))
        house.addLine(to: CGPoint(x: x - 2.5, y: y))
        house.addLine(to: CGPoint(x: x - 4, y: y))
        house.closeSubpath()
        context.fill(house, with: .color(.white))
    }

    private func drawRobot(context: GraphicsContext, entity: MapEntity, params: MapParams, pixelSize: Int) {
        guard let points = entity.points, points.count >= 2 else { return }
        let ps = CGFloat(pixelSize)

        let x = CGFloat(points[0]) / ps * params.scale + params.offsetX
        let y = CGFloat(points[1]) / ps * params.scale + params.offsetY
        let size: CGFloat = 16

        let glowRect = CGRect(x: x - size/2 - 3, y: y - size/2 - 3, width: size + 6, height: size + 6)
        context.fill(Circle().path(in: glowRect), with: .color(Color(white: 0.2).opacity(0.3)))

        let outerRect = CGRect(x: x - size/2, y: y - size/2, width: size, height: size)
        context.fill(Circle().path(in: outerRect), with: .color(Color(white: 0.2)))

        let innerSize: CGFloat = 10
        let innerRect = CGRect(x: x - innerSize/2, y: y - innerSize/2, width: innerSize, height: innerSize)
        context.fill(Circle().path(in: innerRect), with: .color(Color(white: 0.3)))

        let dotSize: CGFloat = 4
        let dotRect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
        context.fill(Circle().path(in: dotRect), with: .color(.white))
    }

    // MARK: - Zone Drawing
    // Note: All API coordinates are in mm, need to divide by pixelSize to get pixel coordinates
    private func drawCleaningZone(context: GraphicsContext, zone: CleaningZone, params: MapParams, pixelSize: Int) {
        let p = zone.points
        let ps = CGFloat(pixelSize)
        var path = Path()
        path.move(to: CGPoint(
            x: CGFloat(p.pA.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pA.y) / ps * params.scale + params.offsetY
        ))
        path.addLine(to: CGPoint(
            x: CGFloat(p.pB.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pB.y) / ps * params.scale + params.offsetY
        ))
        path.addLine(to: CGPoint(
            x: CGFloat(p.pC.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pC.y) / ps * params.scale + params.offsetY
        ))
        path.addLine(to: CGPoint(
            x: CGFloat(p.pD.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pD.y) / ps * params.scale + params.offsetY
        ))
        path.closeSubpath()

        context.fill(path, with: .color(.orange.opacity(0.3)))
        context.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
    }

    private func drawRestrictedZone(context: GraphicsContext, area: NoGoArea, params: MapParams, pixelSize: Int, color: Color, isNew: Bool) {
        let p = area.points
        let ps = CGFloat(pixelSize)
        var path = Path()
        path.move(to: CGPoint(
            x: CGFloat(p.pA.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pA.y) / ps * params.scale + params.offsetY
        ))
        path.addLine(to: CGPoint(
            x: CGFloat(p.pB.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pB.y) / ps * params.scale + params.offsetY
        ))
        path.addLine(to: CGPoint(
            x: CGFloat(p.pC.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pC.y) / ps * params.scale + params.offsetY
        ))
        path.addLine(to: CGPoint(
            x: CGFloat(p.pD.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pD.y) / ps * params.scale + params.offsetY
        ))
        path.closeSubpath()

        context.fill(path, with: .color(color))
        let strokeColor: Color = color.opacity(1.0)
        context.stroke(path, with: .color(strokeColor), style: StrokeStyle(lineWidth: isNew ? 2 : 1))
    }

    private func drawRestrictedZone(context: GraphicsContext, area: NoMopArea, params: MapParams, pixelSize: Int, color: Color, isNew: Bool) {
        let p = area.points
        let ps = CGFloat(pixelSize)
        var path = Path()
        path.move(to: CGPoint(
            x: CGFloat(p.pA.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pA.y) / ps * params.scale + params.offsetY
        ))
        path.addLine(to: CGPoint(
            x: CGFloat(p.pB.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pB.y) / ps * params.scale + params.offsetY
        ))
        path.addLine(to: CGPoint(
            x: CGFloat(p.pC.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pC.y) / ps * params.scale + params.offsetY
        ))
        path.addLine(to: CGPoint(
            x: CGFloat(p.pD.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pD.y) / ps * params.scale + params.offsetY
        ))
        path.closeSubpath()

        context.fill(path, with: .color(color))
        let strokeColor: Color = color.opacity(1.0)
        context.stroke(path, with: .color(strokeColor), style: StrokeStyle(lineWidth: isNew ? 2 : 1))
    }

    private func drawVirtualWall(context: GraphicsContext, wall: VirtualWall, params: MapParams, pixelSize: Int, isNew: Bool) {
        let p = wall.points
        let ps = CGFloat(pixelSize)
        var path = Path()
        path.move(to: CGPoint(
            x: CGFloat(p.pA.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pA.y) / ps * params.scale + params.offsetY
        ))
        path.addLine(to: CGPoint(
            x: CGFloat(p.pB.x) / ps * params.scale + params.offsetX,
            y: CGFloat(p.pB.y) / ps * params.scale + params.offsetY
        ))

        context.stroke(path, with: .color(.purple), style: StrokeStyle(lineWidth: isNew ? 4 : 3))
    }

    private func drawAnnotation(context: GraphicsContext, annotation: MapAnnotation, params: MapParams, pixelSize: Int, isNew: Bool) {
        let ps = CGFloat(pixelSize)
        let screenPoints = annotation.points.map {
            CGPoint(
                x: CGFloat($0.x) / ps * params.scale + params.offsetX,
                y: CGFloat($0.y) / ps * params.scale + params.offsetY
            )
        }
        guard let first = screenPoints.first else { return }

        let color = annotationColor(annotation.type)
        var path = Path()
        path.move(to: first)
        for point in screenPoints.dropFirst() {
            path.addLine(to: point)
        }

        switch annotation.type {
        case .threshold, .curtain:
            // Curtains are drawn dashed to tell them apart from thresholds
            let dash: [CGFloat] = annotation.type == .curtain ? [6, 4] : []
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: isNew ? 4 : 3, dash: dash)
            )
        case .ramp:
            path.closeSubpath()
            context.fill(path, with: .color(color.opacity(isNew ? 0.4 : 0.3)))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2))
        }
    }

    private func annotationColor(_ type: MapAnnotationType) -> Color {
        switch type {
        case .threshold: return .green
        case .curtain: return .teal
        case .ramp: return .indigo
        }
    }

    private func drawCurrentDrawing(context: GraphicsContext, start: CGPoint, end: CGPoint, mode: MapEditMode, size: CGSize) {
        let color: Color
        switch mode {
        case .zone: color = .orange
        case .noGoArea: color = .red
        case .noMopArea: color = .blue
        case .virtualWall: color = .purple
        case .goTo: color = .blue
        case .savePreset: color = .yellow
        case .splitRoom: color = .red
        case .annotation: color = annotationColor(annotationTypeToDraw)
        case .roomEdit, .deleteRestriction, .deleteAnnotation, .none: return
        }

        let drawsLine = mode == .virtualWall
            || mode == .splitRoom
            || (mode == .annotation && annotationTypeToDraw != .ramp)

        if drawsLine {
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4))

            let startSize: CGFloat = 16
            context.fill(Circle().path(in: CGRect(
                x: start.x - startSize/2,
                y: start.y - startSize/2,
                width: startSize,
                height: startSize
            )), with: .color(color))
            context.stroke(Circle().path(in: CGRect(
                x: start.x - startSize/2,
                y: start.y - startSize/2,
                width: startSize,
                height: startSize
            )), with: .color(.white), lineWidth: 2)

            let endSize: CGFloat = 16
            context.fill(Circle().path(in: CGRect(
                x: end.x - endSize/2,
                y: end.y - endSize/2,
                width: endSize,
                height: endSize
            )), with: .color(color))
            context.stroke(Circle().path(in: CGRect(
                x: end.x - endSize/2,
                y: end.y - endSize/2,
                width: endSize,
                height: endSize
            )), with: .color(.white), lineWidth: 2)
        } else if mode == .goTo || mode == .savePreset {
            let targetSize: CGFloat = 20
            context.fill(Circle().path(in: CGRect(
                x: start.x - targetSize/2,
                y: start.y - targetSize/2,
                width: targetSize,
                height: targetSize
            )), with: .color(color.opacity(0.5)))
            context.stroke(Circle().path(in: CGRect(
                x: start.x - targetSize/2,
                y: start.y - targetSize/2,
                width: targetSize,
                height: targetSize
            )), with: .color(color), lineWidth: 2)
        } else {
            let minX = min(start.x, end.x)
            let maxX = max(start.x, end.x)
            let minY = min(start.y, end.y)
            let maxY = max(start.y, end.y)
            let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

            context.fill(Path(rect), with: .color(color.opacity(0.3)))
            context.stroke(Path(rect), with: .color(color), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
        }
    }
}
