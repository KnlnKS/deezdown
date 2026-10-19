import DeezDownKit
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(settings: $model.settings)
            }
            Tab("Naming", systemImage: "textformat") {
                NamingSettings(settings: $model.settings)
            }
            Tab("Artwork", systemImage: "photo") {
                ArtworkSettings(settings: $model.settings)
            }
            Tab("Tags", systemImage: "tag") {
                TagsSettings(settings: $model.settings)
            }
            Tab("Metadata", systemImage: "slider.horizontal.3") {
                MetadataSettings(settings: $model.settings)
            }
        }
        .frame(width: 560, height: 460)
        .tint(.brand)
    }
}

private struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form { content() }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
    }
}

private struct GeneralSettings: View {
    @Binding var settings: DownloadSettings

    var body: some View {
        SettingsForm {
            Section("Downloads") {
                LabeledContent("Location") {
                    HStack(spacing: 6) {
                        Text(settings.downloadLocation)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Picker("Quality", selection: $settings.maxBitrate) {
                    ForEach(TrackFormat.selectable, id: \.self) { format in
                        Text(format.displayName)
                            .tag(format)
                    }
                }
                Toggle("Fall back to a lower quality when unavailable", isOn: $settings.fallbackBitrate)
                Toggle("Search Deezer for an alternative when a track fails", isOn: $settings.fallbackSearch)
                Toggle("Try other releases with the same ISRC", isOn: $settings.fallbackISRC)
                Stepper(
                    "Simultaneous downloads: \(settings.queueConcurrency)",
                    value: $settings.queueConcurrency, in: 1...16
                )
            }

            Section("Existing files") {
                Picker("When a file already exists", selection: $settings.overwriteFile) {
                    ForEach(OverwriteMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }

            Section("Extras") {
                Toggle("Write an .m3u8 playlist file", isOn: $settings.createM3U8File)
                if settings.createM3U8File {
                    TemplateField(
                        "Playlist filename", text: $settings.playlistFilenameTemplate,
                        tokens: PathBuilder.collectionTokens
                    )
                }
                Toggle("Write .lrc synced lyrics files", isOn: $settings.syncedLyrics)
                Toggle("Log failures to errors.txt", isOn: $settings.logErrors)
                Toggle("Log tracks found by search to searched.txt", isOn: $settings.logSearched)
            }

            Section {
                TextField("Run after each download", text: $settings.executeCommand, prompt: Text("Shell command"))
                    .font(.system(.callout, design: .monospaced))
            } footer: {
                Text("%folder% and %filename% are replaced with the download's folder and, for a single track, its file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: settings.downloadLocation)
        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadLocation = url.path(percentEncoded: false)
        }
    }
}

private struct NamingSettings: View {
    @Binding var settings: DownloadSettings

    var body: some View {
        SettingsForm {
            Section("Filenames") {
                TemplateField("Single track", text: $settings.tracknameTemplate, tokens: PathBuilder.trackTokens)
                TemplateField("Album track", text: $settings.albumTracknameTemplate, tokens: PathBuilder.trackTokens)
                TemplateField("Playlist track", text: $settings.playlistTracknameTemplate, tokens: PathBuilder.trackTokens)
            }

            Section("Folders") {
                Toggle("Artist folder", isOn: $settings.createArtistFolder)
                if settings.createArtistFolder {
                    TemplateField("Artist folder name", text: $settings.artistNameTemplate, tokens: PathBuilder.artistTokens)
                }
                Toggle("Album folder", isOn: $settings.createAlbumFolder)
                if settings.createAlbumFolder {
                    TemplateField("Album folder name", text: $settings.albumNameTemplate, tokens: PathBuilder.albumTokens)
                }
                Toggle("Playlist folder", isOn: $settings.createPlaylistFolder)
                if settings.createPlaylistFolder {
                    TemplateField("Playlist folder name", text: $settings.playlistNameTemplate, tokens: PathBuilder.playlistTokens)
                }
                Toggle("CD folder for multi-disc albums", isOn: $settings.createCDFolder)
                Toggle("Folder for single tracks too", isOn: $settings.createSingleFolder)
                Toggle("Album structure inside playlists", isOn: $settings.createStructurePlaylist)
            }

            Section("Track numbers") {
                Toggle("Pad track numbers", isOn: $settings.padTracks)
                if settings.padTracks {
                    Stepper(
                        settings.paddingSize == 0 ? "Width: automatic" : "Width: \(settings.paddingSize)",
                        value: $settings.paddingSize, in: 0...8
                    )
                    Toggle("Pad single digits to two", isOn: $settings.padSingleDigit)
                }
                TextField("Replace illegal characters with", text: $settings.illegalCharacterReplacer)
            }
        }
    }
}

private struct TemplateField: View {
    var title: String
    @Binding var text: String
    var tokens: [String]

    init(_ title: String, text: Binding<String>, tokens: [String]) {
        self.title = title
        _text = text
        self.tokens = tokens
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, text: $text)
                    .labelsHidden()
                    .font(.system(.callout, design: .monospaced))
                Menu {
                    ForEach(tokens, id: \.self) { token in
                        Button("%\(token)%") { text += "%\(token)%" }
                    }
                } label: {
                    Image(systemName: "curlybraces")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Insert a placeholder")
            }
        }
    }
}

private struct ArtworkSettings: View {
    @Binding var settings: DownloadSettings

    var body: some View {
        SettingsForm {
            Section("Embedded") {
                Toggle("Embed cover art in tags", isOn: $settings.tags.cover)
                Stepper(
                    "Size: \(settings.embeddedArtworkSize) px", value: $settings.embeddedArtworkSize,
                    in: 100...Artwork.maximumSize, step: 100
                )
                Toggle("Embed as PNG", isOn: $settings.embeddedArtworkPNG)
                Toggle("UTF-8 cover description (iTunes fix)", isOn: $settings.tags.coverDescriptionUTF8)
            }

            Section("Saved alongside the music") {
                Toggle("Save album cover", isOn: $settings.saveArtwork)
                if settings.saveArtwork {
                    TemplateField("Cover filename", text: $settings.coverImageTemplate, tokens: PathBuilder.albumTokens)
                    Picker("Format", selection: $settings.localArtworkFormat) {
                        Text("JPEG").tag("jpg")
                        Text("PNG").tag("png")
                        Text("Both").tag("jpg,png")
                    }
                }
                Toggle("Save artist image", isOn: $settings.saveArtworkArtist)
                if settings.saveArtworkArtist {
                    TemplateField(
                        "Artist image filename", text: $settings.artistImageTemplate,
                        tokens: PathBuilder.artistTokens
                    )
                }
                Stepper(
                    "Size: \(settings.localArtworkSize) px", value: $settings.localArtworkSize,
                    in: 100...Artwork.maximumSize, step: 100
                )
                Stepper(
                    "JPEG quality: \(settings.jpegImageQuality)", value: $settings.jpegImageQuality,
                    in: 40...100, step: 5
                )
            }

            Section {
                Toggle("Show cover art on files in Finder", isOn: $settings.finderArtwork)
            } footer: {
                Text("Finder reads embedded art from MP3 but not from FLAC, so the cover is attached as the file's icon instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct TagsSettings: View {
    @Binding var settings: DownloadSettings

    var body: some View {
        SettingsForm {
            Section("Write these tags") {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                    Toggle("Title", isOn: $settings.tags.title)
                    Toggle("Artist", isOn: $settings.tags.artist)
                    Toggle("Album", isOn: $settings.tags.album)
                    Toggle("Album artist", isOn: $settings.tags.albumArtist)
                    Toggle("Track number", isOn: $settings.tags.trackNumber)
                    Toggle("Track total", isOn: $settings.tags.trackTotal)
                    Toggle("Disc number", isOn: $settings.tags.discNumber)
                    Toggle("Disc total", isOn: $settings.tags.discTotal)
                    Toggle("Genre", isOn: $settings.tags.genre)
                    Toggle("Year", isOn: $settings.tags.year)
                    Toggle("Date", isOn: $settings.tags.date)
                    Toggle("Length", isOn: $settings.tags.length)
                    Toggle("ISRC", isOn: $settings.tags.isrc)
                    Toggle("Barcode", isOn: $settings.tags.barcode)
                    Toggle("BPM", isOn: $settings.tags.bpm)
                    Toggle("Label", isOn: $settings.tags.label)
                    Toggle("Explicit", isOn: $settings.tags.explicit)
                    Toggle("Replay gain", isOn: $settings.tags.replayGain)
                    Toggle("Lyrics", isOn: $settings.tags.lyrics)
                    Toggle("Synced lyrics", isOn: $settings.tags.syncedLyrics)
                    Toggle("Composer", isOn: $settings.tags.composer)
                    Toggle("Involved people", isOn: $settings.tags.involvedPeople)
                    Toggle("Copyright", isOn: $settings.tags.copyright)
                    Toggle("Source", isOn: $settings.tags.source)
                    Toggle("Rating", isOn: $settings.tags.rating)
                    Toggle("ID3v1 tag", isOn: $settings.tags.saveID3v1)
                }
            }

            Section("Artists") {
                Picker("Multiple artists", selection: $settings.tags.multiArtistSeparator) {
                    ForEach(ArtistSeparator.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Write the ARTISTS tag as well", isOn: $settings.tags.artists)
                    .disabled(settings.tags.multiArtistSeparator == .standard)
                Toggle("Separate MP3 multi-value tags with nulls", isOn: $settings.tags.useNullSeparator)
                Toggle("Single album artist only", isOn: $settings.tags.singleAlbumArtist)
                Toggle("Tag playlists as compilations", isOn: $settings.tags.savePlaylistAsCompilation)
            }
        }
    }
}

private struct MetadataSettings: View {
    @Environment(AppModel.self) private var model
    @Binding var settings: DownloadSettings

    var body: some View {
        SettingsForm {
            Section("Titles") {
                Picker("Featured artists", selection: $settings.featuredToTitle) {
                    ForEach(FeaturedTitleMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Remove \"(Album Version)\"", isOn: $settings.removeAlbumVersion)
                Toggle("Remove duplicate artist names", isOn: $settings.removeDuplicateArtists)
                Toggle("Keep \"Various Artists\"", isOn: $settings.albumVariousArtists)
                Picker("Title casing", selection: $settings.titleCasing) {
                    ForEach(TextCasing.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Artist casing", selection: $settings.artistCasing) {
                    ForEach(TextCasing.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section {
                TextField("Date format", text: $settings.dateFormat)
                    .font(.system(.callout, design: .monospaced))
            } header: {
                Text("Dates")
            } footer: {
                Text("Y, M and D stand for the year, month and day, as in Y-M-D or D/M/Y.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button("Reset All Settings…", role: .destructive) { model.resetSettings() }
            } footer: {
                Text("Restores every setting on every tab to its default.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
