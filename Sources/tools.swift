import AppKit
import Foundation
import JSONSchemaBuilder
@preconcurrency import MCPServer

// MARK: - Utility Functions

/// Check if Zipic app is installed
func isZipicInstalled() -> Bool {
    let zipicBundleID = "studio.5km.zipic"
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: zipicBundleID) != nil
}

/// Calculate output path for compressed images
func calculateOutputPaths(inputUrls: [String], directory: String?, specified: Bool?) -> [String] {
    // If using default directory (specified = true), return empty array as we can't predict the path
    if specified == true {
        return []
    }

    // If no custom directory specified, images will be saved alongside originals
    if directory == nil {
        return inputUrls.map { url in
            let originalPath = (url as NSString)
            let pathExtension = originalPath.pathExtension
            let pathWithoutExtension = originalPath.deletingPathExtension
            return "\(pathWithoutExtension)-compressed.\(pathExtension)"
        }
    }

    // If custom directory specified, images will be saved there
    return inputUrls.map { url in
        let originalPath = (url as NSString)
        let filename = originalPath.lastPathComponent
        let filenameWithoutExtension = (filename as NSString).deletingPathExtension
        let pathExtension = originalPath.pathExtension
        return (directory! as NSString).appendingPathComponent(
            "\(filenameWithoutExtension)-compressed.\(pathExtension)")
    }
}

// MARK: - Quick Compression Tool

/// Input for quick image compression without additional options.
/// This tool provides a simple way to compress images using default settings.
@Schemable
struct QuickCompressInput {
    /// Array of file paths to compress.
    /// Each path should point to an image file or directory.
    let urls: [String]
}

// MARK: - Advanced Compression Tool

/// Input for advanced image compression with customizable options.
/// This tool provides full control over the compression process including format,
/// quality level, output location, and other settings.
@Schemable
struct AdvancedCompressInput {
    /// Array of file paths to compress.
    /// Each path should point to an image file or directory.
    let urls: [String]

    /// Compression level (1 ~ 6).
    /// Higher values mean more compression but lower quality.
    /// Default levels: 2-3 provide good balance between quality and size.
    let level: Double?

    /// Output format for compressed images.
    /// Supported formats: "original", "jpeg", "webp", "heic", "avif", "png"
    let format: String?

    /// Output directory path for compressed images.
    /// Only used when specified is false and location is "custom".
    /// If not provided in this case, images will be saved alongside originals.
    let directory: String?

    /// Target width for image resizing.
    /// Set to 0 for auto-adjustment while maintaining aspect ratio.
    let width: Double?

    /// Target height for image resizing.
    /// Set to 0 for auto-adjustment while maintaining aspect ratio.
    let height: Double?

    /// Location type for saving compressed images.
    /// Options: "original" - same as source, "custom" - use specified directory
    /// Only used when specified is false.
    let location: String?

    /// Whether to add a suffix to compressed file names.
    /// If true, the suffix will be appended to the original filename.
    let addSuffix: Bool?

    /// Custom suffix for compressed file names.
    /// Only used when addSuffix is true.
    /// Example: "-compressed" will result in "image-compressed.jpg"
    let suffix: String?

    /// Whether to create a subfolder for compressed images.
    /// If true, compressed images will be saved in a new subfolder.
    let addSubfolder: Bool?

    /// Whether to use Zipic's default directory settings.
    /// If true: uses Zipic's default directory settings (ignores location and directory)
    /// If false: uses custom location settings (requires location to be set)
    let specified: Bool?
}

