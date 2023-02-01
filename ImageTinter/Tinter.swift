//
//  Tinter.swift
//  ImageTinter
//
//  Created by vino on 2023/1/30.
//

import AppKit
import Cocoa
import Quartz

class PDFTinter {
    let pathExtension = "pdf"
    
    private let fullDiskAuthorizationManager = FullDiskAuthorizationManager.shared

    func scanImages(_ URLs: [URL]) -> [NSImage] {
        guard !URLs.isEmpty else { return [] }
        return URLs.compactMap {
            return NSImage(contentsOf: $0)
        }
    }
    
    func tint(imageURLs: [URL], tintColor: NSColor) -> [NSImage] {
        let images = imageURLs.compactMap {
            return NSImage(contentsOf: $0)
        }
        
        let tintedImages = images.map { image in
            tintedImage(image, tintColor: tintColor)
        }
        return tintedImages
    }
    
    func tint(images: [NSImage], tintColor: NSColor) -> [NSImage] {
        let tintedImages = images.map { image in
            tintedImage(image, tintColor: tintColor)
        }
        return tintedImages
    }
    
    func makeTintedFileURL(_ source: URL, suffix: String) -> URL {
        var fileUrl = source
        let fileName = makeTintedFileName(source, suffix: suffix)
        fileUrl.deleteLastPathComponent()
        fileUrl.appendPathComponent(fileName)
        fileUrl.appendPathExtension(pathExtension)
        return fileUrl
    }
    
    func makeTintedFileName(_ source: URL, suffix: String) -> String {
        var fileUrl = source
        if !fileUrl.pathExtension.isEmpty {
            fileUrl.deletePathExtension()
        }
        let fileName = fileUrl.lastPathComponent
        return fileName + suffix
    }
    
    public func save(_ images: [NSImage], directory: URL, fileNames: [String]) {
        images.enumerated().forEach { idx, image in
            guard let fileName = fileNames[safe: idx] else { return }
            let url = directory.appendingPathComponent(fileName, conformingTo: .pdf)
            save(image, on: url)
        }
    }
    
    func save(_ image: NSImage, on url: URL) {
        let pdf = createPDFDocument(image: image)
        pdf.write(to: url)
        
//        let data = createPDF(image: image) as Data
//        do {
//            try data.write(to: url)
//        } catch {
//            let alert = NSAlert()
//            alert.messageText = "保存文件失败，请添加全盘访问权限或更换目录再试"
//            alert.addButton(withTitle: "添加权限")
//            alert.addButton(withTitle: "稍后再说")
//            alert.beginSheetModal(for: NSApplication.shared.keyWindow!) { [weak self] code in
//                if code == .OK {
//                    self?.fullDiskAuthorizationManager.requestAuthorization()
//                }
//            }
//            debugPrint("保存pdf格式失败, error: \(error)")
//        }
    }
    
    func createPDFDocument(image: NSImage) -> PDFDocument {
        let pdfDocument = PDFDocument()
        let pdfPage = PDFPage(image: image)
        pdfDocument.insert(pdfPage!, at: 0)
        return pdfDocument
    }
    
    func createPDF(image: NSImage) -> NSData {
        let pdfData = NSMutableData()
        let pdfConsumer = CGDataConsumer(data: pdfData as CFMutableData)!
        var mediaBox = NSRect.init(x: 0, y: 0, width: image.size.width, height: image.size.height)
        let pdfContext = CGContext(consumer: pdfConsumer, mediaBox: &mediaBox, nil)!
        var imageRect = NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height)

        pdfContext.beginPage(mediaBox: &mediaBox)
        pdfContext.draw(
            image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)!,
            in: mediaBox
        )
        pdfContext.endPage()
        return pdfData
    }
    
    private func tintedImage(_ image: NSImage, tintColor: NSColor) -> NSImage {
        guard let tinted = image.copy() as? NSImage else { return image }
        tinted.lockFocus()
        tintColor.set()
        
        let doubleSize = CGSize(width: image.size.width * 2, height: image.size.height * 2)
        
        let imageRect = NSRect(origin: NSZeroPoint, size: doubleSize)
        imageRect.fill(using: .sourceAtop)
        
        tinted.unlockFocus()
        return tinted
    }
}
