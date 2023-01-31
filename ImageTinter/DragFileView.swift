//
//  DragFileView.swift
//  ImageTinter
//
//  Created by vino on 2023/1/30.
//

import Foundation
import AppKit

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
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        debugPrint("drop type: \(String(describing: pboard.types))")
        if containsRegisterdDraggedType(types: pboard.types) {
            let imagePath = pboard.propertyList(forType: draggedType.first!)
            if let filePath = imagePath as? String, let url = URL(string: filePath) {
                draggedDelegate?.dragFileView(self, didDroped: url)
            }
        }
        return true
    }
}
