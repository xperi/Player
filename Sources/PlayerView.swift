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
    case stopped = 0
    case playing
    case paused
    case failed

    public var description: String {
        get {
            switch self {
            case .stopped:
                return "Stopped"
            case .playing:
                return "Playing"
            case .failed:
                return "Failed"
            case .paused:
                return "Paused"
            }
        }
    }
}

/// Asset buffering states.
public enum BufferingState: Int, CustomStringConvertible {
    case unknown = 0
    case ready
    case delayed

    public var description: String {
        get {
            switch self {
            case .unknown:
                return "Unknown"
            case .ready:
                return "Ready"
            case .delayed:
                return "Delayed"
            }
        }
    }
}

// MARK: - PlayerDelegate

/// Player delegate protocol
@objc public protocol PlayerDelegate: NSObjectProtocol {
    // state
    @objc optional func playerReady(_ playerView: PlayerView)
    @objc optional func playerPlaybackStateDidChange(_ playerView: PlayerView)
    @objc optional func playerBufferingStateDidChange(_ playerView: PlayerView)

    // playback
    @objc optional func playerCurrentTimeDidChange(_ playerView: PlayerView)
    @objc optional func playerPlaybackWillStartFromBeginning(_ playerView: PlayerView)
    @objc optional func playerPlaybackDidEnd(_ playerView: PlayerView)
    @objc optional func playerPlaybackWillLoop(_ playerView: PlayerView)
}

// MARK: - Player

/// ▶️ Player, simple way to play and stream media
open class PlayerView: UIView {

    /// Player delegate.
    open weak var delegate: PlayerDelegate?

    /// Mutes audio playback when true.
    open var muted: Bool {
        get {
            return self._avplayer.isMuted
        }
        set {
            self._avplayer.isMuted = newValue
        }
    }

    /// Volume for the player, ranging from 0.0 to 1.0 on a linear scale.
    open var volume: Float {
        get {
            return self._avplayer.volume
        }
        set {
            self._avplayer.volume = newValue
        }
    }

    /// Specifies how the video is displayed within a player layer’s bounds.
    /// The default value is `AVLayerVideoGravityResizeAspect`. See `FillMode` enum.
    open var fillMode: String {
        get {
            return self.playerLayer?.videoGravity ?? ""
        }
        set {
            self.playerLayer?.videoGravity = newValue
        }
    }

    // state

    /// Playback automatically loops continuously when true.
    open var playbackLoops: Bool {
        get {
            return (self._avplayer.actionAtItemEnd == .none) as Bool
        }
        set {
            if newValue == true {
                self._avplayer.actionAtItemEnd = .none
            } else {
                self._avplayer.actionAtItemEnd = .pause
            }
        }
    }

    /// Playback freezes on last frame frame at end when true.
    open var playbackFreezesAtEnd: Bool = false

    /// Current playback state of the Player.
    open var playbackState: PlaybackState = .stopped {
        didSet {
            if playbackState != oldValue || !playbackEdgeTriggered {
                self.delegate?.playerPlaybackStateDidChange?(self)
            }
        }
    }

    /// Current buffering state of the Player.
    open var bufferingState: BufferingState = .unknown {
       didSet {
            if bufferingState != oldValue || !playbackEdgeTriggered {
                self.delegate?.playerBufferingStateDidChange?(self)
            }
        }
    }

    /// Playback buffering size in seconds.
    open var bufferSize: Double = 10

    /// Playback is not automatically triggered from state changes when true.
    open var playbackEdgeTriggered: Bool = true

    /// Maximum duration of playback.
    open var maximumDuration: TimeInterval {
        get {
            if let playerItem = self._playerItem {
                return CMTimeGetSeconds(playerItem.duration)
            } else {
                return CMTimeGetSeconds(kCMTimeIndefinite)
            }
        }
    }

