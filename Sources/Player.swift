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

// MARK: - types

/// Video fill mode options for `Player.fillMode`.
///
/// - resize: Stretch to fill.
/// - resizeAspectFill: Preserve aspect ratio, filling bounds.
/// - resizeAspectFit: Preserve aspect ratio, fill within bounds.
public enum FillMode: String {
    case resize = "AVLayerVideoGravityResize"
    case resizeAspectFill = "AVLayerVideoGravityResizeAspectFill"
    case resizeAspectFit = "AVLayerVideoGravityResizeAspect"
}

/// Asset playback states.
public enum PlaybackState: Int, CustomStringConvertible {
    case Stopped = 0
    case Playing
    case Paused
    case Failed
    
    public var description: String {
        get {
            switch self {
            case Stopped:
                return "Stopped"
            case Playing:
                return "Playing"
            case Failed:
                return "Failed"
            case Paused:
                return "Paused"
            }
        }
    }
}

/// Asset buffering states.
public enum BufferingState: Int, CustomStringConvertible {
    case Unknown = 0
    case Ready
    case Delayed
    
    public var description: String {
        get {
            switch self {
            case Unknown:
                return "Unknown"
            case Ready:
                return "Ready"
            case Delayed:
                return "Delayed"
            }
        }
    }
}

// MARK: - PlayerDelegate

/// Player delegate protocol
public protocol PlayerDelegate: NSObjectProtocol {
    func playerReady(player: Player)
    func playerPlaybackStateDidChange(player: Player)
    func playerBufferingStateDidChange(player: Player)
}


/// Player playback protocol
public protocol PlayerPlaybackDelegate: NSObjectProtocol {
    func playerCurrentTimeDidChange(player: Player)
    func playerPlaybackWillStartFromBeginning(player: Player)
    func playerPlaybackDidEnd(player: Player)
    func playerPlaybackWillLoop(player: Player)
}

// MARK: - Player

/// ▶️ Player, simple way to play and stream media
public class Player: UIViewController {
    
    /// Player delegate.
    public weak var playerDelegate: PlayerDelegate?
    
    /// Playback delegate.
    public weak var playbackDelegate: PlayerPlaybackDelegate?
    
    // configuration
    
    /// Local or remote URL for the file asset to be played.
    ///
    /// - Parameter url: URL of the asset.
    public var url: NSURL? {
        didSet {
            setup(url)
        }
    }
    
    public var urlLink: String? {
        didSet {
            guard let urlLink = urlLink, let url = NSURL(string: urlLink) else {
                return
            }
            setup(url)

        }
    }
    
    /// Mutes audio playback when true.
    public var muted: Bool {
        get {
            return self._avplayer.muted
        }
        set {
            self._avplayer.muted = newValue
        }
    }
    
    /// Volume for the player, ranging from 0.0 to 1.0 on a linear scale.
    public var volume: Float {
        get {
            return self._avplayer.volume
        }
        set {
            self._avplayer.volume = newValue
        }
    }
    
    /// Specifies how the video is displayed within a player layer’s bounds.
    /// The default value is `AVLayerVideoGravityResizeAspect`. See `FillMode` enum.
    public var fillMode: String {
        get {
            return self._playerView.fillMode
        }
        set {
            self._playerView.fillMode = newValue
        }
    }
    
    /// Pauses playback automatically when backgrounded.
    public var playbackPausesWhenBackgrounded: Bool
    
    /// Resumes playback when entering foreground.
    public var playbackResumesWhenEnteringForeground: Bool
    
    // state
    
    /// Playback automatically loops continuously when true.
    public var playbackLoops: Bool {
        get {
            return (self._avplayer.actionAtItemEnd == .None) as Bool
        }
        set {
            if newValue == true {
                self._avplayer.actionAtItemEnd = .None
            } else {
                self._avplayer.actionAtItemEnd = .Pause
            }
        }
    }
    
    /// Playback freezes on last frame frame at end when true.
    public var playbackFreezesAtEnd: Bool = false
    
    /// Current playback state of the Player.
    public var playbackState: PlaybackState = .Stopped {
        didSet {
            if playbackState != oldValue || !playbackEdgeTriggered {
                self.playerDelegate?.playerPlaybackStateDidChange(self)
            }
        }
    }
    
