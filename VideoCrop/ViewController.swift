//
//  ViewController.swift
//  VideoCrop
//
//  Created by Mandeep Singh on 21/06/19.
//  Copyright © 2019 Mandeep Singh. All rights reserved.
//

import UIKit
import MobileCoreServices
import AVFoundation
import AVKit
let imageSize = 368

class ViewController: UIViewController {
    
    @IBOutlet weak var videoImage: UIImageView!
    @IBOutlet weak var frameLabel: UILabel!

    var oldURL : URL?
    let ciContext = CIContext()
    var resultBuffer: CVPixelBuffer?
    var editingImage: UIImage?
    let targetImageSize = CGSize(width: imageSize, height: imageSize) // must match model data input
    var audioWriterInput: AVAssetWriterInput?
    var audioReader: AVAssetReader?
    var audioReaderOutPut:AVAssetReaderTrackOutput?

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @IBAction func pickVideo(_ sender: Any) {
        self.openGallery()
    }
    
    @IBAction func tapOnCreateNew(_ sender: Any) {
        
        guard let newURL = self.oldURL else {return}
        self.createNewVideo(newURL)
    }

}


extension ViewController {
    
    //check Status
    func openGallery() {
        
        let mediaTypeArray : [String] = [kUTTypeMovie as String]

        self.openImagePickerViewController(sourceType: .photoLibrary, mediaTypes: mediaTypeArray, callBack: { (isAllow) in
            if let allowed = isAllow as? Bool, allowed == true {
                self.openImagePicker(sourceType: .photoLibrary, mediaTypes: mediaTypeArray)
            }
        })
    }
}

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    
    func openImagePicker(sourceType: UIImagePickerController.SourceType, mediaTypes: [String]) {
        
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = self
        picker.mediaTypes = mediaTypes
        picker.videoExportPreset = AVAssetExportPresetPassthrough
        self.present(picker, animated: true, completion: nil)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        guard let videoURL = info[.mediaURL] as? URL else {
            picker.dismiss(animated: true, completion: nil)
            return
        }
        self.oldURL = videoURL
        picker.dismiss(animated: true, completion: nil)
        
        DispatchQueue.main.async {
            
            self.generateThumnail(url: videoURL, fps: { (getFrames) in
                if let frame = getFrames as? Float {
                    self.frameLabel.text = "\(frame) Frame Per second"
                }
            }, thumbnail: { (thumbnail) in
                if let image = thumbnail as? UIImage {
                    self.videoImage.image = image
                }
            })
        }
    }
}

struct XPQueues {
    static let concurrentQueue = DispatchQueue(label: "com.vuzag.zag", attributes: DispatchQueue.Attributes.concurrent)
    static let mainQueue = DispatchQueue.main
    static let background = DispatchQueue.global(qos: .background)
}

extension ViewController {
    
