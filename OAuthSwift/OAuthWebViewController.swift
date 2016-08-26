//
//  OAuthWebViewController.swift
//  OAuthSwift
//
//  Created by Dongri Jin on 2/11/15.
//  Copyright (c) 2015 Dongri Jin. All rights reserved.
//

import Foundation

#if os(iOS)  || os(tvOS)
    import UIKit
    public typealias OAuthViewController = UIViewController
#elseif os(watchOS)
    import WatchKit
    public typealias OAuthViewController = WKInterfaceController
#elseif os(OSX)
    import AppKit
    public typealias OAuthViewController = NSViewController
#endif

// Delegate for OAuthWebViewController
public protocol OAuthWebViewControllerDelegate {
    
    #if os(iOS) || os(tvOS)
    // Did web view presented (work only without navigation controller)
    func oauthWebViewControllerDidPresent()
    // Did web view dismiss (work only without navigation controller)
    func oauthWebViewControllerDidDismiss()
    #endif
    
    func oauthWebViewControllerWillAppear()
    func oauthWebViewControllerDidAppear()
    func oauthWebViewControllerWillDisappear()
    func oauthWebViewControllerDidDisappear()

}

// A web view controller, which handler OAuthSwift authentification.
open class OAuthWebViewController: OAuthViewController, OAuthSwiftURLHandlerType {
 
    #if os(iOS) || os(tvOS) || os(OSX)
    // Delegate for this view
    open var delegate: OAuthWebViewControllerDelegate?
    #endif

    #if os(iOS) || os(tvOS)
    // If controller have an navigation controller, application top view controller could be used if true
    open var useTopViewControlerInsteadOfNavigation = false
    
    open var topViewController: UIViewController? {
        #if !OAUTH_APP_EXTENSIONS
            return UIApplication.topViewController
        #else
            return nil
        #endif
    }
    #elseif os(OSX)
    // How to present this view controller if parent view controller set
    public enum Present {
        case AsModalWindow
        case AsSheet
        case AsPopover(relativeToRect: NSRect, ofView : NSView, preferredEdge: NSRectEdge, behavior: NSPopoverBehavior)
        case TransitionFrom(fromViewController: NSViewController, options: NSViewControllerTransitionOptions)
        case Animator(animator: NSViewControllerPresentationAnimator)
        case Segue(segueIdentifier: String)
    }
    public var present: Present = .AsModalWindow
    #endif
    
    open func handle(_ url: URL) {
        // do UI in main thread
        OAuthSwift.main { [unowned self] in
             self.doHandle(url)
        }
    }

    #if os(watchOS)
    public static var userActivityType: String = "org.github.dongri.oauthswift.connect"
    #endif

    open func doHandle(_ url: URL) {
        #if os(iOS) || os(tvOS)
            let completion: () -> Void = { [unowned self] in
                self.delegate?.oauthWebViewControllerDidPresent()
            }
            let animated = true
            if let navigationController = self.navigationController , (!useTopViewControlerInsteadOfNavigation || self.topViewController == nil) {
                navigationController.pushViewController(self, animated: animated)
            }
            else if let p = self.parent {
                p.present(self, animated: animated, completion: completion)
            }
            else if let topViewController = topViewController {
                topViewController.present(self, animated: animated, completion: completion)
            }
            else {
                // assert no presentation
            }
        #elseif os(watchOS)
            if (url.scheme == "http" || url.scheme == "https") {
                self.updateUserActivity(OAuthWebViewController.userActivityType, userInfo: nil, webpageURL: url)
            }
        #elseif os(OSX)
            if let p = self.parentViewController { // default behaviour if this controller affected as child controller
                switch self.present {
                case .AsSheet:
                    p.presentViewControllerAsSheet(self)
                    break
                case .AsModalWindow:
                    p.presentViewControllerAsModalWindow(self)
                    // FIXME: if we present as window, window close must detected and oauthswift.cancel() must be called...
                    break
                case .AsPopover(let positioningRect, let positioningView, let preferredEdge, let behavior):
                    p.presentViewController(self, asPopoverRelativeToRect: positioningRect, ofView : positioningView, preferredEdge: preferredEdge, behavior: behavior)
                    break
                case .TransitionFrom(let fromViewController, let options):
                    let completion: () -> Void = { /*[unowned self] in*/
                        //self.delegate?.oauthWebViewControllerDidPresent()
                    }
                    p.transitionFromViewController(fromViewController, toViewController: self, options: options, completionHandler: completion)
                    break
                case .Animator(let animator):
                    p.presentViewController(self, animator: animator)
                case .Segue(let segueIdentifier):
                    p.performSegueWithIdentifier(segueIdentifier, sender: self) // The segue must display self.view
                    break
                }
            }
            else if let window = self.view.window {
                window.makeKeyAndOrderFront(nil)
            }
            // or create an NSWindow or NSWindowController (/!\ keep a strong reference on it)
        #endif
    }

    open func dismissWebViewController() {
        #if os(iOS) || os(tvOS)
            let completion: () -> Void = { [unowned self] in
                self.delegate?.oauthWebViewControllerDidDismiss()
            }
            let animated = true
            if let navigationController = self.navigationController , (!useTopViewControlerInsteadOfNavigation || self.topViewController == nil){
                navigationController.popViewController(animated: animated)
            }
            else if let parentViewController = self.parent {
                // The presenting view controller is responsible for dismissing the view controller it presented
                parentViewController.dismiss(animated: animated, completion: completion)
            }
            else if let topViewController = topViewController {
                topViewController.dismiss(animated: animated, completion: completion)
            }
            else {
                // keep old code...
                self.dismiss(animated: animated, completion: completion)
            }
        #elseif os(watchOS)
            self.dismissController()
        #elseif os(OSX)
            if self.presentingViewController != nil {
                self.dismissController(nil)
                if self.parentViewController != nil {
                    self.removeFromParentViewController()
                }
            }
            else if let window = self.view.window {
                window.performClose(nil)
            }
        #endif
    }
    
    // MARK: overrides
    #if os(iOS) || os(tvOS)
    open override func viewWillAppear(_ animated: Bool) {
        self.delegate?.oauthWebViewControllerWillAppear()
    }
    open override func viewDidAppear(_ animated: Bool) {
        self.delegate?.oauthWebViewControllerDidAppear()
    }
    open override func viewWillDisappear(_ animated: Bool) {
        self.delegate?.oauthWebViewControllerWillDisappear()
    }
    open override func viewDidDisappear(_ animated: Bool) {
        self.delegate?.oauthWebViewControllerDidDisappear()
    }
    #elseif os(OSX)
    public override func viewWillAppear() {
        self.delegate?.oauthWebViewControllerWillAppear()
    }
    public override func viewDidAppear() {
        self.delegate?.oauthWebViewControllerDidAppear()
    }
    public override func viewWillDisappear() {
        self.delegate?.oauthWebViewControllerWillDisappear()
    }
    public override func viewDidDisappear() {
        self.delegate?.oauthWebViewControllerDidDisappear()
    }
    
    #endif
}
