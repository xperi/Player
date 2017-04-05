//  Player.swift
//
//  Created by patrick piemonte on 11/26/14.
//
//  The MIT License (MIT)
//
//  Copyright (c) 2014-present patrick piemonte (http://patrickpiemonte.com/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import UIKit
import Foundation
import AVFoundation
import CoreGraphics

// MARK: - Player

/// ▶️ Player, simple way to play and stream media
open class PlayerViewController: UIViewController {
    
    // configuration
    
    /// Local or remote URL for the file asset to be played.
    ///
    /// - Parameter url: URL of the asset.
    open var url: URL? {
        didSet {
            setup(url: url)
        }
    }
    
    open var urlLink: String? {
        didSet {
            guard let urlLink = urlLink, let url = URL(string: urlLink) else {
                return
            }
            setup(url: url)
        }
    }
    
    /// Pauses playback automatically when backgrounded.
    open var playbackPausesWhenBackgrounded: Bool
    
    /// Resumes playback when entering foreground.
    open var playbackResumesWhenEnteringForeground: Bool

    internal var _playerView: PlayerView!
    
    // MARK: - object lifecycle
    
    public convenience init() {
        self.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        self.playbackPausesWhenBackgrounded = true
        self.playbackResumesWhenEnteringForeground = true
        super.init(coder: aDecoder)
    }
    
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        self.playbackPausesWhenBackgrounded = true
        self.playbackResumesWhenEnteringForeground = true
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    deinit {
        self.removeApplicationObservers()
    }
    
    // MARK: - view lifecycle
    
    open override func loadView() {
        self._playerView = PlayerView(frame: CGRect.zero)
        self._playerView.fillMode = AVLayerVideoGravityResizeAspect
        self._playerView.playerLayer?.isHidden = true
        self._playerView.playbackFreezesAtEnd = false
        self._playerView.delegate = self
        self.view = self._playerView
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        setup(url: url)
        
        self.addApplicationObservers();
    }
    
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        if _playerView.playbackState == .playing {
            _playerView.pause()
        }
    }
    
    fileprivate func setup(url: URL?) {
        guard isViewLoaded else { return }
    
    }
    
}

// MARK: - NSNotifications

extension PlayerViewController {
    
    // UIApplication
    
    internal func addApplicationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationWillResignActive(_:)), name: .UIApplicationWillResignActive, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationDidEnterBackground(_:)), name: .UIApplicationDidEnterBackground, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationWillEnterForeground(_:)), name: .UIApplicationWillEnterForeground, object: UIApplication.shared)
    }
    
    internal func removeApplicationObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    internal func handleApplicationWillResignActive(_ aNotification: Notification) {
        guard self._playerView.playbackState == .playing else {
            return
        }
        self._playerView.pause()
        
    }
    
    internal func handleApplicationDidEnterBackground(_ aNotification: Notification) {
        guard self._playerView.playbackState == .paused && self.playbackPausesWhenBackgrounded else {
            return
        }
        self._playerView.pause()
        
    }
    
    internal func handleApplicationWillEnterForeground(_ aNoticiation: Notification) {
        guard self._playerView.playbackState != .playing && self.playbackResumesWhenEnteringForeground else {
            return
        }
        self._playerView.playFromCurrentTime()
        
    }
    
}

extension PlayerViewController: PlayerDelegate {
    // state
    open func playerReady(_ playerView: PlayerView){
        
    }
    open func playerPlaybackStateDidChange(_ playerView: PlayerView){
        
    }
    open func playerBufferingStateDidChange(_ playerView: PlayerView){
        
    }
    
    // playback
    open func playerCurrentTimeDidChange(_ playerView: PlayerView){
        
    }
    open func playerPlaybackWillStartFromBeginning(_ playerView: PlayerView){
        
    }
    open func playerPlaybackDidEnd(_ playerView: PlayerView){
        
    }
    open func playerPlaybackWillLoop(_ playerView: PlayerView){
        
    }
}
