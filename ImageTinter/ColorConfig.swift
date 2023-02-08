//
//  ColorConfig.swift
//  ImageTinter
//
//  Created by vino on 2023/2/2.
//

import Foundation
import RxRelay

class ColorConfig {
    
    var log = BehaviorRelay<String>(value: "")
    
    private let defatultColors = [
        "#111114": "#ffffff",
        "#484852": "#484852",
        "#71717a": "#787c85",
        "#9d9da3": "#3c4047"
    ]
    
    private let configFileName = "ImageTinterColors.json"
    
    var colorPalette: [String: String] = [:]
    
    static let shared = ColorConfig()
    
    func load() {
        let configColor = loadCache()
        generateColorPalette(configColor)
    }
    
    private func loadCache() -> [String: String] {
        
        guard let userPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            log.accept("找不到用户文档目录")
            return [:]
        }
        let configPath = userPath.appendingPathComponent(configFileName)
        var exist: Bool = false
        exist = FileManager.default.fileExists(atPath: configPath)
        guard exist else {
            log.accept("配色文件不存在")
            return [:]
        }
        
        do {
            guard let configData = try String(contentsOfFile: configPath).data(using: .utf8) else {
                log.accept("读取配色文件失败, path:\(userPath)")
                return [:]
            }
            let configColor = try JSONDecoder().decode([String: String].self, from: configData)
            return configColor
        } catch {
            log.accept("读取配色文件失败, path: \(configPath)")
        }
        
        return [:]
    }
    
    private func generateColorPalette(_ configColor: [String: String]) {
        colorPalette.removeAll()
        let uniqueFilter: (String, String) -> String = { k1, k2 in
            return k2
        }
        let lowcaseConfigColor = configColor.mapKeysAndValues { (k, v) in
            return (k.lowercased(), v.lowercased())
        }
        colorPalette = defatultColors
        colorPalette.merge(lowcaseConfigColor, uniquingKeysWith: uniqueFilter)
    }
    
    
    func tintedColor(with originColor: NSColor) -> NSColor? {
        if let hexString = colorPalette[originColor.hexString.lowercased()] {
            return NSColor(hexString: hexString)
        }
        return nil
    }
}