let advancedCompressTool = Tool(name: "advancedCompress") {
    (input: AdvancedCompressInput) async throws -> [TextContentOrImageContentOrEmbeddedResource] in
    // Check if Zipic is installed
    guard isZipicInstalled() else {
        return [
            .text(TextContent(text: "Error: Zipic app is not installed. Please install Zipic from https://zipic.app"))
        ]
    }

    // Validate location and directory settings
    if input.specified == false {
        if input.location == "custom" && input.directory == nil {
            return [
                .text(
                    TextContent(
                        text: "Error: When specified is false and location is 'custom', directory must be provided"))
            ]
        }
    }

    // Build base URL
    var urlComponents = URLComponents(string: "zipic://compress")!
    var queryItems: [URLQueryItem] = []

    // Add URL parameters (can have multiple)
    for urlPath in input.urls {
        queryItems.append(URLQueryItem(name: "url", value: urlPath))
    }

    // Add optional parameters
    if let level = input.level {
        queryItems.append(URLQueryItem(name: "level", value: String(level)))
    }

    if let format = input.format {
        queryItems.append(URLQueryItem(name: "format", value: format))
    }

    // Only add location and directory if specified is false
    if input.specified == false {
        if let location = input.location {
            queryItems.append(URLQueryItem(name: "location", value: location))

            if location == "custom", let directory = input.directory {
                queryItems.append(URLQueryItem(name: "directory", value: directory))
            }
        }
    }

    if let width = input.width {
        queryItems.append(URLQueryItem(name: "width", value: String(width)))
    }

    if let height = input.height {
        queryItems.append(URLQueryItem(name: "height", value: String(height)))
    }

    if let addSuffix = input.addSuffix {
        queryItems.append(URLQueryItem(name: "addSuffix", value: String(addSuffix)))
    }

    if let suffix = input.suffix {
        queryItems.append(URLQueryItem(name: "suffix", value: suffix))
    }

    if let addSubfolder = input.addSubfolder {
        queryItems.append(URLQueryItem(name: "addSubfolder", value: String(addSubfolder)))
    }

    if let specified = input.specified {
        queryItems.append(URLQueryItem(name: "specified", value: String(specified)))
    }

    urlComponents.queryItems = queryItems

    // Get final URL
    guard let finalURL = urlComponents.url else {
        return [.text(TextContent(text: "Error: Unable to create a valid URL"))]
    }

    // Calculate expected output paths
    let outputPaths = calculateOutputPaths(
        inputUrls: input.urls, directory: input.directory, specified: input.specified)

    // Use AppKit to open URL
    if NSWorkspace.shared.open(finalURL) {
        var response = [TextContent(text: "Successfully launched Zipic for advanced image compression.")]

        // Add output paths information if available
        if !outputPaths.isEmpty {
            response.append(TextContent(text: "\nExpected output paths:"))
            for path in outputPaths {
                response.append(TextContent(text: "\n- \(path)"))
            }
        } else if input.specified == true {
            response.append(TextContent(text: "\nImages will be saved to Zipic's default directory."))
        }

        return response.map { .text($0) }
    } else {
        return [.text(TextContent(text: "Error: Unable to open Zipic app."))]
    }
}

let quickCompressTool = Tool(name: "quickCompress") {
    (input: QuickCompressInput) async throws -> [TextContentOrImageContentOrEmbeddedResource] in
    // Check if Zipic is installed
    guard isZipicInstalled() else {
        return [
            .text(TextContent(text: "Error: Zipic app is not installed. Please install Zipic from https://zipic.app"))
        ]
    }

    // Simple compression tool implementation
    let urlComponents = URLComponents(string: "zipic://compress")!
    var queryItems: [URLQueryItem] = []

    // Add URL parameters for each path
    for urlPath in input.urls {
        queryItems.append(URLQueryItem(name: "url", value: urlPath))
    }

    var components = urlComponents
    components.queryItems = queryItems

    guard let finalURL = components.url else {
        return [.text(TextContent(text: "Error: Unable to create a valid URL"))]
    }

    // Calculate expected output paths (quick compress always saves alongside original)
    let outputPaths = calculateOutputPaths(inputUrls: input.urls, directory: nil, specified: false)

    if NSWorkspace.shared.open(finalURL) {
        var response = [TextContent(text: "Successfully launched Zipic for quick image compression.")]

        // Add output paths information
        response.append(TextContent(text: "\nExpected output paths:"))
        for path in outputPaths {
            response.append(TextContent(text: "\n- \(path)"))
        }

        return response.map { .text($0) }
    } else {
        return [.text(TextContent(text: "Error: Unable to open Zipic app."))]
    }
}
