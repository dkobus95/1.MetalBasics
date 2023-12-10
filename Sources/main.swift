var a: [Float32] = [1, 2, 3, 4]
var b: [Float32] = [-1, 0, 1, 2]

let c = zip(a, b).map{$0 + $1}

print("CPU result => \(c)")

// === Start Accelerate ===
import Accelerate

extension [Float] {
    static func +(_ l: [Float], _ r: [Float]) -> [Float] {
        vDSP.add(l, r)
    }
}

let cAccelerate = a + b
print("CPU accelerate result => \(c)")

var unsafeA = a.withUnsafeMutableBufferPointer {
    return $0
}
var unsafeB = b.withUnsafeMutableBufferPointer {
    return $0
}

extension UnsafeMutableBufferPointer<Float> {
    static func +(_ l: inout UnsafeMutableBufferPointer<Float> , _ r: inout UnsafeMutableBufferPointer<Float>) -> UnsafeMutableBufferPointer<Float> {
        var out = UnsafeMutableBufferPointer<Float>.allocate(capacity: l.count)
        vDSP.add(l, r, result: &out)
        return out
    }
}
let unsafeC = unsafeA + unsafeB
print("Unsafe accelerate result => \([Float32](unsafeC))")
// === Start Metal code ===
import Metal

// init global Metal device
let device = MTLCopyAllDevices()[0]

// init device buffers
//let aBuffer = device.makeBuffer(
//    bytes: a.withUnsafeBytes{ $0.baseAddress! }, 
//    length: a.count * MemoryLayout<Float32>.stride,
//    options: [.storageModeShared]
//)!
//let bBuffer = device.makeBuffer(
//    bytes: b.withUnsafeBytes{ $0.baseAddress! },
//    length: b.count * MemoryLayout<Float32>.stride,
//    options: [.storageModeShared]
//)!

// init reuse memory
let aBuffer = device.makeBuffer(
    bytesNoCopy: a.withUnsafeMutableBytes{ $0.baseAddress! },
    length: a.count * MemoryLayout<Float32>.stride,
    options: [.storageModeShared]
)!
let bBuffer = device.makeBuffer(
    bytesNoCopy: b.withUnsafeMutableBytes{ $0.baseAddress! },
    length: b.count * MemoryLayout<Float32>.stride,
    options: [.storageModeShared]
)!

let cmdQue = device.makeCommandQueue()!

// function that invoke simple add shader on GPU
// a + b = c
func simpleAddMetal(_ left: MTLBuffer, _ right: MTLBuffer) -> MTLBuffer {
    // Create commandBuffer
    let cmdBuffer = cmdQue.makeCommandBuffer()!
    // Create commandEncoder
    let encoder = cmdBuffer.makeComputeCommandEncoder()!
    // Get shader
    let shader = addSimple
    encoder.setComputePipelineState(shader.state)
    // create output buffer
    let outBuffer = device.makeBuffer(length: left.length, options: [.storageModeShared])!
    let w = shader.state.threadExecutionWidth
    let threadsPerThreadgroup = MTLSizeMake(w, 1, 1)
    let threadsPerGrid = MTLSize(width: left.length / MemoryLayout<Float32>.stride, // bytes to array size
                                 height: 1,
                                 depth: 1)
    // preapre all buffers needed for compute shader
    encoder.setBuffer(left, offset: 0, index: 0)
    encoder.setBuffer(right, offset: 0, index: 1)
    encoder.setBuffer(outBuffer, offset: 0, index: 2)
    // dispatch compute shader
    encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    // end compute encoder
    encoder.endEncoding()
    // commit command to GPU
    cmdBuffer.commit()
    // wait for GPU to end compute
    cmdBuffer.waitUntilCompleted()
    return outBuffer
}

func simpleAddMetal(_ left: MTLBuffer, _ right: MTLBuffer, out: MTLBuffer, cmdBuffer: MTLCommandBuffer) -> MTLBuffer {
    // Create commandEncoder
    let encoder = cmdBuffer.makeComputeCommandEncoder()!
    // Get shader
    let shader = addSimple
    encoder.setComputePipelineState(shader.state)
    // create output buffer
    let outBuffer = out
    let w = shader.state.threadExecutionWidth
    let threadsPerThreadgroup = MTLSizeMake(w, 1, 1)
    let threadsPerGrid = MTLSize(width: left.length / MemoryLayout<Float32>.stride, // bytes to array size
                                 height: 1,
                                 depth: 1)
    // preapre all buffers needed for compute shader
    encoder.setBuffer(left, offset: 0, index: 0)
    encoder.setBuffer(right, offset: 0, index: 1)
    encoder.setBuffer(outBuffer, offset: 0, index: 2)
    // dispatch compute shader
    encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    // end compute encoder
    encoder.endEncoding()
    return outBuffer
}

