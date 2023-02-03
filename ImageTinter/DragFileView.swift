//
//  DragFileView.swift
//  ImageTinter
//
//  Created by vino on 2023/1/30.
//

import AppKit
import SnapKit

protocol DragFileViewDelegate: AnyObject {
    func dragFileView(_ view: DragFileView, didDroped url: URL)
}

class DragFileView: NSTableView {
    
    let draggedType: [NSPasteboard.PasteboardType] = [.fileURL]
    
    weak var draggedDelegate: DragFileViewDelegate?
    override func awakeFromNib() {
        super.awakeFromNib()
        self.registerForDraggedTypes(draggedType)
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        debugPrint("- 进入目标区")
        let sourceDragMask = sender.draggingSourceOperationMask
        let pboard = sender.draggingPasteboard
        if containsRegisterdDraggedType(types: pboard.types) {
            if sourceDragMask.contains(.link) {
                return .link
            } else if sourceDragMask.contains(.copy) {
                return .copy
            }
        }
        return .generic
    }
    
    func containsRegisterdDraggedType(types: [NSPasteboard.PasteboardType]?) -> Bool {
        return types?.contains(where: { type in registeredDraggedTypes.contains(where: { $0 == type }) }) ?? false
    }
    
    
//    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
//        let pboard = sender.draggingPasteboard
//        debugPrint("drop type: \(String(describing: pboard.types))")
//        if containsRegisterdDraggedType(types: pboard.types) {
//            let imagePath = pboard.propertyList(forType: draggedType.first!)
//            if let filePath = imagePath as? String, let url = URL(string: filePath) {
//                draggedDelegate?.dragFileView(self, didDroped: url)
//            }
//        }
//        return true
//    }
}


class ImageCellView: NSTableCellView {
    lazy var iconView: NSImageView = {
        let view = NSImageView()
        return view
    }()
    
    var colorLabel: NSTextField = {
        let view = NSTextField()
        view.drawsBackground = false
        view.isBordered = false
        view.textColor = .black
        view.isEditable = false
        return view
    }()
    
    var nameLabel: NSTextField = {
        let view = NSTextField()
        view.drawsBackground = false
        view.isBordered = false
        view.textColor = .black
        view.isEditable = false
        return view
    }()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        makeUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func makeUI() {
        addSubviews([iconView, nameLabel, colorLabel])
        
        iconView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().inset(15)
        }
        nameLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(iconView.snp.bottom).offset(8)
        }
        
        colorLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(nameLabel.snp.bottom).offset(2)
            make.bottom.equalToSuperview().inset(15)
        }
    }
}