    func createNewArrayOfImages(_ inputURL: URL, adaptor: AVAssetWriterInputPixelBufferAdaptor , isCompleted: SharedInstance.completionHandler?) {
        
        XPQueues.concurrentQueue.async {

        let avAsset = AVURLAsset(url: inputURL, options: nil)
        let composition = AVVideoComposition(asset: avAsset, applyingCIFiltersWithHandler: { request in })

        let dispatchGroup = DispatchGroup()

        //We are Creating the instance of AVAssetImageGenerator
        let generator = AVAssetImageGenerator(asset: avAsset)
        
        // Settings to get captures of all frames.
        // Without these settings, you can only get captures of integral seconds.
        generator.requestedTimeToleranceAfter = CMTime.zero
        generator.requestedTimeToleranceBefore = CMTime.zero
        
        let track = avAsset.tracks(withMediaType: AVMediaType.video)

        guard let media = track[0] as AVAssetTrack? else {
            print("ERROR: There is no video track.")
            return
        }
        
        //variables
        let naturalSize: CGSize = media.naturalSize
        let preferedTransform: CGAffineTransform = media.preferredTransform

        let length: Double = Double(CMTimeGetSeconds(avAsset.duration))
        let fps: Int = Int(1 / CMTimeGetSeconds(composition.frameDuration))
        
            autoreleasepool(invoking: {
                for i in stride(from: 0, to: length, by: 1.0 / Double(fps)) {
                    // Capture an image from the video file.
                    let requestedTime = CMTime(seconds: i, preferredTimescale : 600)
                    
                    dispatchGroup.enter()
                    
                    generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: requestedTime)], completionHandler: { (timeValue, image, timeObject, _, error) in
                        
                        dispatchGroup.leave() //This will execute the next value of for loop
                        
                        guard let imageC = image else {return}
                        
                        var orientation: UIImage.Orientation
                        
                        // Rotate the captured image.
                        if preferedTransform.tx == naturalSize.width && preferedTransform.ty == naturalSize.height {
                            orientation = UIImage.Orientation.down
                        } else if preferedTransform.tx == 0 && preferedTransform.ty == 0 {
                            orientation = UIImage.Orientation.up
                        } else if preferedTransform.tx == 0 && preferedTransform.ty == naturalSize.width {
                            orientation = UIImage.Orientation.left
                        } else {
                            orientation = UIImage.Orientation.right
                        }
                        
                        //generate the new Image
                        let tmpImageToEdit = UIImage(cgImage: imageC, scale: 1.0, orientation: orientation)
                        
                        // Resize width to a multiple of 16 and edit the image with overlay
                        self.editingImage = self.resizeImage(image: tmpImageToEdit, size: tmpImageToEdit.size, keepAspectRatio: true, useToMakeVideo: true, iValue: Int(timeValue.seconds))
                        
                        //create the buffer from image
                        let buffer = self.getPixelBufferFromCGImage(cgImage: self.editingImage!.cgImage!)
                        
                        // Repeat until the adaptor is ready.
                        while true {
                            if (adaptor.assetWriterInput.isReadyForMoreMediaData) {
                                //add into the buffer
                                adaptor.append(buffer, withPresentationTime: timeValue)
                                break
                            }
                        }
                        
                        print(timeValue.seconds)
                    })
                }
            })
        
            //stop the for loop for executing next values
            dispatchGroup.wait()
            
            dispatchGroup.notify(queue: .main) {
                print("Both functions complete 👍")
                if let callBack = isCompleted {
                    callBack(true as AnyObject)
                }
            }
        }
    }
    

    
    /// Create new video with autogenerated frames
    ///
    /// - Parameter inputURL: in which you have to do the editing
    func createNewVideo(_ inputURL: URL) {
        
        var isAudio = false
        
        guard let outputURL = Methods.sharedInstance.newVideoURL1 else {return}
        
        guard let videoWriter = try? AVAssetWriter(outputURL: outputURL, fileType: AVFileType.mov) else {
            print("ERROR: Failed to construct AVAssetWriter.")
            return
        }
        
        let avAsset = AVURLAsset(url: inputURL, options: nil)
        let track = avAsset.tracks(withMediaType: AVMediaType.video)
        
        //check video has some sound
        if avAsset.tracks(withMediaType: AVMediaType.audio).count > 0 {
            isAudio = true
        }
        
        guard let media = track[0] as AVAssetTrack? else {
            print("ERROR: There is no video track.")
            return
        }
        
        //variables
        let naturalSize: CGSize = media.naturalSize
        let preferedTransform: CGAffineTransform = media.preferredTransform
        let size = naturalSize.applying(preferedTransform)
        let width = abs(size.width)
        let height = abs(size.height)
        
        //Define Video Properties
        let outputSettings = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
            ] as [String: Any]
        
        //Create Instance of Video Writer Input
        let writerInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: outputSettings as [String : AnyObject])
        writerInput.expectsMediaDataInRealTime = true
        
        //Add Input
        videoWriter.add(writerInput)
        
        //setup video reader
        let videoReaderSettings:[String : AnyObject] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB) as AnyObject
        ]
        
        //Create Instance of AVAssetReaderTrackOutput for Video and add into AVAssetReader
        let assetReaderVideoOutput = AVAssetReaderTrackOutput(track: media, outputSettings: videoReaderSettings)
        let videoReader = try! AVAssetReader(asset: avAsset)
        videoReader.add(assetReaderVideoOutput)
        
        if isAudio {
            //Create Instance of AVAssetWriterInput
            self.audioWriterInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: nil)
            self.audioWriterInput?.expectsMediaDataInRealTime = true
            videoWriter.add(self.audioWriterInput!)
            
            //Create Instance of AVAssetReaderTrackOutput for Audio and add into AVAssetReader
            let audioTrack = avAsset.tracks(withMediaType: AVMediaType.audio)[0]
            self.audioReaderOutPut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            self.audioReader = try! AVAssetReader(asset: avAsset)
            self.audioReader!.add(self.audioReaderOutPut!)
        }
        
        //Create the adaptor so that we can add the new buffer with new changes
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        
        videoWriter.startWriting()
        videoReader.startReading()
        videoWriter.startSession(atSourceTime: CMTime.zero)
        
        
        DispatchQueue.global().async {
            
            self.createNewArrayOfImages(inputURL, adaptor: adaptor, isCompleted: { (isTrue) in
                writerInput.markAsFinished()
                //Video Part is complete, now audio part is start
                if isAudio {
                    self.audioReader!.startReading()
                    
                    videoWriter.startSession(atSourceTime: CMTime.zero)
                    
                    let processingQueue = DispatchQueue(label: "processingQueue2")
                    
                    self.audioWriterInput!.requestMediaDataWhenReady(on: processingQueue, using: {
                        while self.audioWriterInput!.isReadyForMoreMediaData {
                            
                            if let bufferObj = self.audioReaderOutPut!.copyNextSampleBuffer() {
                                if self.audioReader!.status == .reading {
                                    self.audioWriterInput!.append(bufferObj)
                                }
                            } else {
                                self.audioWriterInput!.markAsFinished()
                                if self.audioReader!.status == .completed {
                                    videoWriter.finishWriting(completionHandler: {() -> Void in
                                        self.destroyAllVariables()
                                        
                                        DispatchQueue.main.async(execute: {
                                            let player = AVPlayer(url: outputURL)
                                            let playerViewController = AVPlayerViewController()
                                            playerViewController.player = player
                                            self.present(playerViewController, animated: true) {
                                                playerViewController.player!.play()
                                            }
                                        })
                                    })
                                }
                            }
                        }
                    })
                } else {
                    videoWriter.finishWriting(completionHandler: {() -> Void in
                        DispatchQueue.main.async(execute: {
                            let player = AVPlayer(url: outputURL)
                            let playerViewController = AVPlayerViewController()
                            playerViewController.player = player
                            self.present(playerViewController, animated: true) {
                                playerViewController.player!.play()
                            }
                        })
                    })
                }
            })
        }
    }
    
    private func destroyAllVariables() {
        self.audioReader = nil
        self.audioWriterInput = nil
        self.audioReaderOutPut = nil
        self.editingImage = nil
        self.resultBuffer = nil
    }
    
    fileprivate func getCMSampleBuffer(pxBuffer: CVPixelBuffer) -> CMSampleBuffer {
        
        var info = CMSampleTimingInfo()
        info.presentationTimeStamp = CMTime.zero
        info.duration = CMTime.invalid
        info.decodeTimeStamp = CMTime.invalid
        
        
        var formatDesc: CMFormatDescription? = nil
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pxBuffer, formatDescriptionOut: &formatDesc)
        
        var sampleBuffer: CMSampleBuffer? = nil
        
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: pxBuffer,
                                                 formatDescription: formatDesc!,
                                                 sampleTiming: &info,
                                                 sampleBufferOut: &sampleBuffer);
        
        return sampleBuffer!
    }
    
    func imageFromSampleBuffer(sampleBuffer : CMSampleBuffer) -> CGImage
    {
        // Get a CMSampleBuffer's Core Video image buffer for the media data
        let  imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        // Lock the base address of the pixel buffer
        CVPixelBufferLockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly);
        
        
        // Get the number of bytes per row for the pixel buffer
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer!);
        
        // Get the number of bytes per row for the pixel buffer
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer!);
        // Get the pixel buffer width and height
        let width = CVPixelBufferGetWidth(imageBuffer!);
        let height = CVPixelBufferGetHeight(imageBuffer!);
        
        // Create a device-dependent RGB color space
        let colorSpace = CGColorSpaceCreateDeviceRGB();
        
        // Create a bitmap graphics context with the sample buffer data
        var bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue
        bitmapInfo |= CGImageAlphaInfo.premultipliedFirst.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
        //let bitmapInfo: UInt32 = CGBitmapInfo.alphaInfoMask.rawValue
        let context = CGContext.init(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)
        // Create a Quartz image from the pixel data in the bitmap graphics context
        let quartzImage = context?.makeImage();
        // Unlock the pixel buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly);
        
        return quartzImage!
    }
    
    func uiImageToPixelBuffer(_ uiImage: UIImage, targetSize: CGSize, orientation: UIImage.Orientation) -> CVPixelBuffer? {
        var angle: CGFloat
        
        if orientation == UIImage.Orientation.down {
            angle = CGFloat.pi
        } else if orientation == UIImage.Orientation.up {
            angle = 0
        } else if orientation == UIImage.Orientation.left {
            angle = CGFloat.pi / 2.0
        } else {
            angle = -CGFloat.pi / 2.0
        }
        
        let rotateTransform: CGAffineTransform = CGAffineTransform(translationX: targetSize.width / 2.0, y: targetSize.height / 2.0).rotated(by: angle).translatedBy(x: -targetSize.height / 2.0, y: -targetSize.width / 2.0)
        
        let uiImageResized = self.resizeImage(image: uiImage, size: targetSize, keepAspectRatio: true)
        let ciImage = CIImage(image: uiImageResized)!
        let rotated = ciImage.transformed(by: rotateTransform)
        
        // Only need to create this buffer one time and then we can reuse it for every frame
        if resultBuffer == nil {
            let result = CVPixelBufferCreate(kCFAllocatorDefault, Int(targetSize.width), Int(targetSize.height), kCVPixelFormatType_32BGRA, nil, &resultBuffer)
            
            guard result == kCVReturnSuccess else {
                fatalError("Can't allocate pixel buffer.")
            }
        }
        
        // Render the Core Image pipeline to the buffer
        ciContext.render(rotated, to: resultBuffer!)
        
        //  For debugging
        //  let image = imageBufferToUIImage(resultBuffer!)
        //  print(image.size) // set breakpoint to see image being provided to CoreML
        
        return resultBuffer
    }
    
    func getPixelBufferFromCGImage(cgImage: CGImage) -> CVPixelBuffer {
        let width = cgImage.width
        let height = cgImage.height
        
        let options = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        var pxBuffer: CVPixelBuffer? = nil
        
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, options as CFDictionary?, &pxBuffer)
        CVPixelBufferLockBaseAddress(pxBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        let pxdata = CVPixelBufferGetBaseAddress(pxBuffer!)
        let bitsPerComponent: size_t = 8
        let bytesPerRow: size_t = 4 * width
        let rgbColorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
        
        let context = CGContext(
            data: pxdata,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(x:0, y:0, width:CGFloat(width),height:CGFloat(height)))
        
        CVPixelBufferUnlockBaseAddress(pxBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return pxBuffer!
    }

    func resizeImage(image: UIImage, size: CGSize, keepAspectRatio: Bool = false, useToMakeVideo: Bool = false, iValue: Int = 0) -> UIImage {
        var targetSize: CGSize = size
        
        let layer = self.addTextOnLayer(videoSize: size, textValue: "Finaly, We achieve this, \(iValue)")
        
        if useToMakeVideo {
            // Resize width to a multiple of 16.
            let resizeRate: CGFloat = CGFloat(Int(image.size.width) / 16) * 16 / image.size.width
            targetSize = CGSize(width: image.size.width * resizeRate, height: image.size.height * resizeRate)
        }
        
        var newSize: CGSize = targetSize
        var newPoint: CGPoint = CGPoint(x: 0, y: 0)
        
        if keepAspectRatio {
            if targetSize.width / image.size.width <= targetSize.height / image.size.height {
                newSize = CGSize(width: targetSize.width, height: image.size.height * targetSize.width / image.size.width)
                newPoint.y = (targetSize.height - newSize.height) / 2
            } else {
                newSize = CGSize(width: image.size.width * targetSize.height / image.size.height, height: targetSize.height)
                newPoint.x = (targetSize.width - newSize.width) / 2
            }
        }
        
        UIGraphicsBeginImageContextWithOptions(targetSize, layer.isOpaque, 0.0)
        //we are generating the new Image.
        image.draw(in: CGRect(x: newPoint.x, y: newPoint.y, width: newSize.width, height: newSize.height))
        //We are adding the overlay on the image. So that it could be visible.
        layer.render(in: UIGraphicsGetCurrentContext()!)
        guard let img = UIGraphicsGetImageFromCurrentImageContext() else { return UIImage() }
        //finally generate the new image.
        UIGraphicsEndImageContext()
        
        return img
    }
    
}




