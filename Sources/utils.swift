import Metal
let defaultLibrary = try! device.makeDefaultLibrary(bundle: Bundle.module)

struct Shader {
    let state: MTLComputePipelineState

    init(name: String) {
        let computeShader = defaultLibrary.makeFunction(name: name)!
        let desc = MTLComputePipelineDescriptor()
        desc.computeFunction = computeShader
        let options = MTLPipelineOption()
        self.state = try! device.makeComputePipelineState(descriptor: desc, options: options, reflection: nil)
    }
}

public extension MTLCommandBuffer {
    func addTimerMilliseconds(_ totalCount: Double = 1) {
        self.addCompletedHandler {
            let gpuTime = String(format: "GPU: %.3f ms", (($0.gpuEndTime - $0.gpuStartTime) * 1e3) / totalCount)
            let totalTime = String(format: "Total: %.3f ms", (($0.gpuEndTime - $0.kernelStartTime) * 1e3) / totalCount)
            print("Time spend on GPU \(totalTime) \(gpuTime))")
        }
    }
}

let addSimple = Shader(name: "simpleAddition")
