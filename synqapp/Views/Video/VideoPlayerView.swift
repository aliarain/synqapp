
//  VideoPlayerView.swift
//  SynqApp — AVPlayer wrapper for video journal entries

import SwiftUI
import AVKit

struct VideoPlayerView: NSViewRepresentable {

    let videoURL: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let player = AVPlayer(url: videoURL)
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        player.play()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player?.currentItem?.asset != AVURLAsset(url: videoURL) {
            nsView.player = AVPlayer(url: videoURL)
            nsView.player?.play()
        }
    }
}
