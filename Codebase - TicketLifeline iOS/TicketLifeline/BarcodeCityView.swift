import CoreImage
import MetalKit
import SwiftUI
import UIKit

/// A single Metal scene for both states of a Code 128 pass. The exact barcode
/// modules remain visible from above, then fold down into a street of facades.
struct BarcodeCityView: UIViewRepresentable {
    let isFlat: Bool
    private let pattern: BarcodePattern

    init(code: SavedCode, isFlat: Bool) {
        self.isFlat = isFlat
        pattern = BarcodePattern(code: code)
    }

    init(code: DetectedCode, isFlat: Bool) {
        self.isFlat = isFlat
        pattern = BarcodePattern(code: code)
    }

    final class Coordinator {
        fileprivate var renderer: BarcodeCityMetalRenderer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.isOpaque = true
        view.backgroundColor = .white
        view.clearColor = MTLClearColorMake(1, 1, 1, 1)
        if let renderer = BarcodeCityMetalRenderer(
            view: view,
            pattern: pattern,
            initiallyFlat: isFlat
        ) {
            context.coordinator.renderer = renderer
            view.delegate = renderer
        }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.setFlat(isFlat)
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.delegate = nil
        coordinator.renderer = nil
    }
}

/// Samples the same unscaled Core Image generator used by BarcodeImage. The
/// renderer therefore receives the real dark/light module sequence, including
/// its quiet zones, instead of inventing a decorative approximation.
private struct BarcodePattern {
    struct Run {
        let start: Int
        let width: Int
        let isDark: Bool
        let palette: UInt32
    }

    let moduleCount: Int
    let runs: [Run]

    init(code: SavedCode) {
        self.init(
            encoded: code.visualMatrix,
            width: code.visualWidth ?? code.visualSize,
            height: code.visualHeight ?? code.visualSize,
            payload: code.payload
        )
    }

    init(code: DetectedCode) {
        self.init(
            encoded: code.visualMatrix,
            width: code.visualWidth,
            height: code.visualHeight,
            payload: code.payload
        )
    }

    private init(encoded: String?, width: Int?, height: Int?, payload: String) {
        let modules = Self.modules(encoded: encoded, width: width, height: height, payload: payload)
        moduleCount = max(modules.count, 1)
        var collected: [Run] = []
        var index = 0
        var darkBuildingIndex: UInt32 = 0

        while index < modules.count {
            let isDark = modules[index]
            let start = index
            while index < modules.count && modules[index] == isDark { index += 1 }
            collected.append(
                Run(
                    start: start,
                    width: index - start,
                    isDark: isDark,
                    palette: isDark ? darkBuildingIndex % 4 : 0
                )
            )
            if isDark { darkBuildingIndex += 1 }
        }

        // CIFilter always produces a Code 128 image for a valid string. Keep
        // a tiny valid-looking fallback so an empty malformed input never
        // leaves a blank Metal view.
        runs = collected.isEmpty
            ? [Run(start: 0, width: 1, isDark: false, palette: 0)]
            : collected
    }

    private static func modules(encoded: String?, width: Int?, height: Int?, payload: String) -> [Bool] {
        if let encoded,
           let width,
           let height,
           width > 0,
           height > 0,
           encoded.count == width * height {
            let source = Array(encoded.utf8)
            if height == 1 {
                return source.map { $0 == 49 }
            }
            return (0..<width).map { column in
                var dark = 0
                for row in 0..<height where source[row * width + column] == 49 { dark += 1 }
                return dark * 2 >= height
            }
        }
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(payload.utf8)
        filter.quietSpace = 8
        guard let output = filter.outputImage else { return [false] }

        let bounds = output.extent.integral
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard width > 0, height > 0 else { return [false] }

        var pixels = Array(repeating: UInt8(0), count: width * height * 4)
        CIContext().render(
            output,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: bounds,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let row = height / 2
        return (0..<width).map { column in
            let offset = (row * width + column) * 4
            return pixels[offset] < 128
        }
    }
}

private struct BarcodeSegmentGPU {
    /// Exact Core Image barcode coordinates used by the flat endpoint.
    var flatCenter: Float
    var flatWidth: Float
    /// Centered, normalized coordinates used only by the city endpoint.
    var cityCenter: Float
    var cityWidth: Float
    var palette: UInt32
    var kind: UInt32
}

private struct CityPropGPU {
    var x: Float
    var z: Float
    var streetWidth: Float
    /// 0 = car, 1 = traffic light.
    var kind: UInt32
    var palette: UInt32
    /// 0 travels along a cross street; 1 travels along the avenue.
    var direction: UInt32
}

private struct BarcodeUniforms {
    var aspectRatio: Float
    var time: Float
    /// One is the top-down, scannable barcode; zero is the city.
    var flatness: Float
    var moduleCount: Float
    var cityStreetWidth: Float
    var cityHalfWidth: Float
    var padding = SIMD2<Float>(repeating: 0)
}

private final class BarcodeCityMetalRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let blocksPipeline: MTLRenderPipelineState
    private let roadPipeline: MTLRenderPipelineState
    private let propsPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let segmentsBuffer: MTLBuffer
    private let propsBuffer: MTLBuffer
    private let uniformsBuffer: MTLBuffer
    private let segmentCount: Int
    private let propCount: Int
    private let moduleCount: Float
    private let cityStreetWidth: Float
    private let cityHalfWidth: Float
    private let startTime = CACurrentMediaTime()
    private var lastTime = CACurrentMediaTime()
    private var rawProgress: Float
    private var targetProgress: Float

