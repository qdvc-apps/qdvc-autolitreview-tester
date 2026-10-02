import XCTest
@testable import AutoLitReviewCore

final class ReferenceTests: XCTestCase {
    private func only(_ text: String) throws -> BibEntry {
        let entries = BibTeX.entries(in: text)
        XCTAssertEqual(entries.count, 1)
        return try XCTUnwrap(entries.first)
    }

    // MARK: Parsing

    func testParsesFieldsQuotesConcatenationAndMacros() throws {
        let entries = BibTeX.entries(in: """
        % A comment line
        @string{icis = "International Conference on Information Systems"}
        @comment{@article{fake, title={no}}}
        @InProceedings{lee2023,
          author = "Lee, Kim and Park, Ji-Woo",
          title = "Can {LLMs} screen abstracts?",
          booktitle = "Proceedings of the 44th " # icis,
          pages = {1--15}, year = 2023, month = dec,
          note = {Nested {braces {deep}} and "quotes"}
        }
        @article(Smith 2020, title = {Spaced key})
        """)
        XCTAssertEqual(entries.map(\.key), ["lee2023", "Smith 2020"])
        XCTAssertEqual(entries.map(\.line), [4, 11])
        let lee = entries[0]
        XCTAssertEqual(lee.type, "inproceedings")
        XCTAssertEqual(lee["booktitle"], "Proceedings of the 44th International Conference on Information Systems")
        XCTAssertEqual(lee["title"], "Can {LLMs} screen abstracts?")
        XCTAssertEqual(lee["year"], "2023")
        XCTAssertEqual(lee["month"], "December")
        XCTAssertEqual(lee["note"], "Nested {braces {deep}} and \"quotes\"")
        XCTAssertEqual(lee["pages"], "1--15")
        XCTAssertEqual(entries[1]["title"], "Spaced key")
    }

    func testLaTeXCleaning() {
        XCTAssertEqual(LaTeX.clean("{\\'E}cole na\\\"{\\i}ve Fran\\c{c}ois"), "\u{C9}cole na\u{EF}ve Fran\u{E7}ois")
        XCTAssertEqual(LaTeX.clean("Stra\\ss e and {\\o}ster"), "Stra\u{DF}e and \u{F8}ster")
        XCTAssertEqual(LaTeX.clean("R\\&D, 50\\% off, 1990--2000 --- done"), "R&D, 50% off, 1990\u{2013}2000 \u{2014} done")
        XCTAssertEqual(LaTeX.clean("\\emph{Very}   good~idea {AIS}"), "Very good idea AIS")
        XCTAssertEqual(LaTeX.clean("M{\\\"u}ller"), "M\u{FC}ller")
        XCTAssertEqual(LaTeX.clean(nil), "")
    }

    func testNames() {
        let names = PersonName.parseList(
            "Smith, John A. and van der Berg, Jean-Paul and {World Health Organization} and Jane Q. Public and King, Jr., Martin and others")
        XCTAssertEqual(names.map(\.invertedAPA), [
            "Smith, J. A.", "van der Berg, J.-P.", "World Health Organization", "Public, J. Q.", "King, M., Jr.",
        ])
        XCTAssertEqual(PersonName.parse("Ludwig van Beethoven").invertedAPA, "van Beethoven, L.")
        XCTAssertEqual(PersonName.parse("Doe, Jane").directAPA, "J. Doe")
        XCTAssertTrue(PersonName.parse("{Cochrane Collaboration}").isOrganisation)
        XCTAssertEqual(PersonName.parseList("Anderson, A. and Brandt, B.").count, 2)
        XCTAssertEqual(PersonName.parseList("{Johnson and Johnson}").map(\.family), ["Johnson and Johnson"])
    }

    // MARK: APA 7

    func testJournalArticle() throws {
        let entry = try only("""
        @article{smith2024,
          author = {Smith, John A. and van der Berg, Jean-Paul and {World Health Organization}},
          title = {Automated literature reviews: {A} systematic evaluation},
          journal = {Journal of the {AIS}},
          volume = {25}, number = {3}, pages = {101--130}, year = 2024,
          doi = {https://doi.org/10.17705/1jais.00123},
        }
        """)
        let reference = APA7.format(entry)
        XCTAssertEqual(reference.plain,
                       "Smith, J. A., van der Berg, J.-P., & World Health Organization. (2024). Automated literature reviews: A systematic evaluation. Journal of the AIS, 25(3), 101\u{2013}130. doi:10.17705/1jais.00123")
        XCTAssertEqual(reference.segments.filter(\.italic).map(\.text), ["Journal of the AIS", "25"])
        XCTAssertTrue(reference.html.contains("<i>Journal of the AIS</i>, <i>25</i>(3), 101\u{2013}130."))
        XCTAssertEqual(APA7.shortCitation(entry), "Smith et al. (2024)")
        XCTAssertEqual(APA7.doi(of: entry), "doi:10.17705/1jais.00123")
    }

