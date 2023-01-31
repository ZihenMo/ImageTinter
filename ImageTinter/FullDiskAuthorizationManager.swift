//
//  DiskAuthorization.swift
//  ImageTinter
//
//  Created by vino on 2023/1/19.
//

import Foundation
import RxSwift
import Cocoa
import RxCocoa

public enum FullDistakAuthorizationStatus {
    case authorized
    case denined
    case unspecified
}


public class FullDiskAuthorizationManager {
    
    static let shared = FullDiskAuthorizationManager()
    
    private let manager = FileManager()
    
    private init() {
        
    }
    
    var authrizationStatus: Observable<FullDistakAuthorizationStatus> {
        return .create { observer in
            observer.onNext(self.getAuthorizationStatus())
            return Disposables.create()
        }
    }
        
    /// 沙盒环境用户Home目录
    private var sandboxedHomePath: String {
        let pw = getpwuid(getuid())
        let home = pw?.pointee.pw_dir
        assert(home != nil)
        return FileManager.default.string(withFileSystemRepresentation: home!, length: Int(strlen(home!)))
    }
    
    /// 依据Library/Safari目录进行判断授权状态
    /// 1. 如果存在该目录且有配置文件则已授权；
    /// 2. 如果仅有目录则已拒绝；
    /// 3. 其他情况未指定。
    func getAuthorizationStatus() -> FullDistakAuthorizationStatus {
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        var homePath = isSandboxed ? sandboxedHomePath : NSHomeDirectory()
        debugPrint("沙盒环境：\(isSandboxed)， home: \(homePath)")
        
        let configPath = homePath.appendingPathComponent("Library/Safari")
        let exists = FileManager.default.fileExists(atPath: configPath)
        let configSubpaths = (try? FileManager.default.contentsOfDirectory(atPath: configPath)) ?? []
        debugPrint("Safari子目录:\(configSubpaths)")
        
        if exists, !configSubpaths.isEmpty {
            return .denined
        } else if exists {
            return .authorized
        } else {
            return .unspecified
        }
    }
    
    /// 请求授权
    @available(macOS 10.14, *)
    public func requestAuthorization() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            debugPrint("全盘访问授权文件不存在")
            return
        }
        NSWorkspace.shared.open(url)
    }
    
    public func autoRequestAuthorizationStatus() -> FullDistakAuthorizationStatus {
        let status = getAuthorizationStatus()
        if status != .authorized {
            requestAuthorization()
            return getAuthorizationStatus()
        }
        return status
    }
}
