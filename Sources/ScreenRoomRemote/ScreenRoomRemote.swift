import SwiftUI
import AppKit
import FoundationModels
import UniformTypeIdentifiers
import ScreenRoomKit

#if SWIFT_PACKAGE
private let assetBundle = Bundle.module
#else
private let assetBundle = Bundle.main
#endif

@MainActor final class TV: ObservableObject {
    @Published var address = UserDefaults.standard.string(forKey: "tvAddress") ?? ""
    @Published var connected = false
    @Published var message = "Checking connection…"
    @Published var nowPlaying: TVNowPlaying?
    @Published var nowPlayingStatus = "Refresh to check the TV."
    @Published var screenshot: NSImage?
    @Published var showingScreen = false
    @Published var screenshotData: Data?
    @Published var screenDescription: String?
    @Published var describingScreen = false
    private var screenRevision = UUID()
    private let adb = (FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/adb") ? "/opt/homebrew/bin/adb" : "/usr/local/bin/adb")
    private func run(_ args: [String], completion: @escaping (Data?, String?) -> Void) {
        let binary = adb
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process(); process.executableURL = URL(fileURLWithPath: binary); process.arguments = args
            let out = Pipe(), err = Pipe(); process.standardOutput = out; process.standardError = err
            do {
                try process.run()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let error = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let failure = process.terminationStatus == 0 ? nil : String(data: error, encoding: .utf8)
                DispatchQueue.main.async { completion(data, failure) }
            } catch { DispatchQueue.main.async { completion(nil, error.localizedDescription) } }
        }
    }
    func check() {
        let requestedAddress = address
        let target = requestedAddress + ":5555"
        run(["-s", target, "get-state"]) { data, error in
            guard self.address == requestedAddress else { return }
            self.connected = error == nil && String(data: data ?? Data(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "device"
            self.message = self.connected ? "Connected to \(requestedAddress)" : "Not connected. Pair this TV with ADB first."
            if self.connected { self.refreshNowPlaying() }
            else { self.nowPlaying = nil; self.nowPlayingStatus = "TV not connected." }
        }
    }
    func refreshNowPlaying() {
        guard connected else { nowPlaying = nil; nowPlayingStatus = "TV not connected."; return }
        let target = address
        nowPlayingStatus = "Checking the TV…"
        Task {
            let result = await TVMediaSession.read(address: target)
            guard address == target, connected else { return }
            nowPlaying = result
            nowPlayingStatus = result == nil ? "No active title reported by the TV." : "From the TV · checked just now"
        }
    }
    func connect() {
        let requestedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedAddress.isEmpty, requestedAddress.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) else {
            message = "Enter a valid local IP address."; return
        }
        UserDefaults.standard.set(requestedAddress, forKey: "tvAddress")
        message = "Connecting… approve the prompt on your TV if asked."
        run(["connect", requestedAddress + ":5555"]) { data, error in
            guard self.address == requestedAddress else { return }
            let response = String(data: data ?? Data(), encoding: .utf8) ?? ""
            if error != nil || response.localizedCaseInsensitiveContains("failed") || response.localizedCaseInsensitiveContains("unable") {
                self.connected = false
                self.message = "Connection failed. Check ADB and approve the TV prompt."
            } else { self.check() }
        }
    }
    func openNetflix() {
        guard connected else { message = "Connect the TV before opening Netflix."; return }
        run(["-s", address + ":5555", "shell", "monkey", "-p", "com.netflix.ninja", "1"]) { data, error in
            let response = String(data: data ?? Data(), encoding: .utf8) ?? ""
            self.message = error == nil && response.contains("Events injected: 1") ? "Netflix launch requested" : "Couldn’t open Netflix on this TV."
        }
    }
    func button(_ key: String) {
        guard connected else { message = "Connect the TV before using the remote."; return }
        run(["-s", address + ":5555", "shell", "input", "keyevent", key]) { _, error in
            self.message = error == nil ? "Command sent" : "Couldn’t send command: \(error ?? "unknown error")"
        }
    }
    func openYouTube() {
        guard connected else { message = "Connect the TV before opening YouTube."; return }
        run(["-s", address + ":5555", "shell", "monkey", "-p", "com.amazon.firetv.youtube", "1"]) { data, error in
            let response = String(data: data ?? Data(), encoding: .utf8) ?? ""
            self.message = error == nil && response.contains("Events injected: 1") ? "YouTube launch requested" : "Couldn’t open YouTube on this TV."
        }
    }
    func openYouTubeVideo(_ link: String) {
        guard connected else { message = "Connect the TV before opening a video."; return }
        guard let id = YouTubeLink.videoID(link) else { message = "Enter a YouTube watch or youtu.be link."; return }
        let url = "https://youtu.be/" + id
        run(["-s", address + ":5555", "shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", url, "com.amazon.firetv.youtube"]) { data, error in
            let response = String(data: data ?? Data(), encoding: .utf8) ?? ""
            self.message = error == nil && !response.contains("Error:") ? "Video link sent to YouTube; check the TV." : "YouTube couldn’t open that link."
        }
    }
    func capture() {
        guard connected else { message = "Connect the TV before capturing its screen."; return }
        message = "Getting TV screen…"
        run(["-s", address + ":5555", "exec-out", "screencap", "-p"]) { data, error in
            guard error == nil, let data, let image = NSImage(data: data) else { self.message = "Screen unavailable. This app may block capture."; return }
            self.screenRevision = UUID()
            self.screenshot = image; self.screenshotData = data
            self.screenDescription = nil; self.showingScreen = true; self.message = "TV screen captured"
        }
    }
    func saveScreenshot() {
        guard let data = screenshotData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Fire TV screenshot.png"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic) }
            catch { Task { @MainActor in self.message = "Couldn’t save screenshot." } }
        }
    }
    func describeScreenshot() {
        guard !describingScreen, let image = screenshot,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let model = SystemLanguageModel.default
        guard model.availability == .available, model.capabilities.contains(.vision) else {
            screenDescription = "Image understanding is unavailable on this Mac."
            return
        }
        let revision = screenRevision
        describingScreen = true
        screenDescription = nil
        Task {
            defer { describingScreen = false }
            do {
                let session = LanguageModelSession(model: model, instructions: """
                    Describe only what is visible on the supplied TV screenshot. Read visible text accurately.
                    Do not infer a movie title, identity, playback state, or unavailable content. If uncertain, say so.
                    """)
                let result = try await session.respond {
                    "Briefly describe the visible screen and any readable controls or text."
                    Attachment(cgImage)
                }
                if revision == screenRevision { screenDescription = result.content }
            } catch {
                if revision == screenRevision { screenDescription = "Couldn’t describe this screen. Try again." }
            }
        }
    }
}