let cBuffer = simpleAddMetal(aBuffer, bBuffer)


let cArray = Array(UnsafeBufferPointer(
    start: cBuffer.contents().assumingMemoryBound(to: Float32.self),
    count: c.count)
)
print("Metal (GPU) result => \(cArray)")


@available(macOS 13.0, iOS 16.0, *)
func benchmarkTest(checkResults: Bool = false) {
    let clock = ContinuousClock()
    let measureIterations = 10
    let inputSizes = [256, 4096, 262144, 1048576]
    for inputSize in inputSizes {
        var a: [Float32] = (0..<inputSize).map{_ in Float32.random(in: 0..<1)}
        var b: [Float32] = (0..<inputSize).map{_ in Float32.random(in: 0..<1)}
        let originalResult = zip(a, b).map{$0 + $1}

        var unsafeA = a.withUnsafeMutableBufferPointer {
            return $0
        }
        var unsafeB = b.withUnsafeMutableBufferPointer {
            return $0
        }
        
        let aBuffer = device.makeBuffer(
            bytesNoCopy: a.withUnsafeMutableBytes{ $0.baseAddress! },
            length: a.count * MemoryLayout<Float32>.stride,
            options: [.storageModeShared]
        )!
        let bBuffer = device.makeBuffer(
            bytesNoCopy: b.withUnsafeMutableBytes{ $0.baseAddress! },
            length: b.count * MemoryLayout<Float32>.stride,
            options: [.storageModeShared]
        )!
        let outBuffer = device.makeBuffer(
            length: originalResult.count * MemoryLayout<Float32>.stride,
            options: [.storageModeShared]
        )!
        
        // CPU
        let cpuTime = clock.measure {
            for _ in 0..<measureIterations {
                let c = zip(a, b).map{$0 + $1}
                if checkResults {
                    assert(c ~= originalResult)
                }
            }
            
        }
        print("======== \(inputSize) ========")
        print("CPU simple => \(Double(cpuTime.components.attoseconds) * 1e-15 / Double(measureIterations)) ms")
        let accelerateArrayTime = clock.measure {
            for _ in 0..<measureIterations {
                let c = a + b
                if checkResults {
                    assert(c ~= originalResult)
                }
            }
        }
        print("CPU array accelerate => \(Double(accelerateArrayTime.components.attoseconds) * 1e-15 / Double(measureIterations)) ms")
        let accelerateBufferTime = clock.measure {
            for _ in 0..<measureIterations {
                let unsafeC = unsafeA + unsafeB
                if checkResults {
                    assert([Float32](unsafeC) ~= originalResult)
                }
            }
        }
        print("CPU buffer accelerate => \(Double(accelerateBufferTime.components.attoseconds) * 1e-15 / Double(measureIterations)) ms")
        
        let gpuTime = clock.measure {
            for _ in 0..<measureIterations {
                let cBuffer = simpleAddMetal(aBuffer, bBuffer)
                if checkResults {
                    let cArray = Array(UnsafeBufferPointer(
                        start: cBuffer.contents().assumingMemoryBound(to: Float32.self),
                        count: cBuffer.length / MemoryLayout<Float32>.stride)
                    )
                    assert(cArray ~= originalResult)
                }
            }
        }
        print("GPU => \(Double(gpuTime.components.attoseconds) * 1e-15 / Double(measureIterations)) ms")
        
        let gpuPrealocated = clock.measure {
            let cmdBuffer = cmdQue.makeCommandBuffer()!
            for _ in 0..<measureIterations {
                    let _ = simpleAddMetal(aBuffer, bBuffer, out: outBuffer, cmdBuffer: cmdBuffer)
            }
            if checkResults {
                let _ = simpleAddMetal(aBuffer, bBuffer, out: outBuffer, cmdBuffer: cmdBuffer)
                cmdBuffer.commit()
                cmdBuffer.waitUntilCompleted()
                let cArray = Array(UnsafeBufferPointer(
                    start: outBuffer.contents().assumingMemoryBound(to: Float32.self),
                    count: outBuffer.length / MemoryLayout<Float32>.stride)
                )
                assert(cArray ~= originalResult)
            }
            else {
                cmdBuffer.addTimerMilliseconds(Double(measureIterations))
                cmdBuffer.commit()
                cmdBuffer.waitUntilCompleted()
            }

        }
        print("GPU preallocate buffer with wait => \(Double(gpuPrealocated.components.attoseconds) * 1e-15 / Double(measureIterations)) ms")
        print("======== \(inputSize) ========")
    }
}

if #available(macOS 13.0, *) {
    benchmarkTest()
//    benchmarkTest(checkResults: true)
}


