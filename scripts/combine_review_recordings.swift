import AVFoundation
import Foundation

@main
struct CombineReviewRecordings {
  static func main() async throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 4 else {
      throw NSError(
        domain: "CombineReviewRecordings",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Usage: combine_review_recordings <first.mp4> <second.mp4> <output.mp4>"
        ]
      )
    }

    let inputURLs = arguments[1...2].map {
      URL(fileURLWithPath: String($0))
    }
    let outputURL = URL(fileURLWithPath: arguments[3])

    try? FileManager.default.removeItem(at: outputURL)

    let composition = AVMutableComposition()
    guard
      let compositionVideoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
      ),
      let compositionAudioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    else {
      throw NSError(
        domain: "CombineReviewRecordings",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Could not create composition tracks."]
      )
    }

    var insertionTime = CMTime.zero
    var appliedVideoTransform = false

    for inputURL in inputURLs {
      let asset = AVURLAsset(url: inputURL)
      let duration = try await asset.load(.duration)
      let timeRange = CMTimeRange(start: .zero, duration: duration)

      guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
        throw NSError(
          domain: "CombineReviewRecordings",
          code: 3,
          userInfo: [
            NSLocalizedDescriptionKey: "Missing video track: \(inputURL.lastPathComponent)"
          ]
        )
      }

      try compositionVideoTrack.insertTimeRange(
        timeRange,
        of: videoTrack,
        at: insertionTime
      )

      if !appliedVideoTransform {
        compositionVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)
        appliedVideoTransform = true
      }

      guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
        throw NSError(
          domain: "CombineReviewRecordings",
          code: 4,
          userInfo: [
            NSLocalizedDescriptionKey: "Missing audio track: \(inputURL.lastPathComponent)"
          ]
        )
      }

      try compositionAudioTrack.insertTimeRange(
        timeRange,
        of: audioTrack,
        at: insertionTime
      )

      insertionTime = CMTimeAdd(insertionTime, duration)
    }

    guard
      let exporter = AVAssetExportSession(
        asset: composition,
        presetName: AVAssetExportPresetPassthrough
      )
    else {
      throw NSError(
        domain: "CombineReviewRecordings",
        code: 5,
        userInfo: [NSLocalizedDescriptionKey: "Could not create export session."]
      )
    }

    try await exporter.export(to: outputURL, as: .mp4)

    let outputAsset = AVURLAsset(url: outputURL)
    let outputDuration = try await outputAsset.load(.duration)
    let outputVideoTracks = try await outputAsset.loadTracks(withMediaType: .video)
    let outputAudioTracks = try await outputAsset.loadTracks(withMediaType: .audio)

    print(
      "Created \(outputURL.path) " +
        "duration=\(CMTimeGetSeconds(outputDuration)) " +
        "videoTracks=\(outputVideoTracks.count) " +
        "audioTracks=\(outputAudioTracks.count)"
    )
  }
}
