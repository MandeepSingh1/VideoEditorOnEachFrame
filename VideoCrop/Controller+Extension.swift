//
//  Controller+Extension.swift
//  VideoCrop
//
//  Created by Mandeep Singh on 21/06/19.
//  Copyright © 2019 Mandeep Singh. All rights reserved.
//

import Foundation
import AVFoundation
import Photos
import MobileCoreServices

extension UIViewController {
    
    //MARK:- Check the status whether user allow the gallery or not
    func openImagePickerViewController(sourceType: UIImagePickerController.SourceType, mediaTypes: [String], callBack: SharedInstance.completionHandler?) {
        
        if sourceType == .camera {
            let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
            
            switch cameraAuthorizationStatus {
                
            case .denied:
                self.alertPromptToAllowCameraAccessViaSetting(accessType: "Camera")
                callBack?(false as AnyObject)
            case .authorized:
                callBack?(true as AnyObject)
            case .restricted:
                self.alertPromptToAllowCameraAccessViaSetting(accessType: "Camera")
                callBack?(false as AnyObject)
            case .notDetermined:
                self.openAccessCameraPop(mediaTypes: mediaTypes, callBack: callBack)
            @unknown default:
                break
            }
        } else {
            let photsAuthorizationStatus = PHPhotoLibrary.authorizationStatus()
            
            switch photsAuthorizationStatus {
                
            case .denied:
                self.alertPromptToAllowCameraAccessViaSetting(accessType: "Library")
                callBack?(false as AnyObject)
            case .authorized:
                callBack?(true as AnyObject)
            case .restricted:
                self.alertPromptToAllowCameraAccessViaSetting(accessType: "Library")
                callBack?(false as AnyObject)
            case .notDetermined:
                self.openAccessPhotoLibraryPop(mediaTypes: mediaTypes, callBack: callBack)
            @unknown default:
                break
            }
        }
    }
    
    func openAccessCameraPop(mediaTypes: [String], callBack: SharedInstance.completionHandler?) {
        
        AVCaptureDevice.requestAccess(for: AVMediaType.video) { (granted) in
            
            if granted {
                callBack?(true as AnyObject)
            } else {
                self.alertPromptToAllowCameraAccessViaSetting(accessType: "Camera")
            }
        }
    }
    
    func openAccessPhotoLibraryPop(mediaTypes: [String], callBack: SharedInstance.completionHandler?) {
        
        PHPhotoLibrary.requestAuthorization({(status:PHAuthorizationStatus)in
            
            switch status {
                
            case .denied:
                self.alertPromptToAllowCameraAccessViaSetting(accessType: "Library")
                break
            case .authorized:
                callBack?(true as AnyObject)
                break
            case .restricted:
                self.alertPromptToAllowCameraAccessViaSetting(accessType: "Library")
                break
            case .notDetermined:
                self.alertPromptToAllowCameraAccessViaSetting(accessType: "Library")
                break
            @unknown default:
                 break
            }
        })
    }
    
    func alertPromptToAllowCameraAccessViaSetting(accessType: String) {
        
        let alert = UIAlertController(title: "Access to \(accessType) is restricted", message: "You need to enable access to \(accessType). Apple Settings > Privacy > \(accessType).", preferredStyle: UIAlertController.Style.alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .default))
        alert.addAction(UIAlertAction(title: "Settings", style: .cancel) { (alert) -> Void in
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
        })
        
        self.present(alert, animated: true)
    }
    
    func generateThumnail(url : URL, fps: SharedInstance.completionHandler?, thumbnail: SharedInstance.completionHandler?) {
        
        let asset: AVAsset = AVAsset(url: url)
        let frame = self.getFramePerSecond(asset: asset)
        if let sendFrame = fps {
            sendFrame(frame as AnyObject)
        }
        let assetImgGenerate : AVAssetImageGenerator = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        let time  : CMTime = CMTimeMake(value: 1, timescale: 30)
        let img   : CGImage
        
        if let thumb = thumbnail {
            do {
                try img = assetImgGenerate.copyCGImage(at: time, actualTime: nil)
                let frameImg: UIImage = UIImage(cgImage: img)
                thumb(frameImg as AnyObject)
            } catch {
                print(error.localizedDescription)
                thumb(error.localizedDescription as AnyObject)
            }
        }
    }
    
    func getFramePerSecond(asset: AVAsset) -> Float {
        
        let tracks = asset.tracks(withMediaType: .video)
        guard tracks.count > 0 else { return 0.0 }
        
        guard let fps = tracks.first?.nominalFrameRate else { return 0.0 }
        return fps
    }
    
    func addTextOnLayer(videoSize: CGSize, textValue: String) -> CALayer {
        
        // Adding watermark text
        let titleLayer = CATextLayer()
        titleLayer.backgroundColor = UIColor.black.withAlphaComponent(0.5).cgColor
        titleLayer.string = textValue
        titleLayer.font = UIFont(name: "Helvetica-Bold", size: 25)
        titleLayer.alignmentMode = CATextLayerAlignmentMode.center
        titleLayer.frame = CGRect(x: 0, y: videoSize.height / 2, width: videoSize.width, height: 60)
        
        // 2 - The usual overlay
        let overlayLayer = CALayer()
        overlayLayer.addSublayer(titleLayer)
        overlayLayer.frame = CGRect(x: 0, y: 0, width: videoSize.width, height: videoSize.height)
        overlayLayer.masksToBounds = true
        overlayLayer.backgroundColor = UIColor.clear.cgColor

        return overlayLayer
    }
}

extension UIImage {
     func imageWithLayer(layer: CALayer) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(layer.bounds.size, layer.isOpaque, 0.0)
        layer.render(in: UIGraphicsGetCurrentContext()!)
        guard let img = UIGraphicsGetImageFromCurrentImageContext() else { return UIImage() }
        UIGraphicsEndImageContext()
        return img
    }
}
