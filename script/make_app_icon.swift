#!/usr/bin/env swift
// 生成 Screen Off 主图标。
//
// 几何与配色取自 Figma 定稿「纯蓝无边框」：蓝色渐变外壳托住白框屏幕，
// 屏幕内以对角线切分出亮屏面与息屏面。外壳采用 Apple 标准 824/1024 连续圆角，
// 保证 Dock 中与系统 App 视觉等大。
//
// 用法：xcrun swift script/make_app_icon.swift <输出目录>

import AppKit
import SwiftUI

// MARK: - 设计常量

let canvas: CGFloat = 1024
let shellSize: CGFloat = 824
let shellOrigin = (canvas - shellSize) / 2
/// 定稿圆角占外壳宽度的 53.9062 / 199.453。
let shellCorner: CGFloat = shellSize * 0.27027

/// 屏幕组相对外壳的宽度占比，取自定稿 154.531 / 199.453。
let screenWidthRatio: CGFloat = 154.531 / 199.453
/// 屏幕组自身宽高比。
let screenAspect: CGFloat = 154.531 / 113.203

let shellGradient = [
    (0.00, CGColor(red: 0x57 / 255, green: 0xDB / 255, blue: 0xFF / 255, alpha: 1)),
    (0.52, CGColor(red: 0x15 / 255, green: 0x9E / 255, blue: 0xFF / 255, alpha: 1)),
    (1.00, CGColor(red: 0x17 / 255, green: 0x5A / 255, blue: 0xD9 / 255, alpha: 1)),
]

let screenGradient = [
    (0.00, CGColor(red: 1, green: 1, blue: 1, alpha: 1)),
    (0.62, CGColor(red: 0xE6 / 255, green: 0xF7 / 255, blue: 0xFF / 255, alpha: 1)),
    (1.00, CGColor(red: 0xBF / 255, green: 0xDF / 255, blue: 0xFF / 255, alpha: 1)),
]

// MARK: - 工具

func squircle(_ rect: CGRect, corner: CGFloat) -> CGPath {
    RoundedRectangle(cornerRadius: corner, style: .continuous).path(in: rect).cgPath
}

func gradient(_ stops: [(Double, CGColor)]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: stops.map(\.1) as CFArray,
        locations: stops.map { CGFloat($0.0) }
    )!
}

// MARK: - 绘制

func drawIcon(in ctx: CGContext) {
    ctx.setFillColor(CGColor(gray: 0, alpha: 0))
    ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))

    // CoreGraphics 原点在左下，统一翻转成「原点左上、y 向下」的设计坐标系。
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)

    let shellRect = CGRect(x: shellOrigin, y: shellOrigin, width: shellSize, height: shellSize)
    let shellPath = squircle(shellRect, corner: shellCorner)

    // 外壳阴影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -9), blur: 26, color: CGColor(gray: 0, alpha: 0.16))
    ctx.addPath(shellPath)
    ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // 外壳渐变
    ctx.saveGState()
    ctx.addPath(shellPath)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(shellGradient),
        start: CGPoint(x: shellRect.minX + shellSize * 0.0922, y: shellRect.minY + shellSize * 0.0392),
        end: CGPoint(x: shellRect.minX + shellSize * 0.8981, y: shellRect.minY + shellSize * 0.9706),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    // 外壳内描边
    let innerInset = shellSize * (0.898 / 185.078)
    ctx.saveGState()
    ctx.addPath(squircle(shellRect.insetBy(dx: innerInset, dy: innerInset), corner: shellCorner - innerInset))
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.42))
    ctx.setLineWidth(shellSize * (1.797 / 185.078))
    ctx.strokePath()
    ctx.restoreGState()

    // 屏幕组
    let groupWidth = shellSize * screenWidthRatio
    let groupHeight = groupWidth / screenAspect
    let group = CGRect(
        x: shellRect.midX - groupWidth / 2,
        y: shellRect.midY - groupHeight / 2,
        width: groupWidth,
        height: groupHeight
    )
    let unit = groupWidth / 154.531
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: group.minX + x * unit, y: group.minY + y * unit)
    }

    let screenRect = CGRect(
        x: group.minX + 6.289 * unit,
        y: group.minY + 6.289 * unit,
        width: 141.953 * unit,
        height: 100.625 * unit
    )
    let screenPath = squircle(screenRect, corner: 22.461 * unit)

    // 息屏面：右下半区的浅蓝玻璃，左上留出外壳蓝色作为亮屏面。
    ctx.saveGState()
    ctx.addPath(screenPath)
    ctx.clip()
    let plane = CGMutablePath()
    plane.addLines(between: [
        p(12.578, 100.625),
        p(141.953, 12.578),
        p(192.266, 12.578),
        p(192.266, 170.703),
        p(12.578, 170.703),
    ])
    plane.closeSubpath()
    ctx.addPath(plane)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(screenGradient),
        start: p(32.747, 36.781),
        end: p(113.880, 126.238),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    // 屏幕白框
    ctx.saveGState()
    ctx.addPath(screenPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
    ctx.setLineWidth(12.578 * unit)
    ctx.strokePath()
    ctx.restoreGState()
}

func render(size: Int) -> Data {
    let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    let scale = CGFloat(size) / canvas
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(in: ctx)

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - 输出

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "ScreenOff/Resources/Assets.xcassets/AppIcon.appiconset"

let entries: [(idiom: String, size: Int, scale: Int)] = [
    ("mac", 16, 1), ("mac", 16, 2),
    ("mac", 32, 1), ("mac", 32, 2),
    ("mac", 128, 1), ("mac", 128, 2),
    ("mac", 256, 1), ("mac", 256, 2),
    ("mac", 512, 1), ("mac", 512, 2),
]

let directory = URL(fileURLWithPath: outputDirectory)
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

var images: [[String: String]] = []
for entry in entries {
    let pixels = entry.size * entry.scale
    let name = "icon_\(entry.size)x\(entry.size)\(entry.scale == 2 ? "@2x" : "").png"
    try render(size: pixels).write(to: directory.appendingPathComponent(name))
    images.append([
        "idiom": entry.idiom,
        "size": "\(entry.size)x\(entry.size)",
        "scale": "\(entry.scale)x",
        "filename": name,
    ])
}

let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "xcode"],
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: directory.appendingPathComponent("Contents.json"))

print("已生成 \(entries.count) 张图标 → \(outputDirectory)")
