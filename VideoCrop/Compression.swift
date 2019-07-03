//
//  File.swift
//  VideoCrop
//
//  Created by Mandeep Singh on 21/06/19.
//  Copyright © 2019 Mandeep Singh. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

class Methods {
    
    static let sharedInstance = Methods()
    var exportProgressBarTimer : Timer?
    var exportSessionVar : AVAssetExportSession?
    var framePerSecond: Float?
    var textValue = ""
}

extension Methods {
    
    var newVideoURL1 : URL? {
        
        let outputPath = "\(NSTemporaryDirectory())outputCheck.mov"
        let outputURL = URL(fileURLWithPath: outputPath)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputPath) {
            do {
                try fileManager.removeItem(atPath: outputPath)
            } catch {
                print(error.localizedDescription)
            }
        }
        return outputURL
    }
    
    var newVideoURL : URL? {
        
        let outputPath = "\(NSTemporaryDirectory())output.mov"
        let outputURL = URL(fileURLWithPath: outputPath)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputPath) {
            do {
                try fileManager.removeItem(atPath: outputPath)
            } catch {
                print(error.localizedDescription)
            }
        }
        return outputURL
    }
    
    func cancelExportSession() {
        self.exportSessionVar?.cancelExport()
        self.exportSessionVar = nil
    }
    
    // MARK:- Start Compression For Videos
    func overLayAdded(videoURL: URL, progressBlock: SharedInstance.completionHandler?, success:  @escaping SharedInstance.completionHandler, failure: @escaping SharedInstance.completionHandler, orientationBlockMethod:SharedInstance.completionHandler?) {
        
        guard let compressedURL = self.newVideoURL else { return }
        
        self.addOverLayOnVideo(filePath: videoURL, outputURL: compressedURL, handler: { [weak self] (exportSession) in
            guard let session = exportSession else {
                return
            }
            switch session.status {
            case .unknown:
                break
            case .waiting:
                break
            case .exporting:
                break
            case .completed:
                self?.exportProgressBarTimer?.invalidate(); //invalidate timer
                success(compressedURL as AnyObject)
            case .failed:
                break
            case .cancelled:
                break
            @unknown default:
                break
            }
            }, progressBlock: { (progress) in
                if let progressCompltion = progressBlock {
                    progressCompltion(progress as AnyObject)
                }
        }, orientationBlock: { (orientationValue) in
            orientationBlockMethod?(orientationValue)
        })
    }
    
    func videoOrientation(_ videoTrack: AVAssetTrack) -> (AVCaptureVideoOrientation?, front:Bool) {
        
        var isFrontCamera = false
        guard var result = AVCaptureVideoOrientation(rawValue: 0) else { return (nil, isFrontCamera) }
        let transform : CGAffineTransform = videoTrack.preferredTransform.inverted()
        // Portrait
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 && transform.tx > 0 && transform.ty == 0 {
            //back camera
            result = .portrait
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 && transform.tx == 0 && transform.ty > 0 {
            //back camera
            result = .portraitUpsideDown
        } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 && transform.tx == 0 && transform.ty == 0 {
            //back camera
            result = .landscapeRight
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            //back camera
            result = .landscapeLeft
        } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            isFrontCamera = true
            result = .landscapeLeft
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
            isFrontCamera = true
            result = .landscapeRight
        } else if transform.a == 0 && transform.b == 1.0 && transform.c == 1.0 && transform.d == 0 {
            isFrontCamera = true
            result = .portrait
        } else {
            isFrontCamera = true
            result = .portraitUpsideDown
        }
        return (result, isFrontCamera)
    }
    
    func createCompositionFor(clipVideoTrack:AVAssetTrack, orientationBlock: SharedInstance.completionHandler?) -> AVMutableVideoComposition? {
        
        //4. check Orientation Of Video
        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: clipVideoTrack)
        let tupleObject = self.videoOrientation(clipVideoTrack)
        guard let orientation = tupleObject.0 else { return nil }
        orientationBlock?(orientation as AnyObject)
        let isFrontVideo = tupleObject.1
        
        var isPortrait = false
        switch orientation {
        case .landscapeRight:
            isPortrait = false
        case .landscapeLeft:
            isPortrait = false
        case .portrait:
            isPortrait = true
        case .portraitUpsideDown:
            isPortrait = true
        @unknown default:
            break
        }
        
        //2. Create Composition
        let videoComposition = AVMutableVideoComposition()
        if let seconds = framePerSecond {
            videoComposition.frameDuration = CMTimeMake(value: 1, timescale: Int32(seconds))
        } else {
            videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        }
        
        //6. Give Video Compostion to its original Size
        if isPortrait {
            videoComposition.renderSize = CGSize.init(width: clipVideoTrack.naturalSize.height, height: clipVideoTrack.naturalSize.width)
        } else {
            videoComposition.renderSize = clipVideoTrack.naturalSize
        }
        
        if self.textValue.count > 0 {
            let videoSize = videoComposition.renderSize
            //We are adding Text on Video Layer
            videoComposition.animationTool = self.addTextOnLayer(videoSize: videoSize)
        }
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: CMTimeMakeWithSeconds(60, preferredTimescale: 30))
        
        //7. Give initial Scale to Transform
        let scale = CGFloat(1.0)
        var transform = CGAffineTransform.init(scaleX: CGFloat(scale), y: CGFloat(scale))
        
        if isFrontVideo == true {
            //8. if video recorded by front camera
            transform = CGAffineTransform(scaleX: -1.0, y: 1.0)
            transform = transform.translatedBy(x: -clipVideoTrack.naturalSize.width, y: 0.0)
            transform = transform.rotated(by: CGFloat(Double.pi/2))
            transform = transform.translatedBy(x: 0.0, y: -clipVideoTrack.naturalSize.width)
            //10. set transform for video
            transformer.setTransform(transform, at: CMTime.zero)
        } else {
            //10. set transform for video
            transformer.setTransform(clipVideoTrack.preferredTransform, at: CMTime.zero)
        }
        
        //10. set transform for video
        instruction.layerInstructions = [transformer]
        videoComposition.instructions = [instruction]
        
        return videoComposition
    }
    
    private func addTextOnLayer(videoSize: CGSize) -> AVVideoCompositionCoreAnimationTool {
        
        // Adding watermark text
        let titleLayer = CATextLayer()
        titleLayer.backgroundColor = UIColor.black.withAlphaComponent(0.5).cgColor
        titleLayer.string = self.textValue
        titleLayer.font = UIFont(name: "Helvetica-Bold", size: 25)
        titleLayer.alignmentMode = CATextLayerAlignmentMode.center
        titleLayer.frame = CGRect(x: 0, y: videoSize.height / 2, width: videoSize.width, height: 60)
        
        // 2 - The usual overlay
        let overlayLayer = CALayer()
        overlayLayer.addSublayer(titleLayer)
        overlayLayer.frame = CGRect(x: 0, y: 0, width: videoSize.width, height: videoSize.height)
        overlayLayer.masksToBounds = true
        
        
        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(x: 0, y: 0, width: videoSize.width, height: videoSize.height)
        videoLayer.frame = CGRect(x: 0, y: 0, width: videoSize.width, height: videoSize.height)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        
        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
    }
    
    func addOverLayOnVideo(filePath: URL, outputURL: URL, handler:@escaping (_ exportSession: AVAssetExportSession?)-> (), progressBlock: SharedInstance.completionHandler?, orientationBlock: SharedInstance.completionHandler?) {
        
        //1. input file & Initialize of asset
        let asset = AVAsset.init(url: filePath)
        //2. Prevent crash if tracks is empty
        if asset.tracks.isEmpty {
            return
        }
        
        let clipVideoTrack = asset.tracks(withMediaType: AVMediaType.video)[0]
        
        //3. Get Compostion for asset
        let videoComposition = self.createCompositionFor(clipVideoTrack: clipVideoTrack, orientationBlock: { (orientation) in
            if let block = orientationBlock {
                block(orientation as AnyObject)
            }
        })
        
        //4. start export session for video
        self.exportSessionVar = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        
        guard let exportSession = exportSessionVar else {return}
        exportSession.videoComposition = videoComposition
        exportSession.outputURL = outputURL
        exportSession.outputFileType = AVFileType.mov
        exportSession.shouldOptimizeForNetworkUse = true
        
        //5. Start export bar for videos
        self.exportProgressBarTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            // Get Progress
            let progress = Float((exportSession.progress));
            if let block = progressBlock {
                block(progress as AnyObject)
            }
        }
        exportSession.exportAsynchronously { () -> Void in
            handler(exportSession)
        }
    }
    
   
}

