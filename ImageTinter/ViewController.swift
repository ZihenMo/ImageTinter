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
    
    @IBOutlet weak var autoColorButton: NSButton!
    @IBOutlet weak var customColorButton: NSButton!
    
    @IBOutlet weak var assetsField: NSTextField!
    @IBOutlet weak var toolPathField: NSTextField!
    var tinter = SVGTinter()
        
    let sourceId = NSUserInterfaceItemIdentifier("source")
    let destinationId = NSUserInterfaceItemIdentifier("destination")
    
    var sourceURLs: [URL] = []
    var sourceImages: [ImageInfo] = []
    var destinationImages: [ImageInfo] = []
    var selectedColor: NSColor = .white
    
    var suffix: String {
        return "_" + selectedColor.hexString.removingPrefix("#")
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
            styleMask: [.closable, .resizable, .titled],
            backing: .buffered,
            defer: true
        )
        return panel
    }()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        makeUI()
        bind()
        loadAssetsPath()
    }
    
    func loadAssetsPath() {
        if let assetsPath = UserDefaults.standard.object(forKey: "ImageAssetsPath") as? String {
            assetsField.stringValue = assetsPath
        }
    }
    
    func cacheAssetsPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: "ImageAssetsPath")
        UserDefaults.standard.synchronize()
    }
    
    func makeUI() {
        tableView.draggedDelegate = self
        tableView.delegate = self
        tableView.dataSource = self
        
        let sourceColumn = NSTableColumn(identifier: sourceId)
        let tintedColumn = NSTableColumn(identifier: destinationId)
        let columnWidth =  tableView.width / 2
        sourceColumn.width = columnWidth
        tintedColumn.width = columnWidth
        sourceColumn.title = "源"
        tintedColumn.title = "目标"
        
        tableView.addTableColumn(sourceColumn)
        tableView.addTableColumn(tintedColumn)
        
        toolPathField.stringValue = tinter.toolPath
    }
    
    func bind() {
        let logs = Observable<String>.merge(
            tinter.logs.asObservable().skip(1),
            ColorConfig.shared.log.asObservable().skip(1)
        )
        logs.subscribe(onNext: { [weak self] log in
            guard let self = self else { return }
            print(log)
            let string = self.logPanel.textView.string
            self.logPanel.textView.string = string + "\n" + log
        })
        .disposed(by: disposeBag)
        
        toolPathField.rx.text.changed.subscribe(onNext: { [weak self] _ in
            guard let self = self else { return }
            self.tinter.toolPath = self.toolPathField.stringValue
        }).disposed(by: disposeBag)
        
        customColorButton
            .rx
            .state
            .map {
                switch $0 {
                case .on:
                    return true
                default:
                    return false
                }
            }
            .bind(to: colorButton.rx.isEnabled)
            .disposed(by: disposeBag)
        
        autoColorButton
            .rx
            .state
            .filter { state in
                return state == .on
            }
            .subscribe(onNext: { [weak self] _ in
                self?.colorPanel.orderOut(nil)
                self?.colorButton.isEnabled = false
                self?.processPreview()
            })
            .disposed(by: disposeBag)
        
        customColorButton
            .rx
            .state
            .map {
                return $0 == .on ? .off : .on
            }
            .bind(to: autoColorButton.rx.state)
            .disposed(by: disposeBag)
        
        customColorButton
            .rx
            .state
            .filter {
                return $0 == .on
            }
            .subscribe(onNext: { [weak self] _ in
                self?.processPreview()
            })
            .disposed(by: disposeBag)
        
        colorLabel.rx.text.subscribe(onNext: { [weak self] colorHexString in
            if  let self = self,
                let colorHexString = colorHexString,
                let color = NSColor(hexString: colorHexString),
                self.selectedColor != color {
                self.selectedColor = color
                self.processPreview()
            }
            
        }).disposed(by: disposeBag)
                
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
        let assetsPath = assetsField.stringValue
        if assetsPath.isEmpty {
            save()
        } else if let url = URL(string: assetsPath.urlEncoded){
            self.cacheAssetsPath(assetsPath)
            self.tinter.save(on: url)
        } else {
            logPanel.textView.string += "assets目录不正确"
        }
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
        colorPanel.color = selectedColor
        colorPanel.orderFront(nil)
    }
    
    @objc func colorPanelSelectedColor(_ sender: NSColorPanel) {
        selectedColor = sender.color
        colorButton.backgroundColor = selectedColor
        colorLabel.stringValue = selectedColor.hexString
        processPreview()
    }
    
    func scanImages(_ URLs: [URL]) {
        guard !URLs.isEmpty else { return }
        
        let imageURLs = recognizeImageURLs(URLs)
        sourceURLs = imageURLs
        sourceImages = tinter.scanImages(imageURLs)
    
        processPreview()
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
    /// 识别文件，筛选出svg后缀的文件
    private func recognizeImageURLs(_ URLs: [URL]) -> [URL] {
        guard !URLs.isEmpty else { return [] }
        return URLs.reduce([]) { result, url in
            if isDirectory(url) {
                let dirEnum = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
                var subDir: [URL] = []
                while let nextUrl = dirEnum?.nextObject() as? URL {
                    subDir.append(nextUrl)
                }
                return result + filterImageURLs(subDir)
            } else {
                return result + filterImageURLs([url])
            }

        }
    }
    
    func processPreview() {
        if autoColorButton.state == .on {
            destinationImages = tinter.tint(nil, autoPickColor: true)
        } else {
            destinationImages = tinter.tint(selectedColor, autoPickColor: false)
        }
        saveButton.isEnabled = true
        tableView.reloadData()
    }
}

