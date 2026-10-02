import Foundation

/// Test IDs and the canonical names of the files in a test folder
/// (docs/FILE_FORMAT.md §2).
public enum Naming {
    // MARK: - Test IDs

    /// A–Z, 0–9 and the dash. Nothing else, not even a space.
    public static func isAllowedInTestID(_ character: Character) -> Bool {
        guard let a = character.asciiValue else { return false }
        return (a >= 65 && a <= 90) || (a >= 48 && a <= 57) || a == 45
    }

    /// A test ID is one or more of A–Z, 0–9 and dashes.
    public static func isValidTestID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy(isAllowedInTestID)
    }

    /// Cleans up typing in the Test ID field: lowercase a–z become uppercase
    /// and anything else that isn't allowed (spaces, underscores, accented
    /// letters…) is dropped. `removedSomething` says whether anything was
    /// dropped, so the field can beep and explain.
    public static func sanitizeTestID(_ text: String) -> (id: String, removedSomething: Bool) {
        var result = ""
        var removed = false
        for character in text {
            if let a = character.asciiValue, a >= 97, a <= 122 {
                result.unicodeScalars.append(Unicode.Scalar(a - 32))
            } else if isAllowedInTestID(character) {
                result.append(character)
            } else {
                removed = true
            }
        }
        return (result, removed)
    }

    // MARK: - Canonical names

    /// `ID_query` or `ID_query_variantN`.
    public static func queryFolderName(testID: String, variant: Int?) -> String {
        if let variant { return "\(testID)_query_variant\(variant)" }
        return "\(testID)_query"
    }

    /// `ID_` or `ID_variantN_`: what every artifact file name starts with.
    public static func filePrefix(testID: String, variant: Int?) -> String {
        if let variant { return "\(testID)_variant\(variant)_" }
        return "\(testID)_"
    }

    /// The canonical file name of an artifact, e.g. `ABCD-123_variant2_references_n23.bib`.
    public static func fileName(_ kind: ArtifactKind, testID: String, variant: Int?, referenceCount: Int? = nil) -> String {
        filePrefix(testID: testID, variant: variant) + kind.nameSuffix(referenceCount: referenceCount)
    }

    /// The canonical path of an artifact relative to the test folder, e.g.
    /// `ABCD-123_query_variant2/ABCD-123_variant2_query_asked.png`.
    public static func relativePath(_ kind: ArtifactKind, testID: String, variant: Int?, referenceCount: Int? = nil) -> String {
        let name = fileName(kind, testID: testID, variant: variant, referenceCount: referenceCount)
        guard kind.isInQueryFolder else { return name }
        return queryFolderName(testID: testID, variant: variant) + "/" + name
    }

    // MARK: - Sorting

    /// Natural ordering for test IDs and file names, as in Finder: runs of
    /// digits compare by value, so `ABC-2` sorts before `ABC-10`, and a–z
    /// compare as A–Z. Ties (as in `A-01` and `A-1`, or `a` and `A`) fall
    /// back to plain comparison, so the order is total and stable.
    public static func naturalLess(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.unicodeScalars.map(foldCase), b = rhs.unicodeScalars.map(foldCase)
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if isDigit(a[i]), isDigit(b[j]) {
                let si = i, sj = j
                while i < a.count, isDigit(a[i]) { i += 1 }
                while j < b.count, isDigit(b[j]) { j += 1 }
                let da = trimLeadingZeros(a[si..<i]), db = trimLeadingZeros(b[sj..<j])
                if da.count != db.count { return da.count < db.count }
                for (x, y) in zip(da, db) where x != y { return x.value < y.value }
            } else {
                if a[i] != b[j] { return a[i].value < b[j].value }
                i += 1
                j += 1
            }
        }
        if (a.count - i) != (b.count - j) { return (a.count - i) < (b.count - j) }
        return lhs < rhs
    }

    private static func foldCase(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        guard scalar.value >= 97, scalar.value <= 122, let upper = Unicode.Scalar(scalar.value - 32) else {
            return scalar
        }
        return upper
    }

    static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }

    private static func trimLeadingZeros(_ digits: ArraySlice<Unicode.Scalar>) -> ArraySlice<Unicode.Scalar> {
        var slice = digits
        while slice.count > 1, slice.first?.value == 48 { slice = slice.dropFirst() }
        return slice
    }

    // MARK: - Dates

    /// `yyyy-mm-dd` for default export file names.
    public static func dateStamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
