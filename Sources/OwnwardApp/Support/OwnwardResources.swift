import Foundation

enum OwnwardResources {
    static func url(name: String, extension fileExtension: String, subdirectory: String? = nil) -> URL? {
        Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: fileExtension)
    }
}
