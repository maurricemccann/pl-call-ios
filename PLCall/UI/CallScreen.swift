import Accessibility
import PhotosUI
import SwiftUI

/// The call screen, twin of the R1 Call: REPLAY, Claude's avatar and name pill, the voice picker; the transcript;
/// the status line; then AUTO | PUSH, the quick replies and the round CALL / END button.
struct CallScreen: View {
    let model: CallModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Panel: String, Identifiable {
        case voices, settings, question
        var id: String { rawValue }
    }

    @State private var panel: Panel? = nil
    @State private var picked: PhotosPickerItem?
    @State private var showsPhotos = false
    @State private var showsCamera = false
    @AppStorage("plcall.edgeLight") private var edgeLight = false
    @State private var selectTick = 0
    @State private var connectTick = 0
    @State private var endTick = 0
    @State private var approveTick = 0
    @State private var denyTick = 0
    @State private var errorTick = 0
    @State private var turnTick = 0

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(model: CallModel) { self.model = model }

    var body: some View {
        ZStack {
            TranscriptView(model: model)
                .safeAreaInset(edge: .top, spacing: 0) { topBar }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomArea }
            if showsEdgeLight {
                MicEdgeLight(model: model)
                    .transition(.opacity)
            }
        }
        .animation(PLMotion.standard(reduce: reduceMotion), value: showsEdgeLight)
        .animation(PLMotion.standard(reduce: reduceMotion), value: model.pendingAsk)
        .sheet(item: $panel) { kind in
            panelView(kind)
        }
        .onChange(of: model.pendingAsk, initial: true) { _, _ in
            if pendingQuestion != nil {
                panel = .question
            } else if panel == .question {
                panel = nil
            }
        }
        .onChange(of: model.state) { old, new in
            AccessibilityNotification.Announcement(new.plLabel).post()
            if new == .listening, old == .speaking || old == .working { turnTick += 1 }   // a light tap: his turn
        }
        .onChange(of: model.lastError) { _, new in
            if let new {
                errorTick += 1
                AccessibilityNotification.Announcement(new).post()
            }
        }
        .sensoryFeedback(PLHaptic.select, trigger: selectTick)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: turnTick)
        .sensoryFeedback(PLHaptic.connect, trigger: connectTick)
        .sensoryFeedback(PLHaptic.end, trigger: endTick)
        .sensoryFeedback(PLHaptic.approve, trigger: approveTick)
        .sensoryFeedback(PLHaptic.deny, trigger: denyTick)
        .sensoryFeedback(PLHaptic.error, trigger: errorTick)
    }

    // MARK: What the model is asking

    private var pendingQuestion: PermissionRequest.Question? {
        guard let ask = model.pendingAsk else { return nil }
        if case .question(_, _, let question, _) = ask { return question }
        return nil
    }

    private struct Permission {
        let id: String
        let forWhat: String
        let what: String
    }

    private var pendingPermission: Permission? {
        guard let ask = model.pendingAsk else { return nil }
        if case .permission(let requestId, _, let forWhat, let what) = ask {
            return Permission(id: requestId, forWhat: forWhat, what: what)
        }
        return nil
    }

    /// The glow shows only while the mic is open, and never with Reduce Motion.
    private var showsEdgeLight: Bool {
        if reduceMotion || !edgeLight { return false }
        return model.state == .listening || model.state == .hearing
    }

    /// Green when the line is up, red when it is down, grey while it checks (the R1's presence ring).
    private var ringColor: Color {
        if model.state == .lost { return T.end }
        if model.state == .connecting { return Color(uiColor: .systemGray) }
        if model.isInCall || model.statusLine.hasPrefix("Line ready") { return T.call }
        return Color(uiColor: .systemGray)
    }

    private var voiceLabel: String {
        for voice in model.voices where voice.id == model.voiceID { return voice.label }
        return "Voice"
    }

    // MARK: Top bar

    private var topBar: some View {
        GlassEffectContainer {
            ZStack(alignment: .top) {
                HStack(alignment: .top) {
                    Button {
                        selectTick += 1
                        model.replay()
                    } label: {
                        Group {
                            if typeSize.isAccessibilitySize {
                                Image(systemName: "arrow.counterclockwise")
                            } else {
                                Text("REPLAY").plFont(.footnote, emphasized: true)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(minWidth: T.touch, minHeight: T.touch)
                        .contentShape(Capsule())
                    }
                    .glassControl()
                    .accessibilityLabel("Replay")
                    .accessibilityHint("Reads Claude's last reply again")

                    Spacer(minLength: T.gap)

                    Button {
                        panel = .voices
                    } label: {
                        Group {
                            if typeSize.isAccessibilitySize {
                                Image(systemName: "waveform")
                            } else {
                                Text(voiceLabel.uppercased())
                                    .plFont(.footnote, emphasized: true)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(minWidth: T.touch, minHeight: T.touch)
                        .contentShape(Capsule())
                    }
                    .glassControl()
                    .accessibilityLabel("Voice")
                    .accessibilityValue(voiceLabel)
                }

                Button {
                    panel = .settings
                } label: {
                    VStack(spacing: 4) {
                        ClaudeAvatar(ring: ringColor, speaking: model.state == .speaking && !reduceMotion,
                                     working: model.state == .working && !reduceMotion, beat: model.workBeat)
                        HStack(spacing: 6) {
                            StateDot(state: model.state)
                            Text("Claude").plHand(17, relativeTo: .headline)
                            Text(model.state.plLabel)
                                .plFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Claude")
                .accessibilityValue(model.state.plLabel)
                .accessibilityHint("Opens settings")
            }
            .padding(.horizontal, T.margin)
            .padding(.top, 4)
            .padding(.bottom, T.gap)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)   // a bar, like the system's: capped; the status line below stays full size
    }

    // MARK: Bottom area

    private var bottomArea: some View {
        VStack(spacing: T.gap) {
            if let permission = pendingPermission {
                ApproveCard(forWhat: permission.forWhat, what: permission.what) { allow, note in
                    if allow { approveTick += 1 } else { denyTick += 1 }
                    model.answerPermission(allow: allow, message: note)
                }
                .id(permission.id)
                .transition(.opacity)
            }
            statusLines
            GlassEffectContainer {
                if typeSize.isAccessibilitySize {
                    // his layout 11-12: the mode switch and the round buttons on top, his slash commands below
                    VStack(spacing: T.gap) {
                        HStack(spacing: T.gap) {
                            modeSwitch
                            Spacer(minLength: 0)
                            stopButton
                            audioButton
                            pictureButton
                            talkButton
                            callButton
                        }
                        quickReplies
                    }
                } else {
                    // two rows (his 8:2x PM note: "the UI at the bottom looks squished"): the quick replies get the full
                    // width above, the mode switch and the round buttons sit below with room to breathe
                    // his layout 11-12: the mode switch and the round buttons on top, his slash commands below
                    VStack(spacing: T.gap) {
                        HStack(spacing: T.gap) {
                            modeSwitch
                            Spacer(minLength: 0)
                            stopButton
                            audioButton
                            pictureButton
                            talkButton
                            callButton
                        }
                        quickReplies
                    }
                }
            }
        }
        .padding(.horizontal, T.margin)
        .padding(.top, T.gap)
        .padding(.bottom, T.gap)
    }

    private var statusLines: some View {
        VStack(spacing: 6) {
            if pendingQuestion != nil && panel != .question {
                Button {
                    panel = .question
                } label: {
                    Text("Claude asks. Open the question")
                        .plFont(.footnote, emphasized: true)
                        .padding(.horizontal, 14)
                        .frame(minHeight: T.touch)
                        .contentShape(Capsule())
                }
                .glassControl()
            }
            Text(model.statusLine)
                .plFont(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let error = model.lastError {
                NoteLine(symbol: "exclamationmark.triangle.fill", tint: T.end, text: error)
            }
        }
    }

    // MARK: Controls

    /// AUTO | PUSH as two segments (his ruling 11-12: the single circle was only for the R1's tiny screen).
    /// The chosen one is filled: orange for AUTO, blue for PUSH.
    private var modeSwitch: some View {
        HStack(spacing: 0) {
            modeButton("AUTO", handsFree: true)
            modeButton("PUSH", handsFree: false)
        }
        .padding(.horizontal, 3)
        .glassEffect(.regular.interactive(), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Listening mode")
    }

    private func modeButton(_ title: String, handsFree: Bool) -> some View {
        let selected = model.handsFree == handsFree
        return Button {
            selectTick += 1
            if !selected {
                model.setHandsFree(handsFree)
            } else if !handsFree && model.isInCall {
                model.talk()   // already on PUSH: a press talks, as on the R1
            }
        } label: {
            Text(title)
                .plFont(.caption, emphasized: true)
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background(selected ? (handsFree ? T.orange : Color.blue) : Color.clear, in: Capsule())
                .frame(minHeight: T.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var quickReplies: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(model.quickReplies, id: \.label) { reply in
                    quickReplyChip(reply)
                }
            }
            .padding(.horizontal, 6)
        }
        .scrollIndicators(.hidden)
        .frame(minHeight: T.touch)
        .opacity(model.isInCall ? 1 : 0.6)
        .clipShape(Capsule())
        .glassEffect(.regular, in: Capsule())
        .disabled(!model.isInCall)
    }

    private func quickReplyChip(_ reply: PLCallConfig.QuickReply) -> some View {
        let armed = model.armedReply == reply.label
        return Button {
            selectTick += 1
            model.tapQuickReply(reply)
        } label: {
            Text(armed ? "AGAIN?" : reply.label)
                .plFont(.caption, emphasized: true)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: 38)
                .background(armed ? T.plate : Color.clear, in: Capsule())
                .frame(minHeight: T.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(armed ? "\(reply.label). Press again to send" : reply.label)
    }

    /// One tap while Claude is talking: the voice stops now.
    @ViewBuilder
    private var stopButton: some View {
        if model.isInCall, model.state == .speaking {
            Button {
                selectTick += 1
                model.stopTalking()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: T.touch, height: T.touch)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassControl(in: Circle())
            .accessibilityLabel("Stop Claude talking")
        }
    }

    /// Speaker, the iPhone's earpiece or AirPods, during a call.
    @ViewBuilder
    private var audioButton: some View {
        if model.isInCall {
            AudioRouteButton()
                .frame(width: T.touch, height: T.touch)
                .glassControl(in: Circle())
        }
    }

    /// A picture or a screenshot from Photos, sent to Claude.
    private var pictureButton: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showsCamera = true
                } label: {
                    Label("Take a photo", systemImage: "camera")
                }
            }
            Button {
                showsPhotos = true
            } label: {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: T.touch, height: T.touch)
                .contentShape(Circle())
        }
        .glassControl(in: Circle())
        .accessibilityLabel("Send Claude a picture")
        .photosPicker(isPresented: $showsPhotos, selection: $picked, matching: .images)
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { image in
                selectTick += 1
                model.sendPicture(image)
            }
            .ignoresSafeArea()
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    selectTick += 1
                    model.sendPicture(image)
                }
                picked = nil
            }
        }
    }

    @ViewBuilder
    private var talkButton: some View {
        if !model.handsFree && model.isInCall {
            Button {
                selectTick += 1
                model.talk()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: T.touch, height: T.touch)
                    .contentShape(Circle())
            }
            .glassControl(in: Circle())
            .accessibilityLabel("Talk")
        }
    }

    /// The one tinted control: green to call, red to end.
    private var callButton: some View {
        Button {
            if model.isInCall {
                endTick += 1
                model.endCall()
            } else {
                connectTick += 1
                model.startCall()
            }
        } label: {
            Image(systemName: model.isInCall ? "phone.down.fill" : "phone.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white)
                .contentTransition(.symbolEffect)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .glassControl(tint: callTint, in: Circle())
        .accessibilityLabel(model.isInCall ? "End call" : "Call")
    }

    /// One tinted control at a time: while a permission waits, Approve carries the tint and End goes plain.
    private var callTint: Color? {
        if model.isInCall { return pendingPermission == nil ? T.end : nil }
        return T.call
    }

    // MARK: Sheets

    @ViewBuilder
    private func panelView(_ kind: Panel) -> some View {
        switch kind {
        case .voices:
            VoicePickerView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .settings:
            SettingsView(model: model)
        case .question:
            if let question = pendingQuestion {
                QuestionSheet(question: question) { option in
                    selectTick += 1
                    model.answerQuestion(option: option)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

/// The Edge Light reads the mic level itself, so the dozen level changes a second redraw only the glow, not the call screen.
private struct MicEdgeLight: View {
    let model: CallModel

    var body: some View {
        EdgeLight(level: model.micLevel)
    }
}