extension ViewController: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return sourceImages.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier else { return nil }
        let width: CGFloat = tableView.width / 2
        let height: CGFloat = 50
        let cell = ImageCellView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        switch id {
        case sourceId:
            let imageInfo = sourceImages[safe: row]
            cell.iconView.image = imageInfo?.image
            cell.colorLabel.stringValue = imageInfo?.color?.hexString ?? ""
            cell.nameLabel.stringValue = imageInfo?.fileName ?? ""
        case destinationId:
            let imageInfo = destinationImages[safe: row]
            cell.iconView.image = imageInfo?.image
            cell.nameLabel.stringValue = imageInfo?.fileName ?? ""
            cell.colorLabel.stringValue = imageInfo?.color?.hexString ?? ""
        default:
            return cell
        }
        return cell
    }
    
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        return .every
    }
    
    
    func containsRegisterdDraggedType(types: [NSPasteboard.PasteboardType]?) -> Bool {
        return types?.contains(where: { type in type == self.tableView.draggedType.first! }) ?? false
    }
    
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let pboard = info.draggingPasteboard
        debugPrint("drop type: \(String(describing: pboard.types))")
        if containsRegisterdDraggedType(types: pboard.types) {
            let urls = pboard.pasteboardItems?.reduce([]){ result, item in
                let path = item.propertyList(forType: self.tableView.draggedType.first!) as? String
                if let url = URL(string: path) {
                    return result + [url]
                }
                return result
            } as? [URL]
            if let urls = urls{
                scanImages(urls)
            }
        }
        return true
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
    
    lazy var scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        
        return scrollView
    }()
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        makeUI()
    }
    
    func makeUI() {
        textView.isVerticallyResizable = true
        textView.font = .systemFont(ofSize: 14)
        textView.window?.title = "日志"
        textView.isEditable = false
        scrollView.documentView = textView
        textView.autoresizingMask = .width
        textView.minSize = CGSize(width: 400, height: 600)
        
        if let scrollView = textView.enclosingScrollView, let contentView = contentView {
            contentView.addSubview(scrollView)
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40).isActive = true
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40).isActive = true
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40).isActive = true
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40).isActive = true
        }
    }
}


