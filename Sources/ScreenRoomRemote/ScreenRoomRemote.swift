import SwiftUI
import AppKit

#if SWIFT_PACKAGE
private let assetBundle = Bundle.module
#else
private let assetBundle = Bundle.main
#endif

@MainActor final class TV: ObservableObject {
    @Published var address = UserDefaults.standard.string(forKey: "tvAddress") ?? ""
    @Published var connected = false
    @Published var message = "Checking connection…"
    @Published var screenshot: NSImage?
    @Published var showingScreen = false
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
            self.screenshot = image; self.showingScreen = true; self.message = "TV screen captured"
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
    private let panels: [(String,String,String)] = [("comedy","Feel-Good Comedies","Light, funny, and uplifting"),("romance","Romantic Comedies","Love, laughs, and happily ever after"),("escape","Escape & Dream","Feel-good stories in beautiful places"),("notable","New & Notable","Fresh picks to watch now")]
    var body: some View {
        HStack(spacing: 0) { sidebar; main }.background(Color(red: 0.15, green: 0.105, blue: 0.15)).foregroundStyle(.white)
        .sheet(isPresented: $showYouTube) {
            VStack(alignment: .leading, spacing: 14) {
                Text("YouTube on Fire TV").font(.title2.bold())
                Text("Open YouTube or send a specific video link to the TV. Availability and playback depend on YouTube.").foregroundStyle(.secondary)
                TextField("https://www.youtube.com/watch?v=…", text: $youtubeLink).textFieldStyle(.roundedBorder)
                HStack { Button("Open YouTube") { tv.openYouTube(); showYouTube = false }; Button("Open Video") { tv.openYouTubeVideo(youtubeLink); showYouTube = false }.disabled(YouTubeLink.videoID(youtubeLink) == nil); Spacer(); Button("Done") { showYouTube = false } }
                Text("Your browsing history is not connected.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width: 530)
        }
        .sheet(isPresented: $films.showing) { FilmSearchView(films: films).environmentObject(tv) }
        .sheet(isPresented: $showingChat) { MovieChatView(chat: chat) }
        .sheet(isPresented: $tv.showingScreen) { VStack(alignment: .trailing) { Button("Done") { tv.showingScreen = false }; if let image = tv.screenshot { Image(nsImage: image).resizable().scaledToFit() } }.padding().frame(minWidth: 720, minHeight: 450) }
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
            Spacer(minLength: 4)
            Divider().overlay(.white.opacity(0.1))
            featureRow("Siri Shortcuts", "TV Connection", "sparkles")
            featureRow("Movie Night Focus", "Not configured", "moon.fill")
        }.padding(.horizontal,25).padding(.bottom,24).frame(width:300).background(Color(red:0.17,green:0.13,blue:0.17))
    }
    var main: some View {
        VStack(alignment:.leading,spacing:22) {
            HStack(spacing:15) {
                Image(systemName:"tv").font(.system(size:32))
                VStack(alignment:.leading,spacing:5) { Text(tv.connected ? "TV Connected" : "TV Disconnected").font(.system(size:21,weight:.bold)); HStack(spacing:6) { Circle().fill(tv.connected ? .green : .orange).frame(width:8,height:8); Text(tv.message).lineLimit(1).font(.system(size:12)).foregroundStyle(.white.opacity(0.65)) } }
                Spacer()
                TextField("TV address",text:$tv.address).textFieldStyle(.roundedBorder).frame(width:125).onChange(of: tv.address) { tv.connected = false; tv.message = "Address changed. Select Connect." }.onSubmit { tv.connect() }
                Button("Connect") { tv.connect() }.buttonStyle(.bordered)
                Button("Netflix") { tv.openNetflix() }.buttonStyle(.bordered)
                Button("YouTube") { showYouTube = true }.buttonStyle(.bordered)
                Button { tv.capture() } label: { Label("See TV",systemImage:"tv") }.buttonStyle(.borderedProminent).tint(Color(red:0.48,green:0.32,blue:0.43))
            }.padding(18).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(.white.opacity(0.07)))
            HStack { Image(systemName:"magnifyingglass"); TextField("Search film titles",text:$search).textFieldStyle(.plain).onSubmit { films.query = search; films.showing = true; films.search() }; Button("Search") { films.query = search; films.showing = true; films.search() }.buttonStyle(.plain).font(.subheadline.bold()) }.font(.system(size:19)).padding(16).background(Color(red:0.25,green:0.18,blue:0.24),in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(.pink.opacity(0.45)))
            VStack(alignment:.leading,spacing:4) { Text("Discover Movies").font(.system(size:28,weight:.bold)); Text("Handpicked ideas for your next movie night.").foregroundStyle(.white.opacity(0.65)); Text("Preview categories · Press Return to search Screen Room’s catalog").font(.caption).foregroundStyle(.white.opacity(0.45)) }
            GeometryReader { geometry in let width = max(100, (geometry.size.width - 48) / 4); HStack(alignment:.top,spacing:16) { ForEach(panels,id:\.0) { panel in VStack(alignment:.leading,spacing:7) { if let url = assetBundle.url(forResource: panel.0, withExtension:"png"), let image = NSImage(contentsOf:url) { Image(nsImage:image).resizable().aspectRatio(contentMode:.fill).frame(width:width,height:190).clipped().clipShape(RoundedRectangle(cornerRadius:16)) }; Text(panel.1).font(.system(size:15,weight:.bold)).lineLimit(1).minimumScaleFactor(0.8); Text(panel.2).font(.system(size:13)).foregroundStyle(.white.opacity(0.7)).lineLimit(2) }.frame(width:width,alignment:.leading) } } }.frame(height:260)
            Spacer(minLength:0)
            HStack(spacing:16) { Image(systemName:"bubble.left").font(.title2).padding(15).background(.white.opacity(0.07),in:Circle()); VStack(alignment:.leading,spacing:5) { Text("Movie Chat").font(.system(size:18,weight:.bold)); Text("Find something to watch, get suggestions, or plan a movie night.").font(.system(size:13)).foregroundStyle(.white.opacity(0.65)); Text("On-device text chat · Voice coming later").font(.caption).foregroundStyle(.white.opacity(0.5)) }; Spacer(); Image(systemName:"waveform").font(.system(size:38)).foregroundStyle(.pink.opacity(0.55)); Button { chat.configure(credential: films.activeCredential); showingChat = true } label: { Image(systemName:"bubble.left.fill").font(.title2).padding(16).background(buttonGradient,in:Circle()) }.buttonStyle(.plain).accessibilityLabel("Open movie chat") }.padding(18).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(.white.opacity(0.07)))
        }.padding(24)
    }
    var buttonGradient: LinearGradient { LinearGradient(colors:[Color(red:0.38,green:0.29,blue:0.37),Color(red:0.17,green:0.12,blue:0.17)],startPoint:.topLeading,endPoint:.bottomTrailing) }
    func direction(_ icon:String,_ key:String)->some View { Button { tv.button(key) } label:{ Image(systemName:icon).font(.system(size:20,weight:.medium)).frame(width:44,height:35).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(key.replacingOccurrences(of:"KEYCODE_DPAD_",with:"")) }
    func roundButton(_ title:String,_ icon:String,_ key:String)->some View { Button { tv.button(key) } label:{ VStack(spacing:4) { Image(systemName:icon).font(.system(size:23)); Text(title).font(.system(size:13)) }.frame(width:82,height:82).background(buttonGradient,in:Circle()).overlay(Circle().stroke(.white.opacity(0.12))).shadow(color:.black.opacity(0.5),radius:8,y:5) }.buttonStyle(.plain) }
    func featureRow(_ title:String,_ subtitle:String,_ icon:String)->some View { HStack { Image(systemName:icon).frame(width:30,height:30).background(.white.opacity(0.08),in:Circle()); VStack(alignment:.leading) { Text(title).font(.system(size:13,weight:.semibold)); Text(subtitle).font(.system(size:11)).foregroundStyle(.white.opacity(0.5)) }; Spacer() }.padding(9).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:12)) }
}
