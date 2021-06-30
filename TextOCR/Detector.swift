//
//  Detector.swift
//  TextOCR
//
//  Created by rei8 on 2021/05/18.
//

import Foundation
import CoreML
import Vision
import UIKit

class Detector {
    static var isVertical = false
    static let mldetector = MLDetector()
    class func callDetect(for image: UIImage, callback: ((String)->Void)?) {
        mldetector.convertImage(for: image, callback: callback)
    }
}

class MLDetector: NSObject {

    lazy var config: MLModelConfiguration = {
        var conf = MLModelConfiguration()
        conf.computeUnits = .all
        return conf
    }()

    lazy var encoderModel:VNCoreMLModel = try! VNCoreMLModel(for: ImageEncoder(configuration: config).model)
    lazy var transfomerEncoderModel = try! ImageTransformerEncoder(configuration: config)
    lazy var transfomerDecoderModel = try! ImageTransformerDecoder(configuration: config)

    func convertImage(for image: UIImage, callback: ((String)->Void)?) {
        var results = [[Float]]()
        var pixelCount = [[Int]](repeating: [Int](repeating: 0, count: 5), count: 6)
        
        let pixelsWidth = Int(image.size.width * image.scale)
        let pixelsHeight = Int(image.size.height * image.scale)
        let pixelGrid = Int(128 * image.scale)
        
        guard let pixelData = image.cgImage?.dataProvider?.data else { return }
        let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
        for x in 0..<pixelsWidth {
            let xgrid = x / pixelGrid
            for y in 0..<pixelsHeight {
                let ygrid = y / pixelGrid
                let idx = (y * pixelsWidth + x) * 4
                let r = data[idx]
                let g = data[idx+1]
                let b = data[idx+2]
                if r < 255 || g < 255 || b < 255 {
                    pixelCount[xgrid][ygrid] += 1
                }
            }
        }
        
        var horizontal_count = 31
        var vertical_count = 31
        if Detector.isVertical {
            // 縦書き
            outerloop: for x in 0..<6 {
                for y in (0..<5).reversed() {
                    if pixelCount[x][y] == 0 {
                        vertical_count -= 1
                    }
                    else {
                        break outerloop
                    }
                }
            }
        }
        else {
            // 横書き
            outerloop: for y in (0..<5).reversed() {
                for x in (0..<6).reversed() {
                    if pixelCount[x][y] == 0 {
                        horizontal_count -= 1
                    }
                    else {
                        break outerloop
                    }
                }
            }
        }
        
        if Detector.isVertical {
            outerloop: for x in (0..<6).reversed() {
                for y in 0..<5 {
                    if vertical_count <= 0 {
                        break outerloop
                    }
                    vertical_count -= 1
                    guard let cgImage = image.cgImage?.cropping(to: CGRect(x: x * pixelGrid, y: y * pixelGrid, width: pixelGrid, height: pixelGrid)) else { return }
                    let request = VNCoreMLRequest(model: encoderModel) { request, error in
                        guard let observations = request.results as? [VNCoreMLFeatureValueObservation] else {
                            callback?("Error")
                            return
                        }
                        guard let feature = observations[0].featureValue.multiArrayValue else {
                            callback?("Error")
                            return
                        }
                        guard feature.shape[0] == 1, feature.shape[1] == 256 else {
                            callback?("Error")
                            return
                        }
                        var result = [Float]()
                        for i in 0..<256 {
                            result.append(feature[i].floatValue)
                        }
                        results.append(result)
                    }
                    request.imageCropAndScaleOption = .scaleFit
                    let handler = VNImageRequestHandler(cgImage: cgImage)
                    try? handler.perform([request])
                }
            }
        }
        else {
            outerloop: for y in 0..<5 {
                for x in 0..<6 {
                    if horizontal_count <= 0 {
                        break outerloop
                    }
                    horizontal_count -= 1
                    guard let cgImage = image.cgImage?.cropping(to: CGRect(x: x * pixelGrid, y: y * pixelGrid, width: pixelGrid, height: pixelGrid)) else { return }
                    let request = VNCoreMLRequest(model: encoderModel) { request, error in
                        guard let observations = request.results as? [VNCoreMLFeatureValueObservation] else {
                            callback?("Error")
                            return
                        }
                        guard let feature = observations[0].featureValue.multiArrayValue else {
                            callback?("Error")
                            return
                        }
                        guard feature.shape[0] == 1, feature.shape[1] == 256 else {
                            callback?("Error")
                            return
                        }
                        var result = [Float]()
                        for i in 0..<256 {
                            result.append(feature[i].floatValue)
                        }
                        results.append(result)
                    }
                    request.imageCropAndScaleOption = .scaleFill
                    let handler = VNImageRequestHandler(cgImage: cgImage)
                    try? handler.perform([request])
                }
            }
        }
        DispatchQueue.global().async {
            callback?(self.convertToText(features: results))
        }
    }
    
