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
    var size: Int?
    var fileName: String
    
    init(url: URL? = nil, color: NSColor? = nil, image: NSImage? = nil, size: Int? = nil, fileName: String, dom: String) {
        self.url = url
        self.color = color
        self.image = image
        self.size = size
        self.fileName = fileName
        self.dom = dom
    }
    
    func suffix() -> String {
        var colorString = ""
        if let color = color {
            colorString = "_" + color.hexString.removingPrefix("#")
        }
        var sizeString = ""
        if let size = size {
            sizeString = "_" + size.string
        }
        return sizeString + colorString
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
    var tintedSVGString: [ImageInfo] = []
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
    
    private func pickColorAndSize(from svgDom: String) -> (NSColor, Int)? {
        do {
            let dom = try SwiftSoup.parse(svgDom)
            let fillElements = try getFillElements(from: dom)
            var color: NSColor? = nil
            for e in fillElements {
                if let colorHexString = try? e.attr("fill") {
                    color = NSColor(hexString: colorHexString)
                    break
                }
            }
            let width = try dom.select("svg").attr("width").int
            if let color = color, let width = width {
                return (color, width)
            }
            return nil
        } catch {
            logs.accept("提取svg颜色失败: \(error)")
        }
        return nil
    }
    
    private func makeImageInfo(from url: URL) -> ImageInfo? {
        if let data = try? Data(contentsOf: url),
           let string = data.string(encoding: .utf8),
           let image = NSImage(data: data),
           let (color, size) = pickColorAndSize(from: string) {
            let fileName = url.lastPathComponent.deletingPathExtension
            return ImageInfo(url: url, color: color, image: image, size: size, fileName: fileName, dom: string)
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
    
    private func getFillElements(from dom: Document) throws -> [Element] {
         return try dom.getElementsByAttribute("fill").filter {
            $0.tagName().lowercased() != "svg"
        }
    }
    
    private func parseAndTint(_ imageInfo: ImageInfo, tintColor: NSColor) -> ImageInfo? {
        do {
            let dom = try SwiftSoup.parse(imageInfo.dom)
            let fillElements = try getFillElements(from: dom)
            for e in fillElements {
                try e.attr("fill", tintColor.hexString)
            }
            let string = try dom.select("svg").toString()
            var image: NSImage? = nil
            if let data = string.data(using: .utf8) {
                image = NSImage(data: data)
            }
            return ImageInfo(color: tintColor, image: image, size: imageInfo.size, fileName: imageInfo.fileName, dom: string)
        } catch {
            logs.accept("解析SVG失败, error: \(error)")
        }
        return nil
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
        
        return tintedSVGString
    }
    
    private func writeAllCache() {
        clean()
        logs.accept("保存临时文件至：\(cacheURL)")
        tintedSVGString.forEach { imageInfo in
            var svgURL = cacheURL
            svgURL.appendPathComponent(imageInfo.fileName + imageInfo.suffix())
            svgURL.appendPathExtension(pathExtension)
            imageInfo.url = svgURL
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
}

// MARK: - 保存
extension SVGTinter {
    func save(on dir: URL) {
        writeAllCache()
        sourceImages.forEach { info in
            var fileName = ""
            if let imagesetUrl = generateImageset(fileName: info.fileName + info.suffix(), assets: dir),
               let svgUrl = info.url {
                fileName = info.fileName + info.suffix()
                let pdfUrl = imagesetUrl.appendingPathComponent(fileName).appendingPathExtension(for: .pdf)
                convertToPDF(svgUrl: svgUrl, pdfUrl: pdfUrl)
                
                var tintedFileName = ""
                if let tintedInfo = tintedSVGString.first(where: { $0.fileName == info.fileName }),
                    let tintedSvgUrl = tintedInfo.url {
                    tintedFileName = tintedInfo.fileName + tintedInfo.suffix()
                    let tintedPdfUrl = imagesetUrl.appendingPathComponent(tintedFileName).appendingPathExtension(for: .pdf)
                    convertToPDF(svgUrl: tintedSvgUrl, pdfUrl: tintedPdfUrl)
                    
                }
                generateContentsJson(
                    fileName: fileName.appendingPathExtension(tintedPathExtension) ?? "",
                    tintedFileName: tintedFileName.appendingPathExtension(tintedPathExtension) ?? "",
                    imageset: imagesetUrl
                )
            }
        }
    }
    
    private func generateImageset(fileName: String, assets: URL) -> URL? {
        do {
            guard let path = assets.absoluteString.removingPrefix("file://").appendingPathComponent(fileName.deletingPathExtension).appendingPathExtension("imageset")?.urlDecoded else {
                logs.accept("生成imageassets失败, assets: \(assets), fileName: \(fileName)")
                return nil
            }
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            return URL(string: path.urlEncoded)
        } catch {
            logs.accept("生成imageassets失败, assets: \(assets), fileName: \(fileName), error:\(error)")
        }
        return nil
    }
    
    private func generateContentsJson(fileName: String, tintedFileName: String, imageset: URL) {
        let jsonString =
        """
        {
          "images" : [
            {
              "filename" : "\(fileName)",
              "idiom" : "universal"
            },
            {
              "appearances" : [
                {
                  "appearance" : "luminosity",
                  "value" : "dark"
                }
              ],
              "filename" : "\(tintedFileName)",
              "idiom" : "universal"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        
        var path = imageset.absoluteString.urlDecoded
        path = path.appendingPathComponent("Contents.json")
        do {
            try jsonString.write(toFile: path, atomically: true, encoding: .utf8)
            // url 带有空格和中文时，同时目录又是带后缀，无论怎么转义都无法写入
//            try jsonString.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logs.accept("写入ContentsJson失败, path: \(path): \(error)")
        }
    }
    
    
    private func saveSourceFileToPDF(on dir: URL) {
        convertAllSVGToPDF(urls: sourceImages.compactMap(by: \.url), on: dir)
    }
    
    private func saveTintedFileToPDF(on dir: URL) {
        writeAllCache()
        convertAllSVGToPDF(urls: tintedURLs, on: dir)
    }
    
    private func convertAllSVGToPDF(urls: [URL], on dir: URL) {
        urls.forEach { fileUrl in
            var newFileUrl = dir.appendingPathComponent(fileUrl.lastPathComponent).deletingPathExtension()
            newFileUrl.appendPathExtension(for: .pdf)
            convertToPDF(svgUrl: fileUrl, pdfUrl: newFileUrl)
        }
    }
    
    private func convertToPDF(svgUrl: URL, pdfUrl: URL) {

        let workPath = svgUrl.absoluteString.removingPrefix("file://").deletingLastPathComponent
        
        let op = shell("cd \"\(workPath.urlDecoded)\"")
        logs.accept(op)

        let pwd = shell("pwd")
        logs.accept(pwd)

        let pdfPath = pdfUrl.absoluteString.removingPrefix("file://")
        let svgPath = svgUrl.absoluteString.removingPrefix("file://")

        let toolPath = shell("which rsvg-convert")
        if toolPath.isEmpty {
            logs.accept("找不到libsvg路径，请配置正确路径")
        }
        /// 不能使用带有空格的目录！
        let commond = "\(self.toolPath) -d 72 -p 72 -f pdf -o \"\(pdfPath.urlDecoded)\" \"\(svgPath.urlDecoded)\""
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