    /// Media playback's current time.
    open var currentTime: TimeInterval {
        get {
            if let playerItem = self._playerItem {
                return CMTimeGetSeconds(playerItem.currentTime())
            } else {
                return CMTimeGetSeconds(kCMTimeIndefinite)
            }
        }
    }

    /// The natural dimensions of the media.
    open var naturalSize: CGSize {
        get {
            if let playerItem = self._playerItem {
                let track = playerItem.asset.tracks(withMediaType: AVMediaTypeVideo)[0]
                return track.naturalSize
            } else {
                return CGSize.zero
            }
        }
    }

    /// Player view's initial background color.
    open var layerBackgroundColor: UIColor? {
        get {
            guard let backgroundColor = self.playerLayer?.backgroundColor else { return nil }
            return UIColor(cgColor: backgroundColor)
        }
        set {
            self.playerLayer?.backgroundColor = newValue?.cgColor
        }
    }

    // MARK: - private instance vars

    internal var _asset: AVAsset!
    internal var _avplayer: AVPlayer!
    internal var _playerItem: AVPlayerItem?
    internal var _timeObserver: Any!

    open override class var layerClass: Swift.AnyClass {
        get {
            return AVPlayerLayer.self
        }
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
    
    // MARK: - object lifecycle
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    fileprivate func commonInit(){
        self._avplayer = AVPlayer()
        self._avplayer.actionAtItemEnd = .pause
        self.playbackFreezesAtEnd = false
        self.playerLayer?.backgroundColor = UIColor.black.cgColor
        addPlayerObservers()
    }

    deinit {
        self.delegate = nil
        self.player = nil

        self.removePlayerObservers()

        self._avplayer.pause()
        self.setupPlayerItem(nil)
    }

   
    // MARK: - Playback funcs

    /// Begins playback of the media from the beginning.
    open func playFromBeginning() {
        self.delegate?.playerPlaybackWillStartFromBeginning?(self)
        self._avplayer.seek(to: kCMTimeZero)
        self.playFromCurrentTime()
    }

    /// Begins playback of the media from the current time.
    open func playFromCurrentTime() {
        guard self.playbackState != .playing else {
            return
        }
        self.playbackState = .playing
        self._avplayer.play()
    }

    /// Pauses playback of the media.
    open func pause() {
        guard self.playbackState == .playing else {
            return
        }

        self._avplayer.pause()
        self.playbackState = .paused
    }

    /// Stops playback of the media.
    open func stop() {
        guard self.playbackState != .stopped else {
            return
        }

        self._avplayer.pause()
        self.playbackState = .stopped
        self.delegate?.playerPlaybackDidEnd?(self)
    }

    /// Updates playback to the specified time.
    ///
    /// - Parameter time: The time to switch to move the playback.
    open func seek(to time: CMTime) {
        if let playerItem = self._playerItem {
            return playerItem.seek(to: time)
        }
    }

    /// Updates the playback time to the specified time bound.
    ///
    /// - Parameters:
    ///   - time: The time to switch to move the playback.
    ///   - toleranceBefore: The tolerance allowed before time.
    ///   - toleranceAfter: The tolerance allowed after time.
    open func seekToTime(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        if let playerItem = self._playerItem {
            return playerItem.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter)
        }
    }


    open func takeSnapshot(completion: @escaping ((UIImage?)->Void)) {
        guard let player = player, let asset = player.currentItem?.asset else {
            completion(nil)
            return
        }
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        let times = [NSValue(time:player.currentTime())]
        imageGenerator.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cgImage, actualTime, result, error in
            guard let cgImage = cgImage else {
                completion(nil)
                return
            }
            
            return completion(UIImage(cgImage: cgImage))
            
        }
    }

}

// MARK: - loading funcs

extension PlayerView {

    open func setup(url: URL?, startTime: Double? = nil) {
        // ensure everything is reset beforehand
        if self.playbackState == .playing {
            self.pause()
        }

        self.setupPlayerItem(nil)

        if let url = url {
            let asset = AVURLAsset(url: url, options: .none)
            self.setupAsset(asset, startTime:startTime)
        }
    }

