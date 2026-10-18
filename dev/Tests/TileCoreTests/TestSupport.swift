import CoreGraphics
@testable import TileCore

let A = WindowID(1), B = WindowID(2), C = WindowID(3), D = WindowID(4), E = WindowID(5)

/// The owner's ultrawide (32:9), used as the default layout rect.
let ultrawide = CGRect(x: 0, y: 0, width: 5120, height: 1440)

func leaf(_ id: WindowID) -> LayoutNode { .leaf(id) }

func split(_ direction: SplitDirection, _ parts: (LayoutNode, Double)...) -> LayoutNode {
    .split(direction, parts.map { SplitChild($0.0, weight: $0.1) })
}

/// Compact structure, for example "H(V(1,4),2,3)".
func shape(_ tree: LayoutTree) -> String {
    guard let root = tree.root else { return "empty" }
    return shape(root)
}

func shape(_ node: LayoutNode) -> String {
    switch node {
    case .leaf(let id): return "\(id.raw)"
    case .split(let direction, let children):
        return (direction == .horizontal ? "H(" : "V(") + children.map { shape($0.node) }.joined(separator: ",") + ")"
    }
}

func topWeights(_ tree: LayoutTree) -> [Double] {
    guard case .split(_, let children)? = tree.root else { return [] }
    return children.map(\.weight)
}

func weights(of node: LayoutNode) -> [Double] {
    guard case .split(_, let children) = node else { return [] }
    return children.map(\.weight)
}

func approx(_ a: [Double], _ b: [Double], tolerance: Double = 1e-9) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
}

func approx(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 1e-6) -> Bool {
    abs(a - b) <= tolerance
}

/// True when every split's weights are positive and sum to 1.
func weightsAreValid(_ node: LayoutNode?) -> Bool {
    guard case .split(_, let children)? = node else { return true }
    let sum = children.reduce(0) { $0 + $1.weight }
    return abs(sum - 1) < 1e-9 && children.allSatisfy { $0.weight > 0 && weightsAreValid($0.node) }
}

/// Deterministic pseudo-random numbers for the drift test.
struct LCG {
    var state: UInt64
    mutating func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(bound))
    }
}

let third: Double = 1.0 / 3
let sixth: Double = 1.0 / 6
let quarterPlusSixth: Double = 0.25 + 1.0 / 6
