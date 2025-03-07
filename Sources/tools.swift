import AppKit
import Foundation
import JSONSchemaBuilder
@preconcurrency import MCPServer

// MARK: - Utility Functions

/// Check if Zipic app is installed
func isZipicInstalled() -> Bool {
    let zipicBundleID = "studio.5km.zipic"
    let isInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: zipicBundleID) != nil
    return isInstalled
}

/// Calculate output path for compressed images
func calculateOutputPaths(inputUrls: [String], directory: String?, specified: Bool? = false) -> [String] {
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
            let outputPath = "\(pathWithoutExtension)-compressed.\(pathExtension)"
            return outputPath
        }
    }

    // If custom directory specified, images will be saved there
    return inputUrls.map { url in
        let originalPath = (url as NSString)
        let filename = originalPath.lastPathComponent
        let filenameWithoutExtension = (filename as NSString).deletingPathExtension
        let pathExtension = originalPath.pathExtension
        let outputPath = (directory! as NSString).appendingPathComponent(
            "\(filenameWithoutExtension)-compressed.\(pathExtension)")
        return outputPath
    }
}

// MARK: - Quick Compression Tool

/// Input for quick image compression without additional options.
/// This tool provides a simple way to compress images using default settings.
@Schemable
struct QuickCompressInput {

    @SchemaOptions(
        title: "URLs",
        description:
            "Array of file paths to compress. Each path MUST be an absolute path pointing to either: - An image file (e.g., \"/Users/name/Pictures/photo.jpg\") - A directory containing images (e.g., \"/Users/name/Pictures/vacation\")"
    )
    let urls: [String]

}

// MARK: - Advanced Compression Tool

@Schemable
struct AdvancedCompressInput {

    @SchemaOptions(
        title: "URLs",
        description: """
            Array of file paths to compress. Each path MUST be an absolute path pointing to either:
              An image file (e.g., "/Users/name/Pictures/photo.jpg")
              A directory containing images (e.g., "/Users/name/Pictures/vacation")
            """
    )
    let urls: [String]

    @NumberOptions(minimum: 1, maximum: 6)
    @SchemaOptions(
        title: "Level",
        description: """
            Compression level (MUST be an integer between 1 and 6).
            Higher values mean more compression but lower quality.
            Default levels: 2-3 provide good balance between quality and size.
            Examples:
              1: Highest quality, minimal compression
              6: Maximum compression, lowest quality
            default: 3
            """,
        default: 3
    )
    let level: Int?

    @SchemaOptions(
        title: "Format",
        description: """
            Output format for compressed images.
            Supported formats: "original", "jpeg", "webp", "heic", "avif", "png"
            default: "original"
            """,
        default: "original"
    )
    let format: String?

    @SchemaOptions(
        title: "Directory",
        description: """
            Output directory path for compressed images.
            MUST be an absolute path.
            Only used when specified is false and location is "custom".
            If not provided in this case, images will be saved alongside originals.
            default: nil
            """
    )
    let directory: String?

    @NumberOptions(minimum: 0)
    @SchemaOptions(
        title: "Width",
        description: """
            Target width for image resizing.
            Set to 0 for auto-adjustment while maintaining aspect ratio.
            default: 0
            """,
        default: 0
    )
    let width: Int?

    @NumberOptions(minimum: 0)
    @SchemaOptions(
        title: "Height",
        description: """
            Target height for image resizing.
            Set to 0 for auto-adjustment while maintaining aspect ratio.
            default: 0
            """,
        default: 0
    )
    let height: Int?

    @SchemaOptions(
        title: "Suffix",
        description: """
            Custom suffix for compressed file names.
            Only used when addSuffix is true.
            Example: "-compressed" will result in "image-compressed.jpg"
            default: nil
            """
    )
    let suffix: String?
}

let advancedCompressTool = Tool(
    name: "advancedCompress",
    description: "Advanced image compression tool"
) { (input: AdvancedCompressInput) async throws -> [TextContentOrImageContentOrEmbeddedResource] in
    // Check if Zipic is installed
    guard isZipicInstalled() else {
        return [
            .text(TextContent(text: "Error: Zipic app is not installed. Please install Zipic from https://zipic.app"))
        ]
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

    if let directory = input.directory {
        queryItems.append(URLQueryItem(name: "directory", value: directory))
        queryItems.append(URLQueryItem(name: "location", value: "custom"))
        queryItems.append(URLQueryItem(name: "specified", value: "false"))
    }

    if let width = input.width {
        queryItems.append(URLQueryItem(name: "width", value: String(width)))
    }

    if let height = input.height {
        queryItems.append(URLQueryItem(name: "height", value: String(height)))
    }

    if let suffix = input.suffix {
        queryItems.append(URLQueryItem(name: "suffix", value: suffix))
        queryItems.append(URLQueryItem(name: "addSuffix", value: "true"))
    }

    urlComponents.queryItems = queryItems

    // Get final URL
    guard let finalURL = urlComponents.url else {
        return [.text(TextContent(text: "Error: Unable to create a valid URL"))]
    }

    // Calculate expected output paths
    let outputPaths = calculateOutputPaths(
        inputUrls: input.urls,
        directory: input.directory
    )

    // Use AppKit to open URL
    if NSWorkspace.shared.open(finalURL) {
        var response = [TextContent(text: "Successfully launched Zipic for advanced image compression.")]

        // Add output paths information if available
        if !outputPaths.isEmpty {
            response.append(TextContent(text: "\nExpected output paths:"))
            for path in outputPaths {
                response.append(TextContent(text: "\n- \(path)"))
            }
        }

        return response.map { .text($0) }
    } else {
        return [.text(TextContent(text: "Error: Unable to open Zipic app."))]
    }
}

let quickCompressTool = Tool(
    name: "quickCompress",
    description: "Quick image compression tool"
) { (input: QuickCompressInput) async throws -> [TextContentOrImageContentOrEmbeddedResource] in
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
