//
//  ViewController.swift
//  ImageTinter
//
//  Created by vino on 2023/1/17.
//

import AppKit
import UniformTypeIdentifiers
import Cocoa
import SwifterSwift

class ViewController: NSViewController {
    
    
    @IBOutlet weak var tableView: DragFileView!
    
    @IBOutlet weak var saveButton: NSButton!
    @IBOutlet weak var colorButton: NSButton!
    @IBOutlet weak var colorLabel: NSTextField!
    
    var tinter = Tinter()
    
    let sourceId = NSUserInterfaceItemIdentifier("source")
    let destinationId = NSUserInterfaceItemIdentifier("destination")
    
    var sourceURLs: [URL] = []
    var sourceImages: [NSImage] = []
    var destinationImages: [NSImage] = []
    var selectedColor: NSColor?
    
    var suffix: String {
        if var hexString = selectedColor?.hexString {
            hexString.removeFirst()
            return "_" + hexString
        }
        return "_dark"
    }

    
    private lazy var colorPanel: NSColorPanel = {
        let colorPanel = NSColorPanel()
        colorPanel.mode = .RGB
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorPanelSelectedColor(_:)))
        return colorPanel
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.draggedDelegate = self
        tableView.delegate = self
        tableView.dataSource = self
        
    }
        
    @IBAction func selectSourcePath(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.allowedFileTypes = ["pdf"]
        openPanel.allowedContentTypes = [UTType.init(filenameExtension: "pdf")!]
        openPanel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK {
                let fileURLs = openPanel.urls
                self.scanImages(fileURLs)
            }
        }
    }
    
    @IBAction func selectDestinationPath(_ sender: Any) {
        if destinationImages.count == 1 {
            saveSingleFile()
        } else if destinationImages.count > 1 {
            saveMultipleFile()
        }
    }
    
    private func saveSingleFile() {
        guard let image = destinationImages.first else {
            return
        }
        let savePanel = NSSavePanel()
        savePanel.title = "保存文件"
        savePanel.allowedContentTypes = [.init(filenameExtension: "pdf")!]
        let name = tinter.makeTintedFileName(sourceURLs.first!, suffix: suffix)
        savePanel.nameFieldStringValue = name
        savePanel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK {
                guard let url = savePanel.url else { return }
                debugPrint("保存至:\(url.relativeString)")
                self.tinter.save(image, on: url)
            }
        }
    }
    
    private func saveMultipleFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "保存至"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK {
                if let dir = openPanel.urls.first {
                    let fileNames = self.destinationImages.enumerated().map { i, image in
                        return self.tinter.makeTintedFileName(self.sourceURLs[i], suffix: self.suffix)
                    }
                    self.tinter.save(self.destinationImages, directory: dir, fileNames: fileNames)
                }
            }
        }
    }
    
    
    @IBAction func selectColor(_ sender: Any) {
        if let selectedColor = selectedColor {
            colorPanel.color = selectedColor
        }
        colorPanel.orderFront(nil)
    }
    
    @objc func colorPanelSelectedColor(_ sender: NSColorPanel) {
        selectedColor = sender.color
        colorButton.backgroundColor = selectedColor
        colorLabel.stringValue = selectedColor?.hexString ?? ""
        processPreview()
    }
    
    func scanImages(_ URLs: [URL]) {
        guard !URLs.isEmpty else { return }
        
        let imageURLs = recognizeImageURLs(URLs)
        sourceURLs = imageURLs
        sourceImages = imageURLs.compactMap {
            return NSImage(contentsOf: $0)
        }
        
        if selectedColor != nil {
            processPreview()
        } else {        
            tableView.reloadData()
        }
    }
    
    private func isDirectory(_ URL: URL) -> Bool {
        let path = URL.relativePath
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }
    
    private func filterImageURLs(_ URLs: [URL]) -> [URL] {
        return URLs.filter {
            $0.pathExtension == tinter.pathExtension
        }
    }
    
    /// 识别目录(只允许选一个目录)
    /// 识别文件，筛选出pdf后缀的文件
    private func recognizeImageURLs(_ URLs: [URL]) -> [URL] {
        guard !URLs.isEmpty else { return [] }
        if URLs.count == 1, let url = URLs.first {
            if isDirectory(url) {
                let subPaths = ((try? FileManager.default.contentsOfDirectory(atPath: url.relativePath)) ?? [])
                let subURLs = subPaths.compactMap({ URL(string:$0, relativeTo: url) })
                return filterImageURLs(subURLs)
            } else {
                return filterImageURLs([url])
            }
        } else {
            return filterImageURLs(URLs)
        }
    }
    
    func processPreview() {
        guard let selectedColor = selectedColor else { return }
        saveButton.isEnabled = true
        destinationImages = tinter.tint(images: sourceImages, tintColor: selectedColor)
        tableView.reloadData()
    }
}

extension ViewController: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return sourceImages.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        switch tableColumn?.identifier {
        case sourceId:
            return sourceImages[safe: row]
        case destinationId:
            return destinationImages[safe: row]
        default:
            return nil
        }
    }
}

extension ViewController: NSTableViewDelegate {
    
}

extension ViewController: DragFileViewDelegate {
    func dragFileView(_ view: DragFileView, didDroped url: URL) {
        let imageUrls = recognizeImageURLs([url])
        scanImages(imageUrls)
    }
}