    /// Current buffering state of the Player.
    public var bufferingState: BufferingState = .Unknown {
        didSet {
            if bufferingState != oldValue || !playbackEdgeTriggered {
                self.playerDelegate?.playerBufferingStateDidChange(self)
            }
        }
    }
    
    /// Playback buffering size in seconds.
    public var bufferSize: Double = 10
    
    /// Playback is not automatically triggered from state changes when true.
    public var playbackEdgeTriggered: Bool = true
    
    /// Maximum duration of playback.
    public var maximumDuration: NSTimeInterval {
        get {
            if let playerItem = self._playerItem {
                return CMTimeGetSeconds(playerItem.duration)
            } else {
                return CMTimeGetSeconds(kCMTimeIndefinite)
            }
        }
    }
    
    /// Media playback's current time.
    public var currentTime: NSTimeInterval {
        get {
            if let playerItem = self._playerItem {
                return CMTimeGetSeconds(playerItem.currentTime())
            } else {
                return CMTimeGetSeconds(kCMTimeIndefinite)
            }
        }
    }
    
    /// The natural dimensions of the media.
    public var naturalSize: CGSize {
        get {
            if let playerItem = self._playerItem {
                let track = playerItem.asset.tracksWithMediaType(AVMediaTypeVideo)[0]
                return track.naturalSize
            } else {
                return CGSize.zero
            }
        }
    }
    
    /// Player view's initial background color.
    public var layerBackgroundColor: UIColor? {
        get {
            guard let backgroundColor = self._playerView.playerLayer?.backgroundColor else { return nil }
            return UIColor(CGColor: backgroundColor)
        }
        set {
            self._playerView.playerLayer?.backgroundColor = newValue?.CGColor
        }
    }
    
    // MARK: - private instance vars
    
    internal var _asset: AVAsset!
    internal var _avplayer: AVPlayer
    internal var _playerItem: AVPlayerItem?
    internal var _playerView: PlayerView!
    internal var _timeObserver: AnyObject!
    
    // MARK: - object lifecycle
    
    public convenience init() {
        self.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        self._avplayer = AVPlayer()
        self._avplayer.actionAtItemEnd = .Pause
        self.playbackFreezesAtEnd = false
        self.playbackPausesWhenBackgrounded = true
        self.playbackResumesWhenEnteringForeground = true
        super.init(coder: aDecoder)
    }
    
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) {
        self._avplayer = AVPlayer()
        self._avplayer.actionAtItemEnd = .Pause
        self.playbackFreezesAtEnd = false
        self.playbackPausesWhenBackgrounded = true
        self.playbackResumesWhenEnteringForeground = true
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    deinit {
        self.playerDelegate = nil
        self.removeApplicationObservers()
        
        self.playbackDelegate = nil
        self.removePlayerLayerObservers()
        self._playerView.player = nil
        
        self.removePlayerObservers()
        
        self._avplayer.pause()
        self.setupPlayerItem(nil)
    }
    
    // MARK: - view lifecycle
    
    public override func loadView() {
        self._playerView = PlayerView(frame: CGRect.zero)
        self._playerView.fillMode = AVLayerVideoGravityResizeAspect
        self._playerView.playerLayer?.hidden = true
        self.view = self._playerView
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        setup(url)
        
        self.addPlayerLayerObservers()
        self.addPlayerObservers()
        self.addApplicationObservers()
    }
    
    public override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        
        if self.playbackState == .Playing {
            self.pause()
        }
    }
    
    // MARK: - Playback funcs
    
    /// Begins playback of the media from the beginning.
    public func playFromBeginning() {
        self.playbackDelegate?.playerPlaybackWillStartFromBeginning(self)
        self._avplayer.seekToTime(kCMTimeZero)
        self.playFromCurrentTime()
    }
    
    /// Begins playback of the media from the current time.
    public func playFromCurrentTime() {
        guard self.playbackState != .Playing else {
            return
        }
        self.playbackState = .Playing
        self._avplayer.play()
    }
    
    /// Pauses playback of the media.
    public func pause() {
        guard self.playbackState == .Playing else {
            return
        }
        self._avplayer.pause()
        self.playbackState = .Paused
    }
    
    /// Stops playback of the media.
    public func stop() {
        guard self.playbackState != .Stopped else {
            return
        }
        
        self._avplayer.pause()
        self.playbackState = .Stopped
        self.playbackDelegate?.playerPlaybackDidEnd(self)
    }
    
    /// Updates playback to the specified time.
    ///
    /// - Parameter time: The time to switch to move the playback.
    public func seekToTime(time: CMTime) {
        if let playerItem = self._playerItem {
            return playerItem.seekToTime(time)
        }
    }
    
    /// Updates the playback time to the specified time bound.
    ///
    /// - Parameters:
    ///   - time: The time to switch to move the playback.
    ///   - toleranceBefore: The tolerance allowed before time.
    ///   - toleranceAfter: The tolerance allowed after time.
    public func seekToTime(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        if let playerItem = self._playerItem {
            return playerItem.seekToTime(time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter)
        }
    }
    
    /// Captures a snapshot of the current Player view.
    ///
    /// - Returns: A UIImage of the player view.
    public func takeSnapshot() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(self._playerView.frame.size, false, UIScreen.mainScreen().scale)
        self._playerView.drawViewHierarchyInRect(self._playerView.bounds, afterScreenUpdates: true)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image!
    }
    
}

