//
//  MGalleryPhotoItem.swift
//  TelegramMac
//
//  Created by keepcoder on 15/12/2016.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa
import TelegramCoreMac
import PostboxMac
import SwiftSignalKitMac
import TGUIKit

class MGalleryPhotoItem: MGalleryItem {
    
    let media:TelegramMediaImage
    let secureIdAccessContext: SecureIdAccessContext?
    private let representation:TelegramMediaImageRepresentation
    override init(_ context: AccountContext, _ entry: GalleryEntry, _ pagerSize: NSSize) {
        switch entry {
        case .message(let entry):
            if let webpage =  entry.message!.media[0] as? TelegramMediaWebpage {
                if case let .Loaded(content) = webpage.content, let image = content.image {
                    self.media = image
                } else if case let .Loaded(content) = webpage.content, let media = content.file  {
                    let represenatation = TelegramMediaImageRepresentation(dimensions: media.dimensions ?? NSZeroSize, resource: media.resource)
                    var representations = media.previewRepresentations
                    representations.append(represenatation)
                    self.media = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 0), representations: representations, immediateThumbnailData: nil, reference: nil, partialReference: nil)
                    
                } else {
                    fatalError("image for webpage not found")
                }
            } else {
                if let media = entry.message!.media[0] as? TelegramMediaFile {
                    let represenatation = TelegramMediaImageRepresentation(dimensions: media.dimensions ?? NSZeroSize, resource: media.resource)
                    var representations = media.previewRepresentations
                    representations.append(represenatation)
                    self.media = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 0), representations: representations, immediateThumbnailData: nil, reference: nil, partialReference: nil)
                } else {
                    self.media = entry.message!.media[0] as! TelegramMediaImage
                }
            }
            secureIdAccessContext = nil
        case .instantMedia(let media, _):
            self.media = media.media as! TelegramMediaImage
            secureIdAccessContext = nil
        case let .secureIdDocument(document, _):
            self.media = document.image
            self.secureIdAccessContext = document.context
        default:
            fatalError("photo item not supported entry type")
        }
        
        self.representation = media.representations.last!
        super.init(context, entry, pagerSize)
    }
    
    
    override var sizeValue: NSSize {
        if let largest = media.representations.last {
            if let modifiedSize = modifiedSize {
                return modifiedSize.fitted(pagerSize)
            }
            return largest.dimensions.fitted(pagerSize)
        }
        return NSZeroSize
    }
    
    override func smallestValue(for size: NSSize) -> NSSize {
        if let largest = media.representations.last {
            if let modifiedSize = modifiedSize {
                let lhsProportion = modifiedSize.width/modifiedSize.height
                let rhsProportion = largest.dimensions.width/largest.dimensions.height
                
                if lhsProportion != rhsProportion {
                    return modifiedSize.fitted(size)
                }
            }
            return largest.dimensions.fitted(size)
        }
        return pagerSize
    }
    
    override var status:Signal<MediaResourceStatus, NoError> {
        return chatMessagePhotoStatus(account: context.account, photo: media)
    }
    
    private var hasRequested: Bool = false
    
    override func request(immediately: Bool) {
        if !hasRequested {
            let context = self.context
            let entry = self.entry
            let media = self.media
            let secureIdAccessContext = self.secureIdAccessContext
            
            let sizeValue = size.get() |> distinctUntilChanged(isEqual: { lhs, rhs -> Bool in
                return lhs == rhs
            })
            
            let rotateValue = rotate.get() |> distinctUntilChanged(isEqual: { lhs, rhs -> Bool in
                return lhs == rhs
            })
            
            let result = combineLatest(sizeValue, rotateValue) |> mapToSignal { [weak self] size, orientation -> Signal<(NSSize, ImageOrientation?), NoError> in
                guard let `self` = self else {return .complete()}
                
                var newSize = self.smallestValue(for: size)
                if let orientation = orientation {
                    if orientation == .right || orientation == .left {
                        newSize = NSMakeSize(newSize.height, newSize.width)
                    }
                }
                return .single((newSize, orientation))
                
            } |> mapToSignal { size, orientation -> Signal<NSImage?, NoError> in
                    return chatGalleryPhoto(account: context.account, imageReference: entry.imageReference(media), scale: System.backingScale, secureIdAccessContext: secureIdAccessContext, synchronousLoad: true)
                        |> map { transform in
                            let image = transform(TransformImageArguments(corners: ImageCorners(), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets()))
                            if let orientation = orientation {
                                let transformed = image?.createMatchingBackingDataWithImage(orienation: orientation)
                                if let transformed = transformed {
                                    return NSImage(cgImage: transformed, size: transformed.size)
                                }
                            }
                            if let image = image {
                                return NSImage(cgImage: image, size: image.size)
                            } else {
                                return nil
                            }
                    }
            }
            
            path.set(context.account.postbox.mediaBox.resourceData(representation.resource) |> mapToSignal { resource -> Signal<String, NoError> in
                if resource.complete {
                    return .single(link(path:resource.path, ext:kMediaImageExt)!)
                }
                return .never()
            })
            
            self.image.set(result |> map { .image($0) } |> deliverOnMainQueue)
            
            
            fetch()
            
            hasRequested = true
        }
        
    }
    
    override var backgroundColor: NSColor {
        return theme.colors.transparentBackground
    }
    
    override func fetch() -> Void {
         fetching.set(chatMessagePhotoInteractiveFetched(account: context.account, imageReference: entry.imageReference(media)).start())
    }
    
    override func cancel() -> Void {
        super.cancel()
        chatMessagePhotoCancelInteractiveFetch(account: context.account, photo: media)
    }
    
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
}