    init?(view: MTKView, pattern: BarcodePattern, initiallyFlat: Bool) {
        guard let device = view.device,
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let blockVertex = library.makeFunction(name: "barcodeCityBlockVertex"),
              let blockFragment = library.makeFunction(name: "barcodeCityBlockFragment"),
              let roadVertex = library.makeFunction(name: "barcodeCityRoadVertex"),
              let roadFragment = library.makeFunction(name: "barcodeCityRoadFragment"),
              let propsVertex = library.makeFunction(name: "barcodeCityPropsVertex"),
              let propsFragment = library.makeFunction(name: "barcodeCityPropsFragment") else { return nil }

        func pipeline(vertex: MTLFunction, fragment: MTLFunction) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        do {
            blocksPipeline = try pipeline(vertex: blockVertex, fragment: blockFragment)
            roadPipeline = try pipeline(vertex: roadVertex, fragment: roadFragment)
            propsPipeline = try pipeline(vertex: propsVertex, fragment: propsFragment)
        } catch {
            return nil
        }

        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depth) else { return nil }
        self.depthState = depthState

        // The city is deliberately allowed to rearrange the barcode runs,
        // while the flat endpoint continues to use the literal CI positions.
        // Every internal light run becomes one equal-width street; outer quiet
        // zones collapse into white city margins instead of road end caps.
        // City-only streets receive ample room for the small prop geometry;
        // this never affects the literal Code 128 endpoint.
        let cityStreetModules: Float = 18
        let cityBuildingMultiplier: Float = 5
        let flatSpan: Float = 1.55
        let citySpan: Float = 1.78
        let flatScale = flatSpan / Float(max(pattern.moduleCount, 1))
        let lastIndex = pattern.runs.indices.last
        let cityWeight = pattern.runs.enumerated().reduce(Float.zero) { total, item in
            let (index, run) = item
            let isQuietZone = !run.isDark && (index == 0 || index == lastIndex)
            if isQuietZone { return total }
            return total + (run.isDark ? Float(run.width) * cityBuildingMultiplier : cityStreetModules)
        }
        let cityScale = citySpan / max(cityWeight, 1)
        let computedStreetWidth = cityStreetModules * cityScale
        var cityCursor = -citySpan / 2
        var streets: [(x: Float, width: Float)] = []
        var segments: [BarcodeSegmentGPU] = []

        for (index, run) in pattern.runs.enumerated() {
            let isQuietZone = !run.isDark && (index == 0 || index == lastIndex)
            let kind: UInt32 = run.isDark ? 1 : (isQuietZone ? 0 : 2)
            let cityWidth = isQuietZone
                ? Float.leastNonzeroMagnitude
                : (run.isDark ? Float(run.width) * cityBuildingMultiplier : cityStreetModules) * cityScale
            let cityCenter: Float
            if isQuietZone {
                cityCenter = index == 0 ? -citySpan / 2 : citySpan / 2
            } else {
                cityCenter = cityCursor + cityWidth / 2
                cityCursor += cityWidth
            }
            let flatCenter = (Float(run.start) + Float(run.width) / 2 - Float(pattern.moduleCount) / 2) * flatScale
            segments.append(
                BarcodeSegmentGPU(
                    flatCenter: flatCenter,
                    flatWidth: Float(run.width) * flatScale,
                    cityCenter: cityCenter,
                    cityWidth: cityWidth,
                    palette: run.palette,
                    kind: kind
                )
            )
            if kind == 2 { streets.append((cityCenter, cityWidth)) }
        }