    fileprivate func setupAsset(_ asset: AVAsset, startTime: Double?) {
        if self.playbackState == .playing {
            self.pause()
        }

        self.bufferingState = .unknown

        self._asset = asset
        if let _ = self._asset {
            self.setupPlayerItem(nil)
        }

        let keys: [String] = [PlayerTracksKey, PlayerPlayableKey, PlayerDurationKey]

        self._asset.loadValuesAsynchronously(forKeys: keys, completionHandler: { () -> Void in

            for key in keys {
                var error: NSError?
                let status = self._asset.statusOfValue(forKey: key, error:&error)
                if status == .failed {
                    self.playbackState = .failed
                    return
                }
            }

            if self._asset.isPlayable == false {
                self.playbackState = .failed
                return
            }

            let playerItem: AVPlayerItem = AVPlayerItem(asset:self._asset)
            if let startTime = startTime {
                playerItem.seek(to: CMTime(seconds: startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), toleranceBefore: kCMTimeZero
                    ,toleranceAfter: kCMTimeZero )
            }
            self.setupPlayerItem(playerItem)

        })
    }

    fileprivate func setupPlayerItem(_ playerItem: AVPlayerItem?) {
        if let currentPlayerItem = self._playerItem {
            currentPlayerItem.removeObserver(self, forKeyPath: PlayerEmptyBufferKey, context: &PlayerItemObserverContext)
            currentPlayerItem.removeObserver(self, forKeyPath: PlayerKeepUpKey, context: &PlayerItemObserverContext)
            currentPlayerItem.removeObserver(self, forKeyPath: PlayerStatusKey, context: &PlayerItemObserverContext)
            currentPlayerItem.removeObserver(self, forKeyPath: PlayerLoadedTimeRangesKey, context: &PlayerItemObserverContext)

            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: currentPlayerItem)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: currentPlayerItem)
        }

        self._playerItem = playerItem

        if let updatedPlayerItem = self._playerItem {
            updatedPlayerItem.addObserver(self, forKeyPath: PlayerEmptyBufferKey, options: ([.new, .old]), context: &PlayerItemObserverContext)
            updatedPlayerItem.addObserver(self, forKeyPath: PlayerKeepUpKey, options: ([.new, .old]), context: &PlayerItemObserverContext)
            updatedPlayerItem.addObserver(self, forKeyPath: PlayerStatusKey, options: ([.new, .old]), context: &PlayerItemObserverContext)
            updatedPlayerItem.addObserver(self, forKeyPath: PlayerLoadedTimeRangesKey, options: ([.new, .old]), context: &PlayerItemObserverContext)
//
            NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidPlayToEndTime(_:)), name: .AVPlayerItemDidPlayToEndTime, object: updatedPlayerItem)
            NotificationCenter.default.addObserver(self, selector: #selector(playerItemFailedToPlayToEndTime(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: updatedPlayerItem)
        }

        let playbackLoops = self.playbackLoops

        self._avplayer.replaceCurrentItem(with: self._playerItem)

        // update new playerItem settings
        if playbackLoops == true {
            self._avplayer.actionAtItemEnd = .none
        } else {
            self._avplayer.actionAtItemEnd = .pause
        }
    }

}

// MARK: - NSNotifications

extension PlayerView {

    // AVPlayerItem

    internal func playerItemDidPlayToEndTime(_ aNotification: Notification) {
        if self.playbackLoops == true {
            self.delegate?.playerPlaybackWillLoop?(self)
            self._avplayer.seek(to: kCMTimeZero)
        } else {
            if self.playbackFreezesAtEnd == true {
                self.stop()
            } else {
                self._avplayer.seek(to: kCMTimeZero, completionHandler: { _ in
                    self.stop()
                })
            }
        }
    }

