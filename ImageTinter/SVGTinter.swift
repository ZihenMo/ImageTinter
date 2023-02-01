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

protocol Tinter {
    func scanImages(_ URLs: [URL]) -> [NSImage]
    
    func tint(_ tintColor: NSColor) -> [NSImage]
    
    func save(on url: URL)
}


class SVGTinter: Tinter {
    let pathExtension = "svg"
    let tintedPathExtension = "pdf"
    
    let logs = BehaviorRelay<String>(value: "")
    
    var sourceURLs: [URL] = []
    var tintedSVGString: [String: String] = [:]
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
        
    func scanImages(_ URLs: [URL]) -> [NSImage] {
        sourceURLs = URLs
        return URLs.compactMap {
            NSImage(contentsOf: $0)
        }
    }

    func tint(_ tintColor: NSColor) -> [NSImage] {
        clean()
        tintedSVGString = sourceURLs.map { url -> [String: String] in
            parseAndTint(url, tintColor: tintColor)
        }.reduce([:]) { result, item in
            return result.merging(item, uniquingKeysWith: { k1, k2 in return k2 })
        }
        return tintedSVGString
            .compactMap { (_, string) in
                if let data = string.data(using: .utf8) {
                    return NSImage(data: data)
                }
                return nil
            }
    }
    
    private func parseAndTint(_ url: URL, tintColor: NSColor) -> [String: String] {
        do {
            let domString = try String(contentsOf: url)
            let dom = try SwiftSoup.parse(domString)
            let pathElements = try dom.select("path")
            for e in pathElements {
                try e.attr("fill", tintColor.hexString)
            }
            let string = try dom.select("svg").toString()
            let hexString = tintColor.hexString.removingPrefix("#")
            let fileName = makeTintedFileName(url, suffix: "_" + hexString)
            return [fileName: string]
        } catch {
            logs.accept("解析SVG失败, error: \(error)")
        }
        return [:]
    }
    
    private func writeAllCache() {
        clean()
        logs.accept("保存临时文件至：\(cacheURL)")
        tintedSVGString.forEach { (fileName, string) in
            var svgURL = cacheURL
            svgURL.appendPathComponent(fileName)
            svgURL.appendPathExtension(pathExtension)
            tintedURLs.append(svgURL)
            writeCache(string, url: svgURL)
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
        guard let svgDirPath = sourceURLs.first?.absoluteString.removingPrefix("file://").deletingLastPathComponent else { return }
        convertAllSVGToPDF(urls: sourceURLs, on: dir, svgDirPath: svgDirPath)
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

        /// 不能使用带有空格的目录！
        let commond = "/usr/local/bin/rsvg-convert -d 72 -p 72 -f pdf -o \(pdfPath) \(svgPath)"
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
