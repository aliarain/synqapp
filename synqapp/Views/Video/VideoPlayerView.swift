
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
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Comparing a fresh AVURLAsset by identity was always unequal, so every SwiftUI update restarted the video.
        if (nsView.player?.currentItem?.asset as? AVURLAsset)?.url != videoURL {
            nsView.player = AVPlayer(url: videoURL)
        }
    }
}
