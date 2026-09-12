// The slap, as data (Pass 5 2d, Build Doc 3 step 2): peel in at 1.4× and −34°, smack on frame 3 with
// the cue, squash 0.82 × 1.18, rebound 1.08 × 0.92, settle flat, ~620 ms. The Rive state machine owns
// these numbers when the .riv assets are present; this is the same curve for the still-image path, so
// both play the same slap and the timing lives in one place.
import Foundation
import SwiftUI

public struct StickerSlap: Equatable, Sendable {
    /// One pose on the way down: when it starts, and the transform to reach by then.
    public struct Step: Equatable, Sendable {
        public var at: Double            // seconds from the start of the slap
        public var scaleX: CGFloat
        public var scaleY: CGFloat
        public var rotation: Double      // degrees
        public var opacity: Double
        public init(at: Double, scaleX: CGFloat, scaleY: CGFloat, rotation: Double, opacity: Double = 1) {
            self.at = at; self.scaleX = scaleX; self.scaleY = scaleY; self.rotation = rotation; self.opacity = opacity
        }
    }

    /// Frame 3 at 60 fps: the contact, where the cue fires.
    public static let contact: Double = 3.0 / 60.0
    public static let duration: Double = 0.62

    public static let steps: [Step] = [
        .init(at: 0,      scaleX: 1.40, scaleY: 1.40, rotation: -34, opacity: 0.0),
        .init(at: 0.016,  scaleX: 1.34, scaleY: 1.34, rotation: -26, opacity: 1.0),
        .init(at: contact, scaleX: 1.00, scaleY: 1.00, rotation: 0,  opacity: 1.0),
        .init(at: 0.110,  scaleX: 0.82, scaleY: 1.18, rotation: 0,   opacity: 1.0),
        .init(at: 0.200,  scaleX: 1.08, scaleY: 0.92, rotation: 0,   opacity: 1.0),
        .init(at: 0.300,  scaleX: 0.97, scaleY: 1.03, rotation: 0,   opacity: 1.0),
        .init(at: 0.420,  scaleX: 1.01, scaleY: 0.99, rotation: 0,   opacity: 1.0),
        .init(at: duration, scaleX: 1.00, scaleY: 1.00, rotation: 0, opacity: 1.0),
    ]

    /// The animated properties, as one value SwiftUI can keyframe.
    public struct Pose: Equatable, Sendable, Animatable {
        public var scaleX: CGFloat = 1
        public var scaleY: CGFloat = 1
        public var rotation: Double = 0
        public var opacity: Double = 1
        public init() {}
        public init(scaleX: CGFloat, scaleY: CGFloat, rotation: Double, opacity: Double) {
            self.scaleX = scaleX; self.scaleY = scaleY; self.rotation = rotation; self.opacity = opacity
        }
    }

    /// One property's keyframes, cubic between the poses above — the curve Pass 5 draws.
    public static func track(_ path: WritableKeyPath<Pose, CGFloat>) -> KeyframeTrack<Pose, CGFloat, some KeyframeTrackContent<CGFloat>> {
        KeyframeTrack(path) {
            for (previous, step) in zip(steps, steps.dropFirst()) {
                CubicKeyframe(value(step, path), duration: step.at - previous.at)
            }
        }
    }

    public static func track(_ path: WritableKeyPath<Pose, Double>) -> KeyframeTrack<Pose, Double, some KeyframeTrackContent<Double>> {
        KeyframeTrack(path) {
            for (previous, step) in zip(steps, steps.dropFirst()) {
                CubicKeyframe(value(step, path), duration: step.at - previous.at)
            }
        }
    }

    private static func value(_ step: Step, _ path: WritableKeyPath<Pose, CGFloat>) -> CGFloat {
        var pose = Pose(scaleX: step.scaleX, scaleY: step.scaleY, rotation: step.rotation, opacity: step.opacity)
        return pose[keyPath: path]
    }

    private static func value(_ step: Step, _ path: WritableKeyPath<Pose, Double>) -> Double {
        var pose = Pose(scaleX: step.scaleX, scaleY: step.scaleY, rotation: step.rotation, opacity: step.opacity)
        return pose[keyPath: path]
    }

    /// The pose at a moment in the slap, interpolated between steps (ease-out between poses).
    public static func pose(at t: Double) -> Step {
        guard let last = steps.last else { return .init(at: t, scaleX: 1, scaleY: 1, rotation: 0) }
        if t <= 0 { return steps[0] }
        if t >= last.at { return last }
        var previous = steps[0]
        for step in steps.dropFirst() {
            if t <= step.at {
                let span = step.at - previous.at
                let raw = span <= 0 ? 1 : (t - previous.at) / span
                let e = 1 - pow(1 - raw, 3)   // ease-out cubic, as Pass 5 draws the swipe
                return .init(at: t,
                             scaleX: previous.scaleX + (step.scaleX - previous.scaleX) * e,
                             scaleY: previous.scaleY + (step.scaleY - previous.scaleY) * e,
                             rotation: previous.rotation + (step.rotation - previous.rotation) * e,
                             opacity: previous.opacity + (step.opacity - previous.opacity) * e)
            }
            previous = step
        }
        return last
    }
}
