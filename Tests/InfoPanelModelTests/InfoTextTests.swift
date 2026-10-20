import Testing
@testable import InfoPanelModel

@Suite struct InfoTextTests {
    @Test func plainTextHasTitlesAndLabelledRows() {
        let sections = [
            InfoSection(title: "File", rows: [InfoRow(label: "Name", value: "a.mp4")]),
            InfoSection(title: "Video", rows: [InfoRow(label: "Codec", value: "h264")]),
        ]
        #expect(InfoText.plain(sections) == "File\nName: a.mp4\n\nVideo\nCodec: h264")
    }

    @Test func sectionsWithoutRowsAreLeftOut() {
        let sections = [InfoSection(title: "Empty", rows: []),
                        InfoSection(title: "File", rows: [InfoRow(label: "Name", value: "a.mp4")])]
        #expect(InfoText.plain(sections) == "File\nName: a.mp4")
        #expect(InfoText.plain([]) == "")
    }

    @Test func sectionIdDefaultsToTheTitle() {
        #expect(InfoSection(title: "File", rows: []).id == "File")
        #expect(InfoSection(id: "file", title: "File", rows: []).id == "file")
    }
}
