//
//  AppDelegate.swift
//  ImageTinter
//
//  Created by vino on 2023/1/17.
//

import Cocoa
import SVGKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        avoidSVGKitBug()
        ColorConfig.shared.load()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        
    }
    
    func avoidSVGKitBug() {
        let template =
        """
        <svg width="24" height="24" viewbox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M6 9C6 8.44772 6.44772 8 7 8H8V7C8 6.44772 8.44772 6 9 6C9.55229 6 10 6.44772 10 7V8H11C11.5523 8 12 8.44772 12 9C12 9.55229 11.5523 10 11 10H10V11C10 11.5523 9.55228 12 9 12C8.44772 12 8 11.5523 8 11V10H7C6.44772 10 6 9.55229 6 9Z" fill="#FFA775" />
        <path d="M13 15C12.4477 15 12 15.4477 12 16C12 16.5523 12.4477 17 13 17H17C17.5523 17 18 16.5523 18 16C18 15.4477 17.5523 15 17 15H13Z" fill="#FFA775" />
        <path d="M7.55025 17.4497C7.15972 17.0592 7.15972 16.4261 7.55025 16.0355L16.0355 7.55025C16.4261 7.15973 17.0592 7.15973 17.4497 7.55025C17.8403 7.94078 17.8403 8.57394 17.4497 8.96446L8.96446 17.4497C8.57394 17.8403 7.94077 17.8403 7.55025 17.4497Z" fill="#FFA775" />
        <path fill-rule="evenodd" clip-rule="evenodd" d="M3 6C3 4.34315 4.34315 3 6 3H18C19.6569 3 21 4.34315 21 6V18C21 19.6569 19.6569 21 18 21H6C4.34315 21 3 19.6569 3 18V6ZM6 5C5.44772 5 5 5.44772 5 6V18C5 18.5523 5.44772 19 6 19H18C18.5523 19 19 18.5523 19 18V6C19 5.44772 18.5523 5 18 5H6Z" fill="#FFA775" />
        </svg>
        """
        _ = SVGKImage(data: template.data(using: .utf8))
    }
}