// MARK: - loading funcs

extension Player {
    
    private func setup(url: NSURL?) {
        guard isViewLoaded() else { return }
        
        // ensure everything is reset beforehand
        if self.playbackState == .Playing {
            self.pause()
        }
        
        self.setupPlayerItem(nil)
        
        if let url = url {
            let asset = AVURLAsset(URL: url, options: .None)
            self.setupAsset(asset)
        }
    }
    
    private func setupAsset(asset: AVAsset) {
        if self.playbackState == .Playing {
            self.pause()
        }
        
        self.bufferingState = .Unknown
        
        self._asset = asset
        if let _ = self._asset {
            self.setupPlayerItem(nil)
        }
        
        let keys: [String] = [PlayerTracksKey, PlayerPlayableKey, PlayerDurationKey]
        self._asset.loadValuesAsynchronouslyForKeys(keys, completionHandler: { () -> Void in
            dispatch_sync(dispatch_get_main_queue(), { () -> Void in
                
                for key in keys {
                    var error: NSError?
                    let status = self._asset.statusOfValueForKey(key, error:&error)
                    if status == .Failed {
                        self.playbackState = .Failed
                        return
                    }
                }
                
                if self._asset.playable.boolValue == false {
                    self.playbackState = .Failed
                    return
                }
                
                let playerItem: AVPlayerItem = AVPlayerItem(asset:self._asset)
                self.setupPlayerItem(playerItem)
            })
        })
        
    }
    
    private func setupPlayerItem(playerItem: AVPlayerItem?) {
        if let currentPlayerItem = self._playerItem {
            currentPlayerItem.removeObserver(self, forKeyPath: PlayerEmptyBufferKey, context: &PlayerItemObserverContext)
            currentPlayerItem.removeObserver(self, forKeyPath: PlayerKeepUpKey, context: &PlayerItemObserverContext)
            currentPlayerItem.removeObserver(self, forKeyPath: PlayerStatusKey, context: &PlayerItemObserverContext)
            currentPlayerItem.removeObserver(self, forKeyPath: PlayerLoadedTimeRangesKey, context: &PlayerItemObserverContext)
            
            NSNotificationCenter.defaultCenter().removeObserver(self, name: AVPlayerItemDidPlayToEndTimeNotification, object: currentPlayerItem)
            NSNotificationCenter.defaultCenter().removeObserver(self, name: AVPlayerItemFailedToPlayToEndTimeNotification, object: currentPlayerItem)
        }
        
        self._playerItem = playerItem
        
        if let updatedPlayerItem = self._playerItem {
            updatedPlayerItem.addObserver(self, forKeyPath: PlayerEmptyBufferKey, options: ([.New, .Old]), context: &PlayerItemObserverContext)
            updatedPlayerItem.addObserver(self, forKeyPath: PlayerKeepUpKey, options: ([.New, .Old]), context: &PlayerItemObserverContext)
            updatedPlayerItem.addObserver(self, forKeyPath: PlayerStatusKey, options: ([.New, .Old]), context: &PlayerItemObserverContext)
            updatedPlayerItem.addObserver(self, forKeyPath: PlayerLoadedTimeRangesKey, options: ([.New, .Old]), context: &PlayerItemObserverContext)
            
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(playerItemDidPlayToEndTime(_:)), name: AVPlayerItemDidPlayToEndTimeNotification, object: updatedPlayerItem)
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(playerItemFailedToPlayToEndTime(_:)), name: AVPlayerItemFailedToPlayToEndTimeNotification, object: updatedPlayerItem)
        }
        
        let playbackLoops = self.playbackLoops
        
        self._avplayer.replaceCurrentItemWithPlayerItem(self._playerItem)
        
        // update new playerItem settings
        if playbackLoops == true {
            self._avplayer.actionAtItemEnd = .None
        } else {
            self._avplayer.actionAtItemEnd = .Pause
        }
    }
    
}

