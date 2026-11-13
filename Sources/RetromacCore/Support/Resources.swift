// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum Resources {
    /// Bundle.main first: the .app copies resources into Contents/Resources, because
    /// SwiftPM's Bundle.module expects its bundle at the .app root, which breaks codesign.
    public static func url(_ name: String, ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.module.url(forResource: name, withExtension: ext)
    }
}
