//
//  SwiftPackage.swift
//  LicensePlistCore
//
//  Created by Matthias Buchetics on 20.09.19.
//

import Foundation

public struct SwiftPackage: Equatable {
    let package: String
    let repositoryURL: String
    let revision: String?
    let version: String?
    let packageDefinitionVersion: Int
}

struct SwiftPackageV1: Decodable {
    struct State: Decodable {
        let branch: String?
        let revision: String?
        let version: String?
    }

    let package: String
    let repositoryURL: String
    let state: State
}

struct ResolvedPackagesV1: Decodable {
    struct Pins: Decodable {
        let pins: [SwiftPackageV1]
    }

    let object: Pins
    let version: Int
}

struct SwiftPackageV2: Decodable {
    struct State: Decodable {
        let branch: String?
        let revision: String?
        let version: String?
    }

    let identity: String
    let location: String
    let state: State
}

struct ResolvedPackagesV2: Decodable {
    let pins: [SwiftPackageV2]
    let version: Int
}

extension SwiftPackage {
    static func loadPackages(_ content: String) -> [SwiftPackage] {
        guard let data = content.data(using: .utf8) else { return [] }
        if let resolvedPackagesV1 = try? JSONDecoder().decode(ResolvedPackagesV1.self, from: data) {
            return resolvedPackagesV1.object.pins.map {
                SwiftPackage(package: $0.package, repositoryURL: $0.repositoryURL, revision: $0.state.revision, version: $0.state.version, packageDefinitionVersion: 1)
            }
        } else if let resolvedPackagesV2 = try? JSONDecoder().decode(ResolvedPackagesV2.self, from: data) {
            return resolvedPackagesV2.pins.map {
                SwiftPackage(package: $0.identity, repositoryURL: $0.location, revision: $0.state.revision, version: $0.state.version, packageDefinitionVersion: 2)
            }
        } else {
            return []
        }
    }

    func toGitHub(renames: [String: String]) -> GitHub? {
        guard repositoryURL.contains("github.com") else { return nil }

        let urlParts = repositoryURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .components(separatedBy: "/")

        let name = urlParts.last?.deletingSuffix(".git") ?? ""
        let owner: String
        if urlParts.count >= 3 {
            owner = urlParts[urlParts.count - 2]
        } else {
            owner = urlParts.first?.components(separatedBy: ":").last ?? ""
        }

        return GitHub(name: name,
                      nameSpecified: renames[name] ?? getDefaultName(for: owner, and: name),
                      owner: owner,
                      version: version)
    }

    private func getDefaultName(for owner: String, and name: String) -> String {
        guard packageDefinitionVersion != 1 else { return package } // In SPM v1 the Package.resolved JSON always contains the correct name, no need for anything else.
        guard let version = version else { return fallbackName(using: name) }
        guard let packageDefinitionURL = URL(string: "https://raw.githubusercontent.com/\(owner)/\(name)/\(version)/Package.swift") else { return fallbackName(using: name) }
        guard let packageDefinition = try? String(contentsOf: packageDefinitionURL) else { return fallbackName(using: name) }
        return parseName(from: packageDefinition) ?? fallbackName(using: name)
    }

    private func fallbackName(using githubName: String) -> String {
        packageDefinitionVersion == 1 ? package : githubName
    }

    func parseName(from packageDefinition: String) -> String? {
        // Step 1 - Trim the beginning of the Package Description to where the Package object is starting to be defined -> return as a one-liner without spaces
        let startingPoint = packageDefinition
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .components(separatedBy: "let package = Package")[1]

        // Step 2 - Assemble Reduced Package Description
        // This removes all nested square brackets and everything written after the closing round bracket of the Package definition
        var nestingRoundBracketsCounter = 0
        var nestingSquareBracketsCounter = 0
        var reducedPackageDescription = ""

        parsing: for character in startingPoint {
            switch character {
            case "(":
                nestingRoundBracketsCounter += 1
                reducedPackageDescription.append(nestingSquareBracketsCounter == 0 ? "\(character)" : "")

            case ")":
                nestingRoundBracketsCounter -= 1
                reducedPackageDescription.append(nestingSquareBracketsCounter == 0 ? "\(character)" : "")
                if nestingRoundBracketsCounter < 1 {
                    break parsing
                }

            case "[":
                nestingSquareBracketsCounter += 1

            case "]":
                nestingSquareBracketsCounter -= 1

            default:
                reducedPackageDescription.append(nestingSquareBracketsCounter == 0 ? "\(character)" : "")
            }
        }

        // Step 3 - Retrieve name from the reduced Package Description
        // We can now be confident that we only have the top level description which has exactly one name.

        let name = reducedPackageDescription
            .replacingOccurrences(of: "name\\s?:\\s?\"", with: "name:\"", options: .regularExpression)
            .components(separatedBy: "name:\"")
            .element(at: 1)
            .components(separatedBy: "\"")
            .element(at: 0)

        return name.isEmpty ? nil : name
    }

}

extension Array where Element == String {

    func element(at index: Int) -> String {
        guard (0 ..< count).contains(index) else { return "" }
        return String(self[index])
    }

}
