import AppKit
import SwiftUI

struct NewSessionView: View {
    @Bindable var store: DeckStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nueva sesión")
                .font(.title3.weight(.semibold))
            if !store.recentDirectories.isEmpty {
                Text("Carpetas recientes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.recentDirectories, id: \.self) { directory in
                        Button {
                            create(in: directory)
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(URL(fileURLWithPath: directory).lastPathComponent)
                                    Text(directory)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                    }
                }
            }
            Button("Elegir otra carpeta…", action: chooseDirectory)
            Picker("Cerebro", selection: $store.newSessionBrain) {
                Text("Ninguno (empieza vacío)").tag(String?.none)
                ForEach(store.savedBrains) { brain in
                    Text(brain.name).tag(Optional(brain.slug))
                }
            }
            .font(.callout)
            Toggle("Saltar permisos (bypassPermissions)", isOn: $store.skipPermissions)
                .font(.callout)
            HStack {
                Spacer()
                Button("Cancelar") {
                    store.showingNewSession = false
                    store.newSessionBrain = nil
                }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func create(in directory: String) {
        store.showingNewSession = false
        store.newSession(in: directory)
        store.newSessionBrain = nil
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Abrir aquí"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        create(in: url.path)
    }
}
