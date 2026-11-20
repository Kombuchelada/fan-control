import Charts
import FanKit
import SwiftUI

/// "Fan Curve" settings tab: the curve chart and the curve choice.
struct FanCurveSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                CurveChart(selected: model.profile, temperature: model.snapshot.controlTemperature,
                           speed: model.profile == .automatic ? nil : model.snapshot.fans.map(\.fraction).max())
                    .frame(height: 170)
                    .padding(.vertical, 4)

                Picker("Fan curve", selection: Binding(get: { model.profile }, set: { model.select($0) })) {
                    ForEach(FanProfile.allCases) { profile in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.name)
                            Text(profile.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(profile)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .disabled(model.isApplying || !model.isSMCAvailable)

                Text(model.profile.details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } footer: {
                if model.profile != .automatic {
                    Text("Fans return to automatic control when Fan Control quits. Above \(Int(CurveController.safetyStart)) °C every curve speeds the fans up, so no setting can let your Mac overheat.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .settingsPaneStyle()
    }
}

/// "Sensors" settings tab: live temperatures and fan speeds.
struct SensorsSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Temperatures") {
                LabeledContent("CPU", value: Format.temperature(model.snapshot.cpu))
                if model.snapshot.gpu != nil {
                    LabeledContent("Graphics", value: Format.temperature(model.snapshot.gpu))
                }
            }

            Section("Fans") {
                if model.snapshot.fans.isEmpty {
                    Text("No fans found").foregroundStyle(.secondary)
                }
                ForEach(model.snapshot.fans) { fan in
                    LabeledContent {
                        HStack(spacing: 8) {
                            Gauge(value: fan.fraction) { EmptyView() }
                                .gaugeStyle(.accessoryLinearCapacity)
                                .frame(width: 80)
                            Text(Format.rpm(fan.rpm))
                                .frame(minWidth: 72, alignment: .trailing)
                        }
                    } label: {
                        Text(fan.name)
                        Text(Format.rpmRange(fan.minimumRPM, fan.maximumRPM))
                    }
                }
            }
        }
        .settingsPaneStyle()
    }
}

/// "General" settings tab.
struct GeneralSettingsView: View {
    @Bindable var model: AppModel
    @State private var confirmingUninstall = false

    var body: some View {
        Form {
            Section {
                Toggle("Show temperature in menu bar", isOn: $model.showsTemperatureInMenuBar)
                Toggle("Open at login", isOn: $model.opensAtLogin)
            }

            Section {
                LabeledContent {
                    if model.helperInstalled {
                        Button("Uninstall…") { confirmingUninstall = true }
                    }
                } label: {
                    Text("Fan control helper")
                    Text(model.helperInstalled
                         ? "Installed. Lets Fan Control set fan speeds."
                         : "Installed the first time you choose a fan curve.")
                }
            }
        }
        .settingsPaneStyle()
        .confirmationDialog("Uninstall the fan control helper?", isPresented: $confirmingUninstall) {
            Button("Uninstall", role: .destructive) { model.uninstallHelper() }
        } message: {
            Text("Your fans will return to automatic control. Fan Control will ask to install the helper again the next time you choose a fan curve.")
        }
        .onAppear { model.refreshLoginItemStatus() }
    }
}

private extension View {
    /// Shared look for settings tabs. The height is left flexible so a tab scrolls
    /// when the screen is too short to show all of it.
    func settingsPaneStyle() -> some View {
        formStyle(.grouped)
            .frame(width: 480)
            .monospacedDigit()
    }
}

/// Plots every curve, emphasizing the selected one, with a marker at the live temperature.
struct CurveChart: View {
    let selected: FanProfile
    let temperature: Double?
    /// Current fan speed (0...1) when a curve is active.
    let speed: Double?

    private static let domain = 30.0...100.0
    private static let curves = FanProfile.allCases.filter { $0.curve != nil }

    var body: some View {
        Chart {
            ForEach(Self.curves) { profile in
                ForEach(samples(for: profile), id: \.temperature) { sample in
                    LineMark(x: .value("Temperature", sample.temperature),
                             y: .value("Fan speed", sample.speed * 100),
                             series: .value("Curve", profile.name))
                        .foregroundStyle(profile == selected ? Color.accentColor : Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: profile == selected ? 2.5 : 1.25, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                }
            }

            if let temperature {
                RuleMark(x: .value("Now", temperature.clamped(to: Self.domain)))
                    .foregroundStyle(.orange.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text(Format.temperature(temperature))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                if let speed {
                    PointMark(x: .value("Now", temperature.clamped(to: Self.domain)), y: .value("Fan speed", speed * 100))
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(60)
                }
            }
        }
        .chartXScale(domain: Self.domain)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: 10)) { value in
                AxisGridLine()
                AxisValueLabel { if let t = value.as(Double.self) { Text("\(Int(t))°") } }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(v == 0 ? "Min" : v == 100 ? "Max" : "\(Int(v))%") }
                }
            }
        }
        .chartLegend(.hidden)
        .overlay {
            if selected == .automatic {
                Text("macOS is managing the fans")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .accessibilityLabel("Fan curves")
        .accessibilityValue(selected.curve.map { "\(selected.name): \(describe($0))" } ?? "Automatic")
        .animation(.easeInOut(duration: 0.25), value: selected)
    }

    private func samples(for profile: FanProfile) -> [(temperature: Double, speed: Double)] {
        guard let curve = profile.curve else { return [] }
        let breakpoints = curve.points.map(\.temperature).filter { Self.domain.contains($0) }
        let temps = Set([Self.domain.lowerBound, Self.domain.upperBound] + breakpoints).sorted()
        return temps.map { ($0, curve.speed(at: $0)) }
    }

    private func describe(_ curve: FanCurve) -> String {
        var parts: [String] = []
        if let quiet = curve.quietUntil { parts.append("minimum speed until \(Int(quiet)) degrees") }
        if let full = curve.fullSpeedAt { parts.append("full speed at \(Int(full)) degrees") }
        return parts.joined(separator: ", ")
    }
}
