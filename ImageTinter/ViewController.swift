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
import RxRelay
import RxSwift

class ViewController: NSViewController {
    let disposeBag = DisposeBag()
    
    @IBOutlet weak var tableView: DragFileView!
    
    @IBOutlet weak var saveButton: NSButton!
    @IBOutlet weak var colorButton: NSButton!
    @IBOutlet weak var colorLabel: NSTextField!
    
    var tinter = SVGTinter()
        
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

    lazy var colorPanel: NSColorPanel = {
        let colorPanel = NSColorPanel.shared
        colorPanel.mode = .RGB
        colorPanel.isContinuous = false
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorPanelSelectedColor(_:)))
        return colorPanel
    }()
    
    lazy var logPanel: LogPanel = {
        let panel = LogPanel(
            contentRect: self.view.bounds,
            styleMask: .closable,
            backing: .buffered,
            defer: true
        )
        return panel
    }()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.draggedDelegate = self
        tableView.delegate = self
        tableView.dataSource = self
        
        bind()
    }
    
    func bind() {
        tinter
            .logs
            .subscribe(onNext: { log in
                print(log)
            })
            .disposed(by: disposeBag)
        
        tinter
            .logs
            .subscribe(onNext: { [weak self] log in
                guard let self = self else { return }
                let string = self.logPanel.textView.string
                self.logPanel.textView.string = string + "\n" + log
            })
        .disposed(by: disposeBag)
        
    }
        
    @IBAction func selectSourcePath(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.allowedFileTypes = [tinter.pathExtension]
        openPanel.allowedContentTypes = [UTType.init(filenameExtension: tinter.pathExtension)!]
        openPanel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK {
                let fileURLs = openPanel.urls
                 self.scanImages(fileURLs)
            }
        }
    }
    
    @IBAction func selectDestinationPath(_ sender: Any) {
        save()
    }
    
    private func save() {
        let openPanel = NSOpenPanel()
        openPanel.title = "保存至"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.begin {  [weak self] response in
            guard let self = self else { return }
            if response == .OK {
                if let dir = openPanel.urls.first {
                    self.tinter.save(on: dir)
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
        sourceImages = tinter.scanImages(imageURLs)
    
        if selectedColor != nil {
            processPreview()
        } else {        
            tableView.reloadData()
        }
    }
    
    @IBAction func openLogPannel(_ sender: NSButton) {
        let open = !logPanel.isVisible
        sender.title = open ? "关闭" : "打开"
        open ? logPanel.orderFront(nil) : logPanel.orderOut(nil)
        logPanel.center()
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
        destinationImages = tinter.tint(selectedColor)
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


class LogPanel: NSPanel {
    lazy var textView = NSTextView()
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        makeUI()
    }
    
    func makeUI() {
        textView.window?.title = "日志"
        textView.isEditable = false
        self.contentView?.addSubview(textView)
        if let contentView = contentView {
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40).isActive = true
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40).isActive = true
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40).isActive = true
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40).isActive = true
        }
    }
}