// MARK: - NSNotifications

extension Player {
    
    // AVPlayerItem
    
    internal func playerItemDidPlayToEndTime(aNotification: NSNotification) {
        if self.playbackLoops == true {
            self.playbackDelegate?.playerPlaybackWillLoop(self)
            self._avplayer.seekToTime(kCMTimeZero)
            
        } else {
            if self.playbackFreezesAtEnd == true {
                self.stop()
            } else {
                self._avplayer.seekToTime(kCMTimeZero, completionHandler: { _ in
                    self.stop()
                })
            }
        }
    }
    
    internal func playerItemFailedToPlayToEndTime(aNotification: NSNotification) {
        self.playbackState = .Failed
    }
    
    // UIApplication
    
    internal func addApplicationObservers() {
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(handleApplicationWillResignActive(_:)), name: UIApplicationWillResignActiveNotification, object: UIApplication.sharedApplication())
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(handleApplicationDidEnterBackground(_:)), name: UIApplicationDidEnterBackgroundNotification, object: UIApplication.sharedApplication())
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(handleApplicationWillEnterForeground(_:)), name: UIApplicationWillEnterForegroundNotification, object: UIApplication.sharedApplication())
    }
    
    internal func removeApplicationObservers() {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    internal func handleApplicationWillResignActive(aNotification: NSNotification) {
        guard self.playbackState == .Playing else {
            return
        }
        self.pause()
        
    }
    
    internal func handleApplicationDidEnterBackground(aNotification: NSNotification) {
        guard self.playbackState == .Paused && self.playbackPausesWhenBackgrounded else {
            return
        }
        self.pause()
        
    }
    
    internal func handleApplicationWillEnterForeground(aNoticiation: NSNotification) {
        guard self.playbackState != .Playing && self.playbackResumesWhenEnteringForeground else {
            return
        }
        self.playFromCurrentTime()
        
    }
    
}

// MARK: - KVO

// KVO contexts

private var PlayerObserverContext = 0
private var PlayerItemObserverContext = 0
private var PlayerLayerObserverContext = 0

// KVO player keys

private let PlayerTracksKey = "tracks"
private let PlayerPlayableKey = "playable"
private let PlayerDurationKey = "duration"
private let PlayerRateKey = "rate"

// KVO player item keys

private let PlayerStatusKey = "status"
private let PlayerEmptyBufferKey = "playbackBufferEmpty"
private let PlayerKeepUpKey = "playbackLikelyToKeepUp"
private let PlayerLoadedTimeRangesKey = "loadedTimeRanges"

// KVO player layer keys

private let PlayerReadyForDisplayKey = "readyForDisplay"

extension Player {
    
    // MARK: - AVPlayerLayerObservers
    
    internal func addPlayerLayerObservers() {
        self._playerView.layer.addObserver(self, forKeyPath: PlayerReadyForDisplayKey, options: ([.New, .Old]), context: &PlayerLayerObserverContext)
    }
    
    internal func removePlayerLayerObservers() {
        self._playerView.layer.removeObserver(self, forKeyPath: PlayerReadyForDisplayKey, context: &PlayerLayerObserverContext)
    }
    
    // MARK: - AVPlayerObservers
    
    internal func addPlayerObservers() {
        self._timeObserver = self._avplayer.addPeriodicTimeObserverForInterval(CMTimeMake(1, 100), queue: dispatch_get_main_queue()) { [weak self] timeInterval in
            guard let strongSelf = self else { return }
            strongSelf.playbackDelegate?.playerCurrentTimeDidChange(strongSelf)
        }
        self._avplayer.addObserver(self, forKeyPath: PlayerRateKey, options: ([.New, .Old]), context: &PlayerObserverContext)
    }
    
