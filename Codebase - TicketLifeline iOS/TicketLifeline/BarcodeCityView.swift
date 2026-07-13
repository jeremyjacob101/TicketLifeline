import CoreImage
import MetalKit
import SwiftUI
import UIKit

/// A single Metal scene for both states of a Code 128 pass. The exact barcode
/// modules remain visible from above, then fold down into a street of facades.
struct BarcodeCityView: UIViewRepresentable {
    let code: SavedCode
    let isFlat: Bool

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
        view.backgroundColor = UIColor(red: 0.969, green: 0.980, blue: 0.988, alpha: 1)
        if let renderer = BarcodeCityMetalRenderer(
            view: view,
            pattern: BarcodePattern(payload: code.payload),
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

    init(payload: String) {
        let modules = Self.modules(payload: payload)
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

    private static func modules(payload: String) -> [Bool] {
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
    var start: Float
    var width: Float
    var palette: UInt32
    var kind: UInt32
}

private struct BarcodeUniforms {
    var aspectRatio: Float
    var time: Float
    /// One is the top-down, scannable barcode; zero is the city.
    var flatness: Float
    var moduleCount: Float
    var padding = SIMD4<Float>(repeating: 0)
}

private final class BarcodeCityMetalRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let blocksPipeline: MTLRenderPipelineState
    private let roadPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let segmentsBuffer: MTLBuffer
    private let uniformsBuffer: MTLBuffer
    private let segmentCount: Int
    private let moduleCount: Float
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
              let roadFragment = library.makeFunction(name: "barcodeCityRoadFragment") else { return nil }

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
        } catch {
            return nil
        }

        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depth) else { return nil }
        self.depthState = depthState

        let segments = pattern.runs.map {
            BarcodeSegmentGPU(
                start: Float($0.start),
                width: Float($0.width),
                palette: $0.palette,
                kind: $0.isDark ? 1 : 0
            )
        }
        guard let segmentsBuffer = device.makeBuffer(
            bytes: segments,
            length: max(1, segments.count * MemoryLayout<BarcodeSegmentGPU>.stride),
            options: .storageModeShared
        ), let uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<BarcodeUniforms>.stride,
            options: .storageModeShared
        ) else { return nil }

        self.queue = queue
        self.segmentsBuffer = segmentsBuffer
        self.uniformsBuffer = uniformsBuffer
        segmentCount = segments.count
        moduleCount = Float(pattern.moduleCount)
        rawProgress = initiallyFlat ? 1 : 0
        targetProgress = rawProgress
        super.init()
    }

    func setFlat(_ flat: Bool) { targetProgress = flat ? 1 : 0 }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        let now = CACurrentMediaTime()
        let delta = Float(min(now - lastTime, 0.05))
        lastTime = now
        rawProgress += (targetProgress - rawProgress) * min(1, delta * 5.8)
        if abs(rawProgress - targetProgress) < 0.001 { rawProgress = targetProgress }
        let flatness = rawProgress < 0.5
            ? 4 * rawProgress * rawProgress * rawProgress
            : 1 - pow(-2 * rawProgress + 2, 3) / 2
        let cityAmount = 1 - flatness
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(0.973 - cityAmount * 0.018),
            green: Double(0.980 - cityAmount * 0.010),
            blue: Double(0.988 - cityAmount * 0.028),
            alpha: 1
        )

        var uniforms = BarcodeUniforms(
            aspectRatio: Float(view.drawableSize.width / max(view.drawableSize.height, 1)),
            time: Float(now - startTime),
            flatness: flatness,
            moduleCount: moduleCount
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
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }
}
