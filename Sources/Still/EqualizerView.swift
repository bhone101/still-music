import AppKit
import StillCore
import SwiftUI

struct EqualizerView: View {
    @ObservedObject var model: PlayerModel

    private var preset: String {
        EqualizerPreset.allCases.first { $0.gains == model.equalizer.gains }?.rawValue ?? "Custom"
    }
    private func change(_ update: (inout EqualizerSettings) -> Void) {
        var settings = model.equalizer
        update(&settings)
        model.applyEqualizer(settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Toggle("Equalizer", isOn: Binding(get: { model.equalizer.enabled }, set: { value in change { $0.enabled = value } }))
                    .toggleStyle(.switch).font(.headline)
                Spacer()
                Button("Reset") {
                    model.applyEqualizer(EqualizerSettings(enabled: model.equalizer.enabled))
                }.help("Reset all bands to zero and restore automatic preamp")
            }
            Picker("Preset", selection: Binding(get: { preset }, set: { name in
                guard let choice = EqualizerPreset(rawValue: name) else { return }
                change { $0.gains = choice.gains }
            })) {
                ForEach(EqualizerPreset.allCases) { choice in Text(choice.rawValue).tag(choice.rawValue) }
                if preset == "Custom" { Text("Custom").tag("Custom") }
            }.disabled(!model.equalizer.enabled)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    band(label: "Preamp", accessibility: "Preamp", value: Binding(get: { model.equalizer.preamp }, set: { gain in change { $0.manualPreamp = gain } }), enabled: model.equalizer.enabled && !model.equalizer.automaticPreamp)
                    VStack {
                        Text("+12 dB")
                        Spacer()
                        Text("0 dB")
                        Spacer()
                        Text("−12 dB")
                    }.font(.caption).foregroundStyle(.secondary).frame(height: 180).padding(.top, 24)
                    Divider().frame(height: 240)
                    ForEach(0..<10, id: \.self) { index in
                        let frequency = EqualizerSettings.frequencies[index]
                        let label = frequency >= 1000 ? "\(Int(frequency / 1000))K" : "\(Int(frequency))"
                        band(label: label, accessibility: "\(Int(frequency)) hertz", value: Binding(get: { model.equalizer.gains[index] }, set: { gain in change { $0.gains[index] = gain } }), enabled: model.equalizer.enabled)
                    }
                }.padding(.vertical, 4)
            }
            Toggle("Automatic preamp", isOn: Binding(get: { model.equalizer.automaticPreamp }, set: { value in
                change { settings in
                    if !value { settings.manualPreamp = settings.preamp }
                    settings.automaticPreamp = value
                }
            })).disabled(!model.equalizer.enabled)
            Text(model.equalizer.automaticPreamp
                 ? "Lowers the preamp to leave room for boosted bands. Turn off to adjust it yourself."
                 : "Manual preamp: positive gain can cause distortion. Lower it if needed.")
                .font(.caption).foregroundStyle(.secondary)
            Text(model.equalizer.enabled ? "Changes play immediately. Turning EQ off briefly interrupts playback to bypass processing." : "Off · Original sound. Your settings are kept.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func band(label: String, accessibility: String, value: Binding<Float>, enabled: Bool) -> some View {
        VStack(spacing: 8) {
            Text(String(format: "%+.0f", value.wrappedValue)).font(.caption).monospacedDigit()
                .foregroundStyle(enabled ? Palette.ink : Palette.muted)
            VerticalEQSlider(value: value, label: accessibility, enabled: enabled).frame(width: 28, height: 180)
            Text(label).font(.caption).monospacedDigit()
        }.frame(width: 40)
    }
}

/// Native vertical sliders retain keyboard and VoiceOver support.
private struct VerticalEQSlider: NSViewRepresentable {
    @Binding var value: Float
    let label: String
    let enabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(frame: NSRect(x: 0, y: 0, width: 28, height: 180))
        slider.minValue = -12
        slider.maxValue = 12
        slider.numberOfTickMarks = 25
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.floatValue = value
        slider.isEnabled = enabled
        slider.setAccessibilityLabel(label)
        slider.setAccessibilityValueDescription("\(Int(value)) decibels")
    }
    final class Coordinator: NSObject {
        var parent: VerticalEQSlider
        init(_ parent: VerticalEQSlider) { self.parent = parent }
        @objc func changed(_ slider: NSSlider) { parent.value = slider.floatValue.rounded() }
    }
}