    internal func removePlayerObservers() {
        self._avplayer.removeTimeObserver(_timeObserver)
        self._avplayer.removeObserver(self, forKeyPath: PlayerRateKey, context: &PlayerObserverContext)
    }
    
    // MARK: -
    
    override public func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        
        // PlayerRateKey, PlayerObserverContext
        
        if (context == &PlayerItemObserverContext) {
            
            // PlayerStatusKey
            
            if keyPath == PlayerKeepUpKey {
                
                // PlayerKeepUpKey
                
                if let item = self._playerItem {
                    self.bufferingState = .Ready
                    
                    if item.playbackLikelyToKeepUp && self.playbackState == .Playing {
                        self.playFromCurrentTime()
                    }
                }
                
                if let status = change?[NSKeyValueChangeNewKey] as? NSNumber {
                    switch (status) {
                    case AVPlayerStatus.ReadyToPlay.rawValue:
                        if let layer = self._playerView.playerLayer {
                            layer.player = self._avplayer
                            layer.hidden = false
                        }
                        break
                    case AVPlayerStatus.Failed.rawValue:
                        self.playbackState = PlaybackState.Failed
                        break
                    default:
                        break
                    }
                }
                
            } else if keyPath == PlayerEmptyBufferKey {
                
                // PlayerEmptyBufferKey
                
                if let item = self._playerItem {
                    if item.playbackBufferEmpty {
                        self.bufferingState = .Delayed
                    }
                }
                
                if let status = change?[NSKeyValueChangeNewKey] as? NSNumber {
                    switch (status) {
                    case AVPlayerStatus.ReadyToPlay.rawValue:
                        if let layer = self._playerView.playerLayer {
                            layer.player = self._avplayer
                            layer.hidden = false
                        }
                        break
                    case AVPlayerStatus.Failed.rawValue:
                        self.playbackState = PlaybackState.Failed
                        break
                    default:
                        break
                    }
                }
                
            } else if keyPath == PlayerLoadedTimeRangesKey {
                
                // PlayerLoadedTimeRangesKey
                
                if let item = self._playerItem {
                    self.bufferingState = .Ready
                    
                    let timeRanges = item.loadedTimeRanges
                    if let timeRange = timeRanges.first?.CMTimeRangeValue {
                        let bufferedTime = CMTimeGetSeconds(CMTimeAdd(timeRange.start, timeRange.duration))
                        let currentTime = CMTimeGetSeconds(item.currentTime())
                        if (bufferedTime - currentTime) >= self.bufferSize && self.playbackState == .Playing {
                            self.playFromCurrentTime()
                        }
                    } else {
                        self.playFromCurrentTime()
                    }
                }
            }
            
        } else if (context == &PlayerLayerObserverContext) {
            if let layer = self._playerView.playerLayer {
                if layer.readyForDisplay {
                    self.executeClosureOnMainQueueIfNecessary(withClosure: {
                        self.playerDelegate?.playerReady(self)
                    })
                }
            }
        }
        
    }
    
}

// MARK: - PlayerView

internal class PlayerView: UIView {
    
    override class func layerClass() -> AnyClass {
        return AVPlayerLayer.self
    }
    
    var playerLayer: AVPlayerLayer? {
        get {
            return self.layer as? AVPlayerLayer
        }
    }
    
    var player: AVPlayer? {
        get {
            return self.playerLayer?.player
        }
        set {
            if self.playerLayer?.player != newValue {
                self.playerLayer?.player = newValue
            }
        }
    }
    
    var fillMode: String {
        get {
            return self.playerLayer?.videoGravity ?? ""
        }
        set {
            self.playerLayer?.videoGravity = newValue
        }
    }
    
    // MARK: - object lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.playerLayer?.backgroundColor = UIColor.blackColor().CGColor
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.playerLayer?.backgroundColor = UIColor.blackColor().CGColor
    }
    
}

// MARK: - queues

extension Player {
    
    internal func executeClosureOnMainQueueIfNecessary(withClosure closure:() -> Void) {
        if NSThread.isMainThread() {
            closure()
        } else {
            dispatch_sync(dispatch_get_main_queue(), closure)
        }
    }
    
}