        // A small, deterministic set keeps the streets charming rather than
        // crowded. Cars and lights are generated from the actual street runs.
        let carCount = min(8, streets.count)
        var props: [CityPropGPU] = []
        for slot in 0..<carCount {
            let streetIndex = min(streets.count - 1, slot * streets.count / carCount)
            let street = streets[streetIndex]
            props.append(
                CityPropGPU(
                    x: street.x,
                    z: 0.135 + Float(slot % 3) * 0.080,
                    streetWidth: street.width,
                    kind: 0,
                    palette: UInt32(slot % 4),
                    direction: 0
                )
            )
            if slot.isMultiple(of: 2) {
                props.append(
                    CityPropGPU(
                        x: street.x,
                        z: 0.09 + street.width * 0.16,
                        streetWidth: street.width,
                        kind: 1,
                        palette: 0,
                        direction: 0
                    )
                )
            }
        }

        // The avenue is a real second traffic direction, not empty scenery.
        // Three cars occupy alternating lanes and two signals hang over it at
        // deterministic cross-street junctions.
        for slot in 0..<3 {
            props.append(
                CityPropGPU(
                    x: -citySpan * 0.27 + Float(slot) * citySpan * 0.27,
                    z: 0.09 + (slot.isMultiple(of: 2) ? -1 : 1) * computedStreetWidth * 0.16,
                    streetWidth: computedStreetWidth,
                    kind: 0,
                    palette: UInt32((slot + 1) % 4),
                    direction: 1
                )
            )
        }
        if streets.count >= 3 {
            for fraction in 1...2 {
                let street = streets[min(streets.count - 1, fraction * streets.count / 3)]
                props.append(
                    CityPropGPU(
                        x: street.x,
                        z: 0.09,
                        streetWidth: computedStreetWidth,
                        kind: 1,
                        palette: 0,
                        direction: 1
                    )
                )
            }
        }

        let bufferProps = props.isEmpty
            ? [CityPropGPU(x: 0, z: 0, streetWidth: 0, kind: 0, palette: 0, direction: 0)]
            : props
        guard let segmentsBuffer = device.makeBuffer(
            bytes: segments,
            length: max(1, segments.count * MemoryLayout<BarcodeSegmentGPU>.stride),
            options: .storageModeShared
        ), let propsBuffer = device.makeBuffer(
            bytes: bufferProps,
            length: max(1, bufferProps.count * MemoryLayout<CityPropGPU>.stride),
            options: .storageModeShared
        ), let uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<BarcodeUniforms>.stride,
            options: .storageModeShared
        ) else { return nil }

        self.queue = queue
        self.segmentsBuffer = segmentsBuffer
        self.propsBuffer = propsBuffer
        self.uniformsBuffer = uniformsBuffer
        segmentCount = segments.count
        propCount = props.count
        moduleCount = Float(pattern.moduleCount)
        cityStreetWidth = computedStreetWidth
        cityHalfWidth = citySpan / 2
        rawProgress = initiallyFlat ? 1 : 0
        targetProgress = rawProgress
        super.init()
    }

    func setFlat(_ flat: Bool) { targetProgress = flat ? 1 : 0 }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer() else { return }

        let now = CACurrentMediaTime()
        let delta = Float(min(now - lastTime, 0.05))
        lastTime = now
        rawProgress += (targetProgress - rawProgress) * min(1, delta * 5.8)
        if abs(rawProgress - targetProgress) < 0.001 { rawProgress = targetProgress }
        let flatness = rawProgress < 0.5
            ? 4 * rawProgress * rawProgress * rawProgress
            : 1 - pow(-2 * rawProgress + 2, 3) / 2
        // The artwork card stays clean white in both endpoints. All city
        // depth comes from the road and building geometry, never a tinted sky.
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 1, 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        var uniforms = BarcodeUniforms(
            aspectRatio: Float(view.drawableSize.width / max(view.drawableSize.height, 1)),
            time: Float(now - startTime),
            flatness: flatness,
            moduleCount: moduleCount,
            cityStreetWidth: cityStreetWidth,
            cityHalfWidth: cityHalfWidth
        )
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<BarcodeUniforms>.stride)

        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.setRenderPipelineState(roadPipeline)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        encoder.setRenderPipelineState(blocksPipeline)
        encoder.setVertexBuffer(segmentsBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: segmentCount)

        if propCount > 0 {
            encoder.setRenderPipelineState(propsPipeline)
            encoder.setVertexBuffer(propsBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 144, instanceCount: propCount)
        }
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }
}
