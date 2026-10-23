import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var server: ProxyServer
    @State private var portText: String = "8888"
    @State private var logFilter = "Eventos"
    @State private var showRotationSetup = false

    private var visibleLog: [ProxyLogEntry] {
        server.logBuffer.entries.filter {
            switch logFilter {
            case "Avisos/erros": return $0.level == .warning || $0.level == .error
            case "Tudo": return true
            default: return $0.level != .debug
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    HStack {
                        Circle()
                            .fill(server.isRunning ? .green : .gray)
                            .frame(width: 10, height: 10)
                        Text(server.isRunning ? "Em execução" : "Parado")
                            .font(.headline)
                        Spacer()
                        Text("\(server.activeConnections) conexões")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    LabeledContent("IP Wi-Fi do iPhone", value: server.localIP)
                    LabeledContent("IP interno da operadora", value: server.cellularIP)
                    LabeledContent {
                        HStack(spacing: 6) {
                            if server.isCheckingPublicIP { ProgressView().controlSize(.mini) }
                            // With no cellular address the last public IP is
                            // stale (e.g. mid airplane-mode rotation).
                            if (server.cellularIP == "—" || server.publicIPLastError != nil) && server.publicIP != "—" {
                                Text("último: \(server.publicIP)")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(server.publicIP).textSelection(.enabled)
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("IP público móvel")
                            if let at = server.publicIPCheckedAt {
                                Text("consultado às \(at.formatted(date: .omitted, time: .standard))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let error = server.publicIPLastError {
                        Text("Consulta indisponível: \(error)")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    LabeledContent("Acesso Guiado", value: server.guidedAccess ? "Ligado" : "Desligado")
                    if let started = server.rotateStartedAt {
                        LabeledContent("Rotação solicitada", value: "às \(started.formatted(date: .omitted, time: .standard))")
                    }
                    LabeledContent("Bytes ↑", value: ByteCountFormatter.string(fromByteCount: Int64(server.bytesUp), countStyle: .binary))
                    LabeledContent("Bytes ↓", value: ByteCountFormatter.string(fromByteCount: Int64(server.bytesDown), countStyle: .binary))
                }

                Section("Proxy") {
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", text: $portText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(server.isRunning)
                            .frame(width: 100)
                    }
                    if server.isRunning {
                        Button {
                            server.refreshPublicIP()
                        } label: {
                            Label("Check public IP now", systemImage: "arrow.clockwise")
                        }
                        .disabled(server.isCheckingPublicIP)
                        Button(role: .destructive) {
                            server.stop()
                        } label: {
                            Label("Stop proxy", systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            if let p = UInt16(portText) { server.port = p }
                            server.start()
                        } label: {
                            Label("Start proxy", systemImage: "play.fill")
                        }
                    }

                    Toggle(isOn: $server.keepAliveEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep alive in background (audio)")
                            Text("Plays silent audio so the proxy survives screen-lock. Costs battery; may pause on a call.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: server.keepAliveEnabled) { _ in
                        server.updateKeepAlive()
                    }
                }

                Section("Conectar no AdsPower — Wi-Fi") {
                    if server.isRunning && server.localIP != "—" {
                        connectionFields(host: server.localIP, port: String(server.port))
                        Text("Use um computador na mesma sub-rede Wi-Fi do iPhone. O endereço exibido é atualizado quando a rede muda.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button {
                            UIPasteboard.general.string = "\(server.localIP):\(server.port)"
                        } label: { Label("Copiar endereço Wi-Fi", systemImage: "doc.on.doc") }
                    } else {
                        Text("\(server.isRunning ? "Wi-Fi indisponível" : "Proxy parado"). O endereço aparecerá quando o proxy e o Wi-Fi estiverem ativos.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Alternativa — USB no mesmo Mac") {
                    connectionFields(host: "127.0.0.1", port: "8889")
                    Text("Requer cabo USB e o túnel aberto pelo Iniciar Proxy iPhone.command no Mac que executa o AdsPower. O iPhone não consegue confirmar se esse túnel está aberto.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Se falhar, desbloqueie o iPhone e execute o .command novamente. Use a porta 8888 no app para esse túnel.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        UIPasteboard.general.string = "127.0.0.1:8889"
                    } label: { Label("Copiar endereço USB", systemImage: "doc.on.doc") }
                }

                Section("Rotação do IP") {
                    LabeledContent("Atalho necessário", value: ProxyServer.rotateShortcutName)
                    Button { server.requestRotate() } label: {
                        Label("Trocar IP agora", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!server.isRunning || server.rotation.isBusy || server.guidedAccess)
                    if server.rotation.isBusy { ProgressView("Rotação em andamento…") }
                    Text(server.rotation.message)
                        .font(.caption).textSelection(.enabled)
                    if server.guidedAccess {
                        Text("Desligue o Acesso Guiado para abrir Atalhos.").font(.caption).foregroundStyle(.orange)
                    }
                    Button("Configurar atalho Rotate IP") { showRotationSetup = true }
                    Text("Instale o atalho antes do primeiro uso. Ao tocar em Trocar IP, o modo avião interromperá a conexão temporariamente. Nenhuma rotação periódica está agendada.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("O atalho reconecta a rede móvel; a operadora pode devolver o mesmo IP. A consulta automática a cada 30 segundos apenas observa o IP, sem executar rotação.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("iMessage / relay rotate") {
                    LabeledContent("Mac paired", value: server.isPaired ? "yes" : "no")
                    LabeledContent("Relay", value: server.relayState)
                    if let last = server.lastRotateCommand {
                        LabeledContent("Last command", value: last)
                    }
                    if let until = server.pairingOpenUntil, until > Date() {
                        Text("Pairing open until \(until.formatted(date: .omitted, time: .standard)) — run macos/rotate-ip.sh --pair on the Mac")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Button {
                            server.openPairingWindow()
                        } label: {
                            Label(server.isPaired ? "Re-pair Mac (2 min window)" : "Pair Mac (2 min window)",
                                  systemImage: "link")
                        }
                        .disabled(!server.isRunning)
                    }
                    if server.isPaired {
                        Button(role: .destructive) {
                            server.unpair()
                        } label: {
                            Label("Unpair", systemImage: "xmark.circle")
                        }
                    }
                }

                Section("Diagnóstico — últimos 300 eventos") {
                    Picker("Filtro", selection: $logFilter) {
                        Text("Eventos").tag("Eventos")
                        Text("Avisos/erros").tag("Avisos/erros")
                        Text("Tudo").tag("Tudo")
                    }.pickerStyle(.segmented)
                    HStack {
                        Button {
                            UIPasteboard.general.string = visibleLog.map(\.formatted).joined(separator: "\n")
                        } label: { Label("Copiar", systemImage: "doc.on.doc") }
                        .disabled(visibleLog.isEmpty)
                        Spacer()
                        Button(role: .destructive) { server.clearLog() } label: {
                            Label("Limpar", systemImage: "trash")
                        }
                    }.buttonStyle(.borderless)
                    Text("\(visibleLog.count) eventos no filtro. Histórico desta execução; não é salvo em disco. IPs e destinos podem aparecer ao copiar.")
                        .font(.caption2).foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if visibleLog.isEmpty {
                                Text("Nenhum evento neste filtro.").foregroundStyle(.secondary)
                            }
                            ForEach(visibleLog.reversed()) { entry in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(entry.timestamp.formatted(date: .omitted, time: .standard)) · \(entry.level.rawValue) · \(entry.category.rawValue)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(entry.level == .error ? .red : entry.level == .warning ? .orange : .secondary)
                                    Text(entry.message).font(.caption).textSelection(.enabled)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(height: 320)
                }
            }
            .navigationTitle("iProxy")
            .sheet(isPresented: $showRotationSetup) {
                NavigationStack {
                    Form {
                        Section("Instalar uma vez neste iPhone") {
                            Text("O botão precisa de um atalho com o nome exato Rotate IP no app Atalhos.")
                            if let file = Bundle.main.url(forResource: "Rotate IP", withExtension: "shortcut") {
                                ShareLink(item: file) { Label("Compartilhar arquivo do atalho", systemImage: "square.and.arrow.up") }
                                Text("Salve o arquivo em Arquivos, abra-o e toque em Adicionar Atalho. Se Rotate IP já aparece no Atalhos, não precisa importar novamente.")
                                    .font(.caption)
                            }
                        }
                        Section("Alternativa: criar no app Atalhos") {
                            Text("1. Crie um atalho chamado Rotate IP.")
                            Text("2. Adicione Definir Modo Avião → Ativar.")
                            Text("3. Adicione Esperar → 91 segundos.")
                            Text("4. Adicione Definir Modo Avião → Desativar.")
                            Text("Salve sem executar. O intervalo é ajustável; não garante outro IP na sua operadora.").font(.caption)
                        }
                        Section("Para usar") {
                            Text("Com o proxy iniciado e o Acesso Guiado desligado, toque em Trocar IP agora. Mantenha Atalhos aberto até terminar e permita o retorno ao iProxy, se o iOS pedir.")
                            Text("Se interromper o atalho, confira se o modo avião ficou desligado. A instalação só pode ser confirmada no app Atalhos; este app não lê sua biblioteca.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Configurar rotação")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluir") { showRotationSetup = false } } }
                }
            }
        }
    }

    @ViewBuilder
    private func connectionFields(host: String, port: String) -> some View {
        LabeledContent("Tipo", value: "HTTP")
        LabeledContent("Host / endereço") { Text(host).monospaced().textSelection(.enabled) }
        LabeledContent("Porta") { Text(port).monospaced().textSelection(.enabled) }
        Text("Usuário e senha em branco. Preencha host e porta nos campos do proxy; não use o IP público móvel.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
