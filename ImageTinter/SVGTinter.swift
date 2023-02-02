//
//  SVGTinter.swift
//  ImageTinter
//
//  Created by vino on 2023/1/31.
//

import SwiftSoup
import RxSwift
import RxRelay
import AppKit

class ImageInfo {
    var url: URL?
    var color: NSColor?
    var image: NSImage?
    var dom: String
    
    init(url: URL? = nil, color: NSColor? = nil, image: NSImage? = nil, dom: String) {
        self.url = url
        self.color = color
        self.image = image
        self.dom = dom
    }
}

class SVGTinter {
    let pathExtension = "svg"
    let tintedPathExtension = "pdf"
    var toolPath: String {
        get {
            let defaultPath = "/usr/local/bin/rsvg-convert"
            if let toolPath = UserDefaults.standard.object(forKey: "ToolPath") as? String {
                return toolPath
            }
            return defaultPath
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "ToolPath")
            UserDefaults.standard.synchronize()
        }
    }
    
    let logs = BehaviorRelay<String>(value: "")
    
    var sourceImages: [ImageInfo] = []
    var tintedSVGString: [String: ImageInfo] = [:]
    var tintedURLs: [URL] = []
        
    lazy var cacheURL: URL = {
        var svgPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!
        
        if !svgPath.hasPrefix("file://") {  
            svgPath.insert(contentsOf: "file://", at: svgPath.startIndex)
        }
        guard var url = URL(string: svgPath) else {
            logs.accept("缓存目录不存在")
            fatalError("无缓存目录")
        }
        url.appendPathComponent("ImageTinter", conformingTo: .directory)
        try? FileManager.default.createDirectory(atPath: url.path, withIntermediateDirectories: false)
        return url
    }()
        
    /// 从svg文件提取颜色
    private func pickColor(from url: URL) -> NSColor? {
        do {
            let domString = try String(contentsOf: url)
            return pickColor(from: domString)
        } catch {
            logs.accept("读取svg失败：\(error)")
        }
        return nil
    }
    
    private func pickColor(from svgDom: String) -> NSColor? {
        do {
            let dom = try SwiftSoup.parse(svgDom)
            let pathElements = try dom.select("path")
            for e in pathElements {
                if let colorHexString = try? e.attr("fill") {
                    return NSColor(hexString: colorHexString)
                }
            }
        } catch {
            logs.accept("提取svg颜色失败: \(error)")
        }
        return nil
    }
    
    private func makeImageInfo(from url: URL) -> ImageInfo? {
        if let data = try? Data(contentsOf: url),
           let string = data.string(encoding: .utf8),
           let image = NSImage(data: data) {
            let color = pickColor(from: string)
            return ImageInfo(url: url, color: color, image: image, dom: string)
        }
        return nil
    }

    /// 扫描图片
    func scanImages(_ URLs: [URL]) -> [ImageInfo] {
        let sourceURLs = URLs.sorted(by: \.lastPathComponent)
        sourceImages = sourceURLs.compactMap {
            return makeImageInfo(from: $0)
        }
        return sourceImages
    }
                
    func tint(_ tintColor: NSColor?, autoPickColor: Bool = true) -> [ImageInfo] {
        clean()
        tintedSVGString = sourceImages
            .compactMap { imageInfo in
                if autoPickColor {
                    if let color = imageInfo.color,
                       let tintedColor = ColorConfig.shared.tintedColor(with: color) {
                        return parseAndTint(imageInfo, tintColor: tintedColor)
                    }
                } else if let tintedColor = tintColor{
                    return parseAndTint(imageInfo, tintColor: tintedColor)
                }
                return nil
            }
            .reduce([:]) { result, item in
                return result.merging(item, uniquingKeysWith: { k1, k2 in return k2 })
            }
        
        return tintedSVGString
            .map { $0.0 }
            .sorted(by: \.lastPathComponent)
            .compactMap {
                tintedSVGString[$0]
            }
    }
    
    private func parseAndTint(_ imageInfo: ImageInfo, tintColor: NSColor) -> [String: ImageInfo] {
        do {
            guard let url = imageInfo.url else { return [:] }
            let dom = try SwiftSoup.parse(imageInfo.dom)
            let pathElements = try dom.select("path")
            for e in pathElements {
                try e.attr("fill", tintColor.hexString)
            }
            let string = try dom.select("svg").toString()
            let fileName = makeTintedFileName(url, suffix: suffix(tintedColor: tintColor))
            
            var image: NSImage? = nil
            if let data = string.data(using: .utf8) {
                image = NSImage(data: data)
            }
            return [fileName: ImageInfo(color: tintColor, image: image, dom: string)]
        } catch {
            logs.accept("解析SVG失败, error: \(error)")
        }
        return [:]
    }
    
    func suffix(tintedColor: NSColor)-> String {
        return "_" + tintedColor.hexString.removingPrefix("#")
    }
    
    private func writeAllCache() {
        clean()
        logs.accept("保存临时文件至：\(cacheURL)")
        tintedSVGString.forEach { (fileName, imageInfo) in
            var svgURL = cacheURL
            svgURL.appendPathComponent(fileName)
            svgURL.appendPathExtension(pathExtension)
            tintedURLs.append(svgURL)
            writeCache(imageInfo.dom, url: svgURL)
        }
    }
    
    private func writeCache(_ svgString: String, url: URL) {
        do {
            try svgString.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logs.accept("保存SVG失败error: \(error)")
        }
    }
    
    func makeTintedFileName(_ source: URL, suffix: String) -> String {
        var fileUrl = source
        if !fileUrl.pathExtension.isEmpty {
            fileUrl.deletePathExtension()
        }
        let fileName = fileUrl.lastPathComponent
        return fileName + suffix
    }
    
    func save(on dir: URL) {
        saveSourceFileToPDF(on: dir)
        saveTintedFileToPDF(on: dir)
    }
    
    private func saveSourceFileToPDF(on dir: URL) {
        guard let svgDirPath = sourceImages.first?.url?.absoluteString.removingPrefix("file://").deletingLastPathComponent else {
            return
            
        }
        convertAllSVGToPDF(urls: sourceImages.compactMap(by: \.url), on: dir, svgDirPath: svgDirPath)
    }
    
    private func saveTintedFileToPDF(on dir: URL) {
        let svgDirPath = cacheURL.absoluteString.removingPrefix("file://")
        writeAllCache()
        convertAllSVGToPDF(urls: tintedURLs, on: dir, svgDirPath: svgDirPath)
    }
    
    private func convertAllSVGToPDF(urls: [URL], on dir: URL, svgDirPath: String) {
        urls.forEach { fileUrl in
            var newFileUrl = dir.appendingPathComponent(fileUrl.lastPathComponent).deletingPathExtension()
            newFileUrl.appendPathExtension(for: .pdf)
            convertToPDF(svgUrl: fileUrl, pdfUrl: newFileUrl, svgDirPath: svgDirPath)
        }
    }
    
    private func convertToPDF(svgUrl: URL, pdfUrl: URL, svgDirPath: String) {

        let op = shell("cd \(svgDirPath)")
        logs.accept(op)

        let pwd = shell("pwd")
        logs.accept(pwd)

        let fileName = svgUrl.lastPathComponent
        let pdfPath = pdfUrl.absoluteString.removingPrefix("file://")
        let svgPath = svgDirPath.appendingPathComponent(fileName)

        let toolPath = shell("which rsvg-convert")
        if toolPath.isEmpty {
            logs.accept("找不到libsvg路径，请配置正确路径")
        }
        /// 不能使用带有空格的目录！
            let commond = "\(self.toolPath) -d 72 -p 72 -f pdf -o \(pdfPath) \(svgPath)"
        logs.accept("commonad: \(commond)")

        let op2 = shell(commond)
        logs.accept(op2)
    }
    
    func move(to url: URL) {
        guard !tintedURLs.isEmpty else { return }
        tintedURLs.forEach { fileURL in
            let fileName = fileURL.lastPathComponent
            let newURL = url.appendingPathComponent(fileName)
            try? FileManager.default.moveItem(at: fileURL, to: newURL)
        }
    }
    
    func clean() {
        cleanDiskCache()
        tintedURLs.removeAll()
    }
    
    func cleanDiskCache() {
        let path = cacheURL.absoluteString.removingPrefix("file://")
        let subpath = (try?FileManager.default.subpathsOfDirectory(atPath: path)) ?? []
        
        subpath.forEach { fileName in
            let filePath = path.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(atPath: filePath.removingPrefix("file://"))
        }
    }
}

extension SVGTinter {
    func shell(_ command: String) -> String {

        let task = Process()

        task.launchPath = "/bin/zsh"

        task.arguments = ["-c", command]
        let pipe = Pipe()

        task.standardOutput = pipe

        task.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        let output: String = NSString(data: data, encoding: String.Encoding.utf8.rawValue)! as String
        return output
    }
}
