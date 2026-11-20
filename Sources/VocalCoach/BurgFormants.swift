// Swift adaptation of burg.rs and roots.rs from Phonia's phonia-formant crate.
// Copyright (c) 2026 Phonia contributors. MIT, see Resources/Phonia-MIT.txt.
// https://github.com/mkpoli/phonia/tree/663f43de63dd9dcb82a124b34739edb52635ebb6/crates/phonia-formant

import Foundation

enum BurgFormants {
    struct Resonance {
        let frequency: Double
        let bandwidth: Double
    }

    static func estimate(_ windowed: [Double], sampleRate: Double) -> [Resonance] {
        guard let coefficients = burg(windowed, order: 10) else { return [] }
        return roots(of: coefficients).compactMap { root -> Resonance? in
            let squaredMagnitude = root.squaredMagnitude
            guard root.imaginary > 1e-8, squaredMagnitude > Double.ulpOfOne else { return nil }
            let radius = squaredMagnitude > 1 ? 1 / root.magnitude : root.magnitude
            let frequency = atan2(root.imaginary, root.real) * sampleRate / (2 * .pi)
            let bandwidth = -sampleRate / .pi * log(radius)
            guard frequency >= 50, frequency <= sampleRate / 2 - 50 else { return nil }
            return Resonance(frequency: frequency, bandwidth: bandwidth)
        }.sorted { $0.frequency < $1.frequency }
    }

    private static func burg(_ samples: [Double], order: Int) -> [Double]? {
        guard samples.count > order else { return nil }
        var error = samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count)
        guard error > Double.ulpOfOne else { return nil }

        var forward = Array(samples.dropLast())
        var backward = Array(samples.dropFirst())
        var coefficients = [Double](repeating: 0, count: order)
        for degree in 0..<order {
            let count = forward.count
            var numerator = 0.0
            var denominator = 0.0
            for i in 0..<count {
                numerator += forward[i] * backward[i]
                denominator += forward[i] * forward[i] + backward[i] * backward[i]
            }
            guard denominator > Double.ulpOfOne else { return nil }

            let reflection = min(0.999999999999, max(-0.999999999999, 2 * numerator / denominator))
            let previous = coefficients
            coefficients[degree] = -reflection
            for i in 0..<degree {
                coefficients[i] = previous[i] - reflection * previous[degree - i - 1]
            }
            error *= 1 - reflection * reflection
            if error <= Double.ulpOfOne { break }

            if degree + 1 < order {
                for i in 0..<(count - 1) {
                    let nextBackward = backward[i + 1] - reflection * forward[i + 1]
                    forward[i] -= reflection * backward[i]
                    backward[i] = nextBackward
                }
                forward.removeLast()
                backward.removeLast()
            }
        }
        return coefficients
    }

    // Aberth iterations refine the poles together, followed by Newton polishing.
    private static func roots(of coefficients: [Double]) -> [Complex] {
        let degree = coefficients.count
        let tolerance = 1e-12
        let radius = 1 + (coefficients.map(abs).max() ?? 0)
        var roots = (0..<degree).map { i in
            let angle = .pi * Double(2 * i + 1) / Double(degree)
            return Complex(radius * cos(angle), radius * sin(angle))
        }
        for _ in 0..<200 {
            var largestStep = 0.0
            let previous = roots
            for i in previous.indices {
                let root = previous[i]
                let (value, derivative) = evaluate(coefficients, at: root)
                guard value.magnitude > tolerance, derivative.magnitude > Double.ulpOfOne else { continue }
                let newton = value / derivative
                var repulsion = Complex(0, 0)
                for j in previous.indices where i != j {
                    let distance = root - previous[j]
                    if distance.magnitude > Double.ulpOfOne {
                        repulsion = repulsion + Complex(1, 0) / distance
                    }
                }
                let denominator = Complex(1, 0) - newton * repulsion
                guard denominator.magnitude > Double.ulpOfOne else { continue }
                let step = newton / denominator
                roots[i] = root - step
                largestStep = max(largestStep, step.magnitude)
            }
            if largestStep <= tolerance { break }
        }
        for i in roots.indices {
            for _ in 0..<20 {
                let (value, derivative) = evaluate(coefficients, at: roots[i])
                guard derivative.magnitude > Double.ulpOfOne else { break }
                let step = value / derivative
                roots[i] = roots[i] - step
                if step.magnitude <= tolerance { break }
            }
        }
        return roots.filter { evaluate(coefficients, at: $0).0.magnitude < 1e-6 }
    }

    private static func evaluate(_ coefficients: [Double], at point: Complex) -> (Complex, Complex) {
        var value = Complex(1, 0)
        var derivative = Complex(0, 0)
        for coefficient in coefficients {
            derivative = derivative * point + value
            value = value * point + Complex(coefficient, 0)
        }
        return (value, derivative)
    }

    private struct Complex {
        let real: Double
        let imaginary: Double

        init(_ real: Double, _ imaginary: Double) {
            self.real = real
            self.imaginary = imaginary
        }

        var squaredMagnitude: Double { real * real + imaginary * imaginary }
        var magnitude: Double { squaredMagnitude.squareRoot() }

        static func + (left: Self, right: Self) -> Self {
            Self(left.real + right.real, left.imaginary + right.imaginary)
        }

        static func - (left: Self, right: Self) -> Self {
            Self(left.real - right.real, left.imaginary - right.imaginary)
        }

        static func * (left: Self, right: Self) -> Self {
            Self(left.real * right.real - left.imaginary * right.imaginary,
                 left.real * right.imaginary + left.imaginary * right.real)
        }

        static func / (left: Self, right: Self) -> Self {
            let scale = right.squaredMagnitude
            return Self((left.real * right.real + left.imaginary * right.imaginary) / scale,
                        (left.imaginary * right.real - left.real * right.imaginary) / scale)
        }
    }
}