    func testConferencePaperWithEditors() throws {
        let entry = BibTeX.entries(in: """
        @string{icis = "International Conference on Information Systems"}
        @inproceedings{lee2023,
          author = "Lee, Kim and Park, Ji-Woo",
          title = "Can {LLMs} screen abstracts?",
          booktitle = "Proceedings of the 44th " # icis,
          editor = {Doe, Jane and Roe, Richard},
          pages = {1--15}, year = {2023}, publisher = {AIS},
          doi = {10.1234/icis.2023.42}
        }
        """)[0]
        XCTAssertEqual(APA7.format(entry).plain,
                       "Lee, K., & Park, J.-W. (2023). Can LLMs screen abstracts? In J. Doe & R. Roe (Eds.), Proceedings of the 44th International Conference on Information Systems (pp. 1\u{2013}15). AIS. doi:10.1234/icis.2023.42")
        XCTAssertEqual(APA7.shortCitation(entry), "Lee & Park (2023)")
    }

    func testBookThesisAndMisc() throws {
        let book = try only("@book{k, author={Kitchenham, Barbara and Budgen, David and Brereton, Pearl}, title={Evidence-Based Software Engineering and Systematic Reviews}, edition={2nd}, publisher={CRC Press}, year={2015}, url={https://example.org/ebse}}")
        XCTAssertEqual(APA7.format(book).plain,
                       "Kitchenham, B., Budgen, D., & Brereton, P. (2015). Evidence-Based Software Engineering and Systematic Reviews (2nd ed.). CRC Press. https://example.org/ebse")
        XCTAssertEqual(APA7.format(book).segments.filter(\.italic).map(\.text),
                       ["Evidence-Based Software Engineering and Systematic Reviews"])

        let thesis = try only("@phdthesis{t, author={M{\\\"u}ller, Anna}, title={Screening at scale}, school={Universit{\\\"a}t Wien}, year={2022}}")
        XCTAssertEqual(APA7.format(thesis).plain,
                       "M\u{FC}ller, A. (2022). Screening at scale [Doctoral dissertation, Universit\u{E4}t Wien].")

        let misc = try only("@misc{m, title={{PRISMA} 2020 checklist}, howpublished={\\url{https://prisma-statement.org}}, year={2021}}")
        XCTAssertEqual(APA7.format(misc).plain, "PRISMA 2020 checklist. (2021). https://prisma-statement.org")

        let undated = try only("@article{u, author={Solo, Han}, title={Undated}, journal={J}}")
        XCTAssertEqual(APA7.format(undated).plain, "Solo, H. (n.d.). Undated. J.")
    }

    func testTwentyOneOrMoreAuthors() {
        let names = (1...22).map { PersonName.parse("Author\($0), Xavier") }
        let list = APA7.authorList(names)
        XCTAssertTrue(list.hasPrefix("Author1, X., Author2, X.,"))
        XCTAssertTrue(list.hasSuffix("Author19, X., . . . Author22, X."))
        XCTAssertFalse(list.contains("Author20"))
        XCTAssertEqual(APA7.authorList(Array(names.prefix(2))), "Author1, X., & Author2, X.")
    }

    func testDOINormalisation() {
        XCTAssertEqual(APA7.normalizedDOI("https://doi.org/10.1234/abcd9999"), "doi:10.1234/abcd9999")
        XCTAssertEqual(APA7.normalizedDOI("http://dx.doi.org/10.1234/abcd9999"), "doi:10.1234/abcd9999")
        XCTAssertEqual(APA7.normalizedDOI("DOI: 10.1234/abcd9999"), "doi:10.1234/abcd9999")
        XCTAssertEqual(APA7.normalizedDOI("10.1234/abcd9999"), "doi:10.1234/abcd9999")
        XCTAssertEqual(APA7.normalizedDOI("{10.1234/ABCD\\_9999}"), "doi:10.1234/ABCD_9999")
        XCTAssertNil(APA7.normalizedDOI("  "))
        XCTAssertNil(APA7.normalizedDOI(nil))
    }

    func testGroundTruthProblems() {
        XCTAssertEqual(GroundTruth(source: "not bibtex").problem, "No BibTeX entry was found")
        XCTAssertNil(GroundTruth(source: "@article{a, title={A}}").problem)
        let two = GroundTruth(source: "@article{a, title={A}}\n@article{b, title={B}}")
        XCTAssertEqual(two.entryCount, 2)
        XCTAssertEqual(two.entry?.key, "a")
        XCTAssertTrue(two.problem?.contains("2 entries") ?? false)
        XCTAssertNil(GroundTruth(source: "@article{a, title={A}}").doi)
        let withDOI = GroundTruth(source: "@article{a, title={A}, doi={https://doi.org/10.1234/abcd9999}}")
        XCTAssertEqual(withDOI.doi, "doi:10.1234/abcd9999")
        XCTAssertEqual(withDOI.bareDOI, "10.1234/abcd9999")
        XCTAssertNil(GroundTruth(source: "@article{a, title={A}}").bareDOI)
    }
}