    internal func playerItemFailedToPlayToEndTime(_ aNotification: Notification) {
        self.playbackState = .failed
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

extension PlayerView {

    // MARK: - AVPlayerObservers

    internal func addPlayerObservers() {
        self._timeObserver = self._avplayer.addPeriodicTimeObserver(forInterval: CMTimeMake(1,100), queue: DispatchQueue.main, using: { [weak self] timeInterval in
            guard let strongSelf = self
            else {
                return
            }
            strongSelf.delegate?.playerCurrentTimeDidChange?(strongSelf)
        })
        self._avplayer.addObserver(self, forKeyPath: PlayerRateKey, options: ([.new, .old]) , context: &PlayerObserverContext)
    }

    internal func removePlayerObservers() {
        self._avplayer.removeTimeObserver(_timeObserver)
        self._avplayer.removeObserver(self, forKeyPath: PlayerRateKey, context: &PlayerObserverContext)
    }

    // MARK: -

    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

        // PlayerRateKey, PlayerObserverContext

        if (context == &PlayerItemObserverContext) {

            // PlayerStatusKey

            if keyPath == PlayerKeepUpKey {

                // PlayerKeepUpKey

                if let item = self._playerItem {
                    self.bufferingState = .ready

                    if item.isPlaybackLikelyToKeepUp && self.playbackState == .playing {
                        self.playFromCurrentTime()
                    }
                }

                if let status = change?[NSKeyValueChangeKey.newKey] as? NSNumber {
                    switch (status.intValue as AVPlayerStatus.RawValue) {
                    case AVPlayerStatus.readyToPlay.rawValue:
                        if let layer = self.playerLayer {
                            layer.player = self._avplayer
                            layer.isHidden = false
                        }
                        break
                    case AVPlayerStatus.failed.rawValue:
                        self.playbackState = PlaybackState.failed
                        break
                    default:
                        break
                    }
                }

            } else if keyPath == PlayerEmptyBufferKey {

                // PlayerEmptyBufferKey

                if let item = self._playerItem {
                    if item.isPlaybackBufferEmpty {
                        self.bufferingState = .delayed
                    }
                }

                if let status = change?[NSKeyValueChangeKey.newKey] as? NSNumber {
                    switch (status.intValue as AVPlayerStatus.RawValue) {
                    case AVPlayerStatus.readyToPlay.rawValue:
                        if let layer = self.playerLayer {
                            layer.player = self._avplayer
                            layer.isHidden = false
                        }
                        break
                    case AVPlayerStatus.failed.rawValue:
                        self.playbackState = PlaybackState.failed
                        break
                    default:
                        break
                    }
                }

            } else if keyPath == PlayerLoadedTimeRangesKey {

                // PlayerLoadedTimeRangesKey

                if let item = self._playerItem {
                    self.bufferingState = .ready
                    
                    let timeRanges = item.loadedTimeRanges
                    
                    guard let timeRange = timeRanges.first?.timeRangeValue else {
                        return
                    }
                    
                    let bufferedTime = CMTimeGetSeconds(CMTimeAdd(timeRange.start, timeRange.duration))
                    let currentTime = CMTimeGetSeconds(item.currentTime())

                    if (bufferedTime - currentTime) >= self.bufferSize && self.playbackState == .playing {
                        self.playFromCurrentTime()
                    }
                }
            }

        } else if (context == &PlayerLayerObserverContext) {
            if let layer = self.playerLayer {
                if layer.isReadyForDisplay {
                    self.executeClosureOnMainQueueIfNecessary(withClosure: {
                        self.delegate?.playerReady?(self)
                    })
                }
            }
        }

    }

}

// MARK: - queues

extension PlayerView {

    internal func executeClosureOnMainQueueIfNecessary(withClosure closure: @escaping () -> Void) {
        if Thread.isMainThread {
            closure()
        } else {
            DispatchQueue.main.async(execute: closure)
        }
    }

}