    func convertToText(features: [[Float]]) -> String {
        guard features.count < 32 else {
            return "Length Over"
        }
        
        let LOOP_COUNT = 4
        let LEN_CANDIDATE = 4

        //
        // transformer encoder part
        //
        let mlarray1 = try! MLMultiArray(shape: [1, 32, 256], dataType: .float32 )
        let p = mlarray1.dataPointer.bindMemory(to: Float.self, capacity: 1*32*256)
        for i in 0..<1*32*256 {
            p[i] = 0
        }
        for c in 0..<features.count {
            for i in 0..<256 {
                mlarray1[[0,NSNumber(value: c),NSNumber(value: i)]] = NSNumber(value: features[c][i])
            }
        }
        guard let prediction1 = try? transfomerEncoderModel.prediction(input_1: mlarray1) else {
            return "Error"
        }
        // copy result to batch 4
        let result3 = prediction1.Identity.dataPointer.bindMemory(to: Float.self, capacity: LEN_CANDIDATE*32*512)
        let mlarray3 = try! MLMultiArray(shape: [NSNumber(value: LEN_CANDIDATE), 32, 512], dataType: .float32 )
        let p3 = mlarray3.dataPointer.bindMemory(to: Float.self, capacity: LEN_CANDIDATE*32*512)
        for b in 0..<LEN_CANDIDATE {
            for i in 0..<32*512 {
                p3[b*32*512+i] = result3[i]
            }
        }

        //
        // transformer decoder part
        //
        
        // copy encoder input to batch 4
        let mlarray4 = try! MLMultiArray(shape: [NSNumber(value: LEN_CANDIDATE), 32, 256], dataType: .float32 )
        let p4 = mlarray4.dataPointer.bindMemory(to: Float.self, capacity: LEN_CANDIDATE*32*256)
        for b in 0..<LEN_CANDIDATE {
            for i in 0..<32*256 {
                p4[b*32*256+i] = p[i]
            }
        }
        
        // make decoder input for batch 4
        let mlarray2 = try! MLMultiArray(shape: [NSNumber(value: LEN_CANDIDATE), 128], dataType: .float32 )
        let p2 = mlarray2.dataPointer.bindMemory(to: Float.self, capacity: LEN_CANDIDATE*128)
        for i in 0..<LEN_CANDIDATE*128 {
            p2[i] = 0
        }
        // first call has only LENGTH token
        mlarray2[[0,0]] = 257
        
        guard let prediction2 = try? transfomerDecoderModel.prediction(input_1: mlarray4, input_2: mlarray2, input_3: mlarray3) else {
            return "Error"
        }
        var lenExpSum: Float = 0
        var lenProb = [Float](repeating: 0, count: 256)
        let result2 = prediction2.Identity.dataPointer.bindMemory(to: Float.self, capacity: LEN_CANDIDATE*128*256)
        for i in 0..<256 {
            lenProb[i] = exp(result2[i])
            lenExpSum += lenProb[i]
        }
        for i in 0..<256 {
            lenProb[i] /= lenExpSum
        }
        let lenSorted = lenProb.enumerated().sorted {$0.element > $1.element}
        //print(lenSorted[0..<LEN_CANDIDATE])
        let pred_lens = lenSorted[0..<LEN_CANDIDATE].map { $0.offset < 128 ? $0.offset : 128 }
        //print(pred_lens)

        var b_pred_char = [[Int]](repeating: [Int](repeating: 0, count: 128), count: LEN_CANDIDATE)
        var b_pred_p = [[Float]](repeating: [Float](repeating: 0, count: 128), count: LEN_CANDIDATE)

        for loop_l in 0..<LOOP_COUNT {
            // Fill MASK token before call
            for (b, target_len) in zip(pred_lens.indices, pred_lens) {
                // partialy fix previous result
                let fix_len = target_len * loop_l / LOOP_COUNT
                
                if fix_len == 0 {
                    for j in 0..<target_len {
                        p2[b*128+j] = 256
                    }
                }
                else {
                    let pred_p = b_pred_p[b]
                    let pSorted = pred_p.enumerated().sorted {$0.element > $1.element}
                    let fix_idx = pSorted[0..<fix_len].map { $0.offset }
                    
                    for j in 0..<target_len {
                        if fix_idx.contains(j) {
                            p2[b*128+j] = Float(b_pred_char[b][j])
                        }
                        else {
                            p2[b*128+j] = 256
                        }
                    }
                }
            }
            
            guard let prediction3 = try? transfomerDecoderModel.prediction(input_1: mlarray4, input_2: mlarray2, input_3: mlarray3) else {
                return "Error"
            }
            let result3 = prediction3.Identity.dataPointer.bindMemory(to: Float.self, capacity: LEN_CANDIDATE*128*256)
            
            // softmax and argmax in last axis
            for b in 0..<LEN_CANDIDATE {
                var pred_char = [Int](repeating: 0, count: 128)
                var pred_p = [Float](repeating: 0, count: 128)
                for pos in 0..<pred_lens[b] {
                    var expSum: Float = 0
                    var prob = [Float](repeating: 0, count: 256)
                    for i in 0..<256 {
                        prob[i] = exp(result3[b*128*256+pos*256+i])
                        expSum += prob[i]
                    }
                    for i in 0..<256 {
                        prob[i] /= expSum
                    }
                    guard let argmax_i = prob.indices.max(by: { prob[$0] < prob[$1] }) else {
                        return "Error"
                    }
                    pred_char[pos] = argmax_i
                    pred_p[pos] = prob[argmax_i]
                }
                b_pred_char[b] = pred_char
                b_pred_p[b] = pred_p
            }
            //print(b_pred_char)
            //print(b_pred_p)
        }
        
        var result_p = [Float](repeating: 0, count: LEN_CANDIDATE)
        for b in 0..<LEN_CANDIDATE {
            for pos in 0..<pred_lens[b] {
                result_p[b] += log(b_pred_p[b][pos])
            }
            result_p[b] /= Float(pred_lens[b])
            result_p[b] = exp(result_p[b])
        }
        //print(result_p)

        guard let maxp_i = result_p.indices.max(by: { result_p[$0] < result_p[$1] }) else {
            return "Error"
        }
        var converted = Data()
        for pos in 0..<pred_lens[maxp_i] {
            converted.append(UInt8(b_pred_char[maxp_i][pos]))
        }
        
        return "p=" + String(format: "%.5f", result_p[maxp_i]) + "\n" + (String(decoding: converted, as: UTF8.self))
    }
}
