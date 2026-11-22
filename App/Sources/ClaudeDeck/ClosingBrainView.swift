import DeckCore
import SwiftUI

struct ClosingBrainView: View {
    @Bindable var store: DeckStore
    let request: ClosingRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.mode == .terminate ? "¿Guardar el cerebro de esta sesión?" : "La sesión terminó. ¿Guardas su cerebro?")
                .font(.title3.weight(.semibold))
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
            BrainText(content: store.workingBrainContent(request.sessionId) ?? "")
                .frame(height: 260)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            TextField("Nombre del cerebro", text: $store.closingName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Descartar", role: .destructive) { store.discardClosingBrain() }
                Spacer()
                Button("Cancelar") { store.cancelClosing() }
                    .keyboardShortcut(.cancelAction)
                if request.mode == .terminate {
                    Button("Guardar tal cual") { store.saveClosingBrain(updatingFirst: false) }
                    Button("Actualizar y guardar") { store.saveClosingBrain(updatingFirst: true) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Guardar") { store.saveClosingBrain(updatingFirst: false) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private var explanation: String {
        let base = store.baseBrainName(of: request.sessionId)
        let target = base.map { "Si lo guardas con el nombre “\($0)”, ese especialista se actualiza con lo aprendido." }
            ?? "Guardarlo lo convierte en un especialista para arrancar sesiones futuras."
        if request.mode == .terminate {
            return target + " “Actualizar y guardar” le pide a Claude un último repaso antes de cerrar. Descartar lo borra."
        }
        return target + " Descartar lo borra."
    }
}