@main struct ScreenRoomRemoteApp: App {
    @StateObject private var tv = TV()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(tv).frame(minWidth: 1040, minHeight: 720).onAppear { tv.check() } }
        .windowStyle(.hiddenTitleBar)
    }
}

struct ContentView: View {
    @EnvironmentObject var tv: TV
    @State private var search = ""
    @State private var youtubeLink = ""
    @State private var showYouTube = false
    @StateObject private var films = FilmSearch()
    @StateObject private var chat = MovieChat()
    @State private var showingChat = false
    private let sampleArtwork = ["comedy", "romance", "escape", "notable"]
    var body: some View {
        HStack(spacing: 0) { sidebar; main }.background(Color(red: 0.15, green: 0.105, blue: 0.15)).foregroundStyle(.white).onAppear { films.loadFeatured() }
        .sheet(isPresented: $showYouTube) {
            VStack(alignment: .leading, spacing: 14) {
                Text("YouTube on Fire TV").font(.title2.bold())
                Text("Open YouTube or send a specific video link to the TV. Availability and playback depend on YouTube.").foregroundStyle(.secondary)
                TextField("https://www.youtube.com/watch?v=…", text: $youtubeLink).textFieldStyle(.roundedBorder)
                HStack { Button("Open YouTube") { tv.openYouTube(); showYouTube = false }; Button("Send Video Link") { tv.openYouTubeVideo(youtubeLink); showYouTube = false }.disabled(YouTubeLink.videoID(youtubeLink) == nil); Spacer(); Button("Done") { showYouTube = false } }
                Text("Link handling varies by TV and may not start playback. Your browsing history is not connected.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width: 530)
        }
        .sheet(isPresented: $films.showing) { FilmSearchView(films: films).environmentObject(tv) }
        .sheet(isPresented: $showingChat) { MovieChatView(chat: chat) }
         .sheet(isPresented: $tv.showingScreen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("TV Screenshot").font(.title2.bold()); Spacer(); Button("Save…") { tv.saveScreenshot() }; Button("Done") { tv.showingScreen = false } }
                if let image = tv.screenshot { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 430) }
                HStack { Button("Describe with Apple Intelligence") { tv.describeScreenshot() }.disabled(tv.describingScreen); if tv.describingScreen { ProgressView().controlSize(.small) }; Spacer(); Text("Processed on this Mac").font(.caption).foregroundStyle(.secondary) }
                if let description = tv.screenDescription { ScrollView { Text(description).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 120) }
                Text("Some apps block screenshots. A description can be inaccurate.").font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(minWidth: 720, minHeight: 450)
        }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) { Image(systemName:"tv").font(.system(size:30)); VStack(alignment:.leading,spacing:3) { Text("Screen Room Remote").font(.system(size:17,weight:.bold)).lineLimit(1).minimumScaleFactor(0.8); Text("Control · Discover · Watch").font(.system(size:12)).foregroundStyle(.white.opacity(0.55)) } }.padding(.top,28)
            Spacer(minLength: 4)
            ZStack {
                Circle().fill(buttonGradient).overlay(Circle().stroke(.white.opacity(0.14),lineWidth:1)).shadow(color:.black.opacity(0.65),radius:12,y:8)
                VStack { direction("chevron.up","KEYCODE_DPAD_UP"); Spacer(); direction("chevron.down","KEYCODE_DPAD_DOWN") }.padding(16)
                HStack { direction("chevron.left","KEYCODE_DPAD_LEFT"); Spacer(); direction("chevron.right","KEYCODE_DPAD_RIGHT") }.padding(16)
                Button { tv.button("KEYCODE_DPAD_CENTER") } label: { Text("Select").font(.system(size:17,weight:.medium)).frame(width:92,height:92).background(buttonGradient,in:Circle()).overlay(Circle().stroke(.black.opacity(0.8),lineWidth:2)).shadow(color:.black.opacity(0.5),radius:5,y:4) }.buttonStyle(.plain).accessibilityLabel("Select")
            }.frame(width:220,height:220).frame(maxWidth:.infinity)
            HStack(spacing:22) { roundButton("Home","house","KEYCODE_HOME"); roundButton("Back","arrow.uturn.backward","KEYCODE_BACK") }.frame(maxWidth:.infinity)
            Button { tv.button("KEYCODE_MEDIA_PLAY_PAUSE") } label: { Label("Play / Pause",systemImage:"playpause.fill").font(.system(size:15,weight:.medium)).frame(maxWidth:.infinity).frame(height:64).background(buttonGradient,in:Capsule()).overlay(Capsule().stroke(.white.opacity(0.14))).shadow(color:.black.opacity(0.5),radius:8,y:5) }.buttonStyle(.plain)
            HStack {
                Button("Resume", systemImage: "play.fill") { tv.button("KEYCODE_MEDIA_PLAY") }
                Button("Forward", systemImage: "goforward") { tv.button("KEYCODE_MEDIA_FAST_FORWARD") }
            }.buttonStyle(.bordered).frame(maxWidth: .infinity)
            Spacer(minLength: 4)
            Divider().overlay(.white.opacity(0.1))
            featureRow("Siri Shortcuts", "TV Connection", "sparkles")
            featureRow("Movie Night Focus", "Not configured", "moon.fill")
        }.padding(.horizontal,25).padding(.bottom,24).frame(width:300).background(Color(red:0.17,green:0.13,blue:0.17))
    }
    var main: some View {
        ScrollView { VStack(alignment:.leading,spacing:22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName:"tv").font(.system(size:26))
                    VStack(alignment:.leading,spacing:3) {
                        Text(tv.connected ? "TV Connected" : "TV Disconnected").font(.system(size:19,weight:.bold))
                        HStack(spacing:6) { Circle().fill(tv.connected ? .green : .orange).frame(width:8,height:8); Text(tv.message).lineLimit(1).font(.system(size:12)).foregroundStyle(.white.opacity(0.65)) }
                    }
                    Spacer()
                    Button { tv.capture() } label: { Label("See TV",systemImage:"tv") }.buttonStyle(.borderedProminent).tint(Color(red:0.48,green:0.32,blue:0.43))
                }
                HStack {
                    TextField("TV address",text:$tv.address).textFieldStyle(.roundedBorder).frame(width:150).onChange(of: tv.address) { tv.connected = false; tv.nowPlaying = nil; tv.nowPlayingStatus = "TV address changed."; tv.message = "Address changed. Select Connect." }.onSubmit { tv.connect() }
                    Button("Connect") { tv.connect() }
                    Button("Netflix") { tv.openNetflix() }
                    Button("YouTube") { showYouTube = true }
                    Spacer()
                }.buttonStyle(.bordered)
            }.padding(16).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(.white.opacity(0.07)))
            HStack(spacing: 12) {
                Image(systemName: "play.tv").font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tv.nowPlaying?.title ?? "Nothing reported by the TV").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(tv.nowPlaying.map { $0.state + ($0.artist.map { " · " + $0 } ?? "") } ?? tv.nowPlayingStatus).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
                Spacer()
                Button { tv.button("KEYCODE_VOLUME_DOWN") } label: { Image(systemName:"speaker.minus") }.help("Volume down").accessibilityLabel("Volume down")
                Button { tv.button("KEYCODE_VOLUME_MUTE") } label: { Image(systemName:"speaker.slash") }.help("Mute or unmute").accessibilityLabel("Mute or unmute")
                Button { tv.button("KEYCODE_VOLUME_UP") } label: { Image(systemName:"speaker.plus") }.help("Volume up").accessibilityLabel("Volume up")
                Button("Refresh") { tv.refreshNowPlaying() }.disabled(!tv.connected)
            }.padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            HStack { Image(systemName:"magnifyingglass"); TextField("Search film titles",text:$search).textFieldStyle(.plain).onSubmit { films.query = search; films.showing = true; films.search() }; Button("Search") { films.query = search; films.showing = true; films.search() }.buttonStyle(.plain).font(.subheadline.bold()) }.font(.system(size:19)).padding(16).background(Color(red:0.25,green:0.18,blue:0.24),in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(.pink.opacity(0.45)))
            VStack(alignment:.leading,spacing:4) {
                HStack { Text("Discover Movies").font(.system(size:28,weight:.bold)); Spacer(); Button("Refresh") { films.loadFeatured() }.disabled(films.isLoadingFeatured) }
                Text(films.featuredStatus).foregroundStyle(.white.opacity(0.65))
                Text("Catalog titles do not confirm streaming availability.").font(.caption).foregroundStyle(.white.opacity(0.45))
            }
            GeometryReader { geometry in
                let width = max(100, (geometry.size.width - 48) / 4)
                HStack(alignment:.top,spacing:16) {
                    ForEach(Array(films.featured.enumerated()), id: \.element.id) { index, film in
                        Button {
                            films.query = film.title; films.showing = true; films.search()
                        } label: {
                            VStack(alignment:.leading,spacing:7) {
                                Group {
                                    if let url = TMDBImage.url(path: film.posterPath, size: .poster) {
                                        AsyncImage(url: url) { image in image.resizable().aspectRatio(contentMode:.fill) } placeholder: { Color.white.opacity(0.06) }
                                    } else if let url = assetBundle.url(forResource: sampleArtwork[index % sampleArtwork.count], withExtension:"png"), let image = NSImage(contentsOf:url) {
                                        Image(nsImage:image).resizable().aspectRatio(contentMode:.fill)
                                    } else { Color.white.opacity(0.06) }
                                }.frame(width:width,height:190).clipped().clipShape(RoundedRectangle(cornerRadius:16))
                                Text(film.title).font(.system(size:15,weight:.bold)).lineLimit(1).minimumScaleFactor(0.8)
                                Text(film.year ?? "Year unavailable").font(.system(size:13)).foregroundStyle(.white.opacity(0.7))
                            }.frame(width:width,alignment:.leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(height:240)
            Spacer(minLength:0)
            HStack(spacing:16) { Image(systemName:"bubble.left").font(.title2).padding(15).background(.white.opacity(0.07),in:Circle()); VStack(alignment:.leading,spacing:5) { Text("Movie Chat").font(.system(size:18,weight:.bold)); Text("Find something to watch, get suggestions, or plan a movie night.").font(.system(size:13)).foregroundStyle(.white.opacity(0.65)); Text("On-device text chat · Voice coming later").font(.caption).foregroundStyle(.white.opacity(0.5)) }; Spacer(); Image(systemName:"waveform").font(.system(size:38)).foregroundStyle(.pink.opacity(0.55)); Button { chat.configure(credential: films.activeCredential, tvAddress: tv.connected ? tv.address : nil); showingChat = true } label: { Image(systemName:"bubble.left.fill").font(.title2).padding(16).background(buttonGradient,in:Circle()) }.buttonStyle(.plain).accessibilityLabel("Open movie chat") }.padding(18).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(.white.opacity(0.07)))
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading) }
    }
    var buttonGradient: LinearGradient { LinearGradient(colors:[Color(red:0.38,green:0.29,blue:0.37),Color(red:0.17,green:0.12,blue:0.17)],startPoint:.topLeading,endPoint:.bottomTrailing) }
    func direction(_ icon:String,_ key:String)->some View { Button { tv.button(key) } label:{ Image(systemName:icon).font(.system(size:20,weight:.medium)).frame(width:44,height:35).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(key.replacingOccurrences(of:"KEYCODE_DPAD_",with:"")) }
    func roundButton(_ title:String,_ icon:String,_ key:String)->some View { Button { tv.button(key) } label:{ VStack(spacing:4) { Image(systemName:icon).font(.system(size:23)); Text(title).font(.system(size:13)) }.frame(width:82,height:82).background(buttonGradient,in:Circle()).overlay(Circle().stroke(.white.opacity(0.12))).shadow(color:.black.opacity(0.5),radius:8,y:5) }.buttonStyle(.plain) }
    func featureRow(_ title:String,_ subtitle:String,_ icon:String)->some View { HStack { Image(systemName:icon).frame(width:30,height:30).background(.white.opacity(0.08),in:Circle()); VStack(alignment:.leading) { Text(title).font(.system(size:13,weight:.semibold)); Text(subtitle).font(.system(size:11)).foregroundStyle(.white.opacity(0.5)) }; Spacer() }.padding(9).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:12)) }
}
