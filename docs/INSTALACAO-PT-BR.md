# Instalação do MyProxy no iPhone e no Mac

O app instalado aparece como **MyProxy**, com ícone próprio. O projeto/target do Xcode e o arquivo compilado `.app` continuam chamados `MobilePhoneProxy`; os comandos deste guia usam esses nomes técnicos.

Este é um fork do [Mobile Phone Proxy](https://github.com/stepanic/mobile-phone-proxy), criado por **Matija Stepanic (@stepanic)**. As melhorias deste fork são mantidas por Wellington Ferraz. O projeto continua sob a [licença MIT](../LICENSE); veja os [créditos](../CREDITS.md).

O app transforma o iPhone em um proxy HTTP com suporte a HTTPS via CONNECT. O Mac pode chegar ao app pela rede Wi-Fi local ou por um túnel USB. Os perfis de navegador usam esse proxy, mas **várias portas ou perfis no mesmo iPhone não criam vários IPs celulares independentes**.

## 1. O que você precisa

- Um Mac com Xcode completo e suas ferramentas de linha de comando.
- Um iPhone físico com iOS 16 ou superior, desbloqueado durante a instalação.
- Uma conta Apple para assinar o app. A assinatura gratuita serve para testes pessoais e precisa ser renovada; veja a seção de distribuição.
- Cabo USB com transmissão de dados para instalar e usar o túnel USB.
- Homebrew, Git e Python 3 no Mac. XcodeGen gera o projeto do Xcode; `libusbmuxd` fornece `iproxy`.
- Dados móveis ativos, se você quiser testar a saída pela operadora.

A configuração mínima do projeto é iOS 16. Isso não significa que todas as versões foram testadas. O teste físico desta versão foi feito em um **iPhone 15 Pro Max com iOS 26.6**, usando macOS 26.4.1 e Xcode 26.6. O segundo aparelho com iOS 27.1 ainda não foi validado. Confira a [compatibilidade do Xcode](https://developer.apple.com/xcode/system-requirements/) com seu Mac e iPhone.

## 2. Baixe o código e instale as ferramentas

No Terminal:

```bash
git clone https://github.com/wellingtonferraz/mobile-phone-proxy.git
cd mobile-phone-proxy
brew install xcodegen libusbmuxd
xcodebuild -version
python3 --version
```

Se `xcodebuild` apontar somente para Command Line Tools, selecione o Xcode completo em **Xcode → Settings → Locations → Command Line Tools**. Abra o Xcode uma vez para concluir a instalação dos componentes solicitados.

Opcional: prepare o arquivo do atalho de rotação para o botão de compartilhamento do app:

```bash
./macos/prepare-shortcut.sh
```

Esse comando assina o modelo legível de `shortcuts/Rotate IP.plist` usando o utilitário Atalhos do macOS. **Ele não executa o atalho nem liga o modo avião.** A assinatura do atalho passa pelo serviço de validação da Apple. O arquivo `.shortcut` gerado é local e ignorado pelo Git. Você também pode criar o atalho manualmente, sem executar esse comando.

## 3. Compile e instale no seu iPhone

```bash
cd ios
xcodegen generate
open MobilePhoneProxy.xcodeproj
```

No Xcode:

1. Entre na sua conta Apple em **Settings → Accounts**.
2. Selecione o projeto e o target **MobilePhoneProxy**. Em **Signing & Capabilities**, selecione seu **Team** e mantenha a assinatura automática.
3. Troque `com.example.mobilephoneproxy` por um **Bundle Identifier próprio e único**, por exemplo `com.seunome.mobilephoneproxy`. Guarde esse valor: o inicializador USB usa o mesmo identificador para abrir o app correto.
4. Conecte e desbloqueie o iPhone. Toque em **Confiar** quando solicitado e selecione esse aparelho como destino de execução.
5. Ative **Modo de Desenvolvedor** nos ajustes de privacidade e segurança do iPhone se o Xcode solicitar. Siga o reinício e a confirmação no aparelho.
6. Clique em **Run**. Se o iPhone pedir confiança no desenvolvedor, siga a orientação em **Ajustes → Geral → VPN e Gerenciamento de Dispositivo**.
7. Abra o app no iPhone e conceda acesso à **Rede Local** quando solicitado. Confirme que o servidor está rodando na porta **8888**.

O repositório não contém certificados, perfis de provisionamento nem a assinatura do mantenedor. Cada pessoa assina sua própria instalação. As alterações feitas somente no projeto gerado podem desaparecer ao executar `xcodegen` novamente; para mantê-las localmente, ajuste também `ios/project.yml`, sem enviar seu Team ou configurações pessoais em uma contribuição.

Se você preparou o `.shortcut` depois de gerar o projeto, execute `xcodegen generate` novamente para incluí-lo e compile de novo.

### Compilação por Terminal

Depois de configurar a assinatura, também é possível usar:

```bash
xcrun xctrace list devices
xcodebuild -project MobilePhoneProxy.xcodeproj \
  -scheme MobilePhoneProxy -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=SEU_TEAM \
  PRODUCT_BUNDLE_IDENTIFIER=com.seunome.mobilephoneproxy build

xcrun devicectl device install app --device SEU_DEVICE_ID \
  build/Build/Products/Debug-iphoneos/MobilePhoneProxy.app
```

Substitua os exemplos pelos seus dados. Para `iproxy`, use o **UDID do iPhone físico** mostrado entre parênteses por `xcrun xctrace list devices`. Não use o identificador de um simulador nem o UUID de CoreDevice mostrado por outras ferramentas.

## 4. Escolha USB ou Wi-Fi

### Pelo USB: `127.0.0.1:8889` no Mac

Volte à raiz do repositório e mantenha o iPhone conectado:

```bash
MPP_BUNDLE_ID=com.seunome.mobilephoneproxy \
  ./macos/start-usb-proxy.sh SEU_UDID_DO_IPHONE
```

O script liga a porta **8889 do Mac** à porta **8888 do iPhone**, escutando apenas em `127.0.0.1`. Ele verifica se o app responde, reutiliza um túnel compatível já existente e pode reiniciar **somente o app configurado no aparelho selecionado** quando ele não responde. Uma porta ocupada por outro processo ou outro aparelho gera um aviso; o script não encerra esse processo.

Para um túnel novo, mantenha o Terminal aberto. **Ctrl+C encerra o túnel criado nessa execução.** Se o script reutilizar um túnel existente, a janela que criou esse túnel precisa continuar aberta.

Também é possível abrir `macos/Iniciar Proxy iPhone.command` com dois cliques. Sem uma configuração prévia, ele solicita o UDID e o Bundle Identifier. Se o macOS impedir a execução de um arquivo baixado, use o Terminal para executar o script de dentro do clone Git.

No AdsPower ou em outro cliente:

| Campo | Valor |
|---|---|
| Tipo | HTTP |
| Endereço | `127.0.0.1` |
| Porta | `8889` |
| Usuário/senha | Em branco |

Esse endereço funciona **somente no Mac que mantém o túnel USB**. Outro computador não pode usar o `127.0.0.1` desse Mac como se fosse um endereço remoto.

### Pelo Wi-Fi: endereço local do iPhone e porta 8888

Conecte Mac e iPhone à mesma rede local confiável. Use o endereço Wi-Fi que o app exibe, por exemplo **`192.168.1.50:8888`**, com tipo HTTP e sem usuário/senha. Esse endereço é apenas um exemplo; use o do seu aparelho.

O app aceita conexões IPv4 por loopback/USB e pela sub-rede Wi-Fi local reconhecida. Conexões vindas por interfaces celulares, IPv6 ou outras interfaces são recusadas por essa política. Acesso direto por Tailscale, que aparece em documentos antigos do projeto original, não é compatível com essa restrição deste fork.

Os clientes permitidos da rede local também podem acessar os endpoints de status, logs e controle. **Não há autenticação por usuário/senha.** Use uma rede confiável e não exponha a porta por encaminhamento no roteador ou por túneis públicos. O relay remoto opcional vem desativado: se optar por usá-lo, configure sua própria infraestrutura e revise sua autenticação.

### Confira a conexão

Para USB:

```bash
curl --noproxy '*' --fail http://127.0.0.1:8889/__status
curl --proxy http://127.0.0.1:8889 --max-time 30 https://api.ipify.org
```

Para Wi-Fi, substitua o endereço e a porta pelos do iPhone. A segunda consulta mostra o IP de saída usando um serviço externo; não executa rotação.

O app tenta usar a rede celular, mas mantém um fallback de conexão padrão, que pode sair pelo Wi-Fi. Para testar a saída celular sem essa dúvida, use USB, desligue o Wi-Fi **do iPhone**, mantenha os dados móveis ativos e confira o IP. Apenas ver o proxy conectado não prova que a saída está no 5G.

## 5. Configure o botão “Rotate IP”

No app **Atalhos** do iPhone, crie um atalho chamado exatamente **Rotate IP**, com estas ações:

1. Definir **Modo Avião: ativado**.
2. **Esperar 91 segundos**.
3. Definir **Modo Avião: desativado**.

Se você incluiu o arquivo preparado na compilação, o app oferece o compartilhamento desse modelo; importe-o no Atalhos. Também é possível sincronizar o atalho criado no Mac via iCloud. Confira se ele já existe antes de importar outra cópia e evite nomes duplicados.

Ao tocar no botão de rotação, o app abre o Atalhos. O atalho interrompe a rede e tenta reconectar depois da espera. Se cancelar ou interromper o atalho, confira manualmente se o **modo avião ficou desligado** antes de voltar ao proxy.

O botão e a lógica de retorno/estado foram testados em compilação e por testes locais. **O ciclo real de modo avião não foi executado na validação documentada desta versão.** O iOS pode interromper a espera ou pedir interação, e a operadora pode entregar o mesmo IP depois da reconexão. Não há garantia de IP novo, nem rotação automática periódica configurada por este fork.

## 6. Keep alive e logs

**Keep alive in background (audio)** começa ativado em instalações novas e salva sua preferência. Ele usa o mecanismo de áudio silencioso herdado do projeto original para tentar manter o app ativo em segundo plano. Não garante execução permanente: o iOS pode suspender ou encerrar o app, e interrupções de áudio podem afetá-lo. Não é necessário iniciar uma música no Spotify para configurar essa opção.

Os logs ficam em memória, limitados a 300 entradas, com filtros, copiar e limpar. A sanitização cobre formatos comuns de segredos, mas não é uma garantia de anonimização. Hosts e outros dados de diagnóstico podem ser sensíveis; revise tudo antes de compartilhar. O contador de conexões representa conexões de clientes abertas, não usuários nem IPs independentes.

## 7. Problemas comuns

| Sintoma | O que conferir |
|---|---|
| `127.0.0.1:8889` falha, mas o Wi-Fi funciona | Inicie o túnel USB, confira cabo/Confiar, UDID e Bundle Identifier. O endereço USB depende do processo `iproxy` no Mac. |
| Porta 8889 ocupada | O script só reutiliza o túnel do mesmo aparelho e portas. Use outra porta local, por exemplo `./macos/start-usb-proxy.sh SEU_UDID 8890 8888`, se o processo existente for de outro uso. |
| App não responde | Desbloqueie o aparelho, abra o app, confira porta 8888 e permissões. Os logs do launcher ficam em `~/Library/Logs/MobilePhoneProxy/`; revise-os antes de compartilhar. |
| O app deixou de abrir após alguns dias | A assinatura gratuita pode ter expirado. Compile/instale novamente com sua conta Apple. |
| Xcode não reconhece a versão do iOS | Atualize para uma versão compatível do Xcode e conclua a instalação do suporte ao aparelho. |
| IP não mudou | Confirme a saída celular e o término do atalho. Uma reconexão não obriga a operadora a trocar o IP. |
| Cai ao bloquear a tela | Confira o keep alive e interrupções de áudio. O funcionamento contínuo em segundo plano depende do iOS e não foi validado em teste prolongado. |

## 8. Outro iPhone e distribuição

Você pode compilar e instalar no outro iPhone usando o mesmo processo e uma assinatura válida para ele. Para dois iPhones por USB simultaneamente, inicie um túnel com o UDID de cada aparelho e portas locais diferentes, como 8889 e 8890. Cada porta aponta para o aparelho selecionado; isso não garante IPs públicos diferentes entre eles, pois a operadora pode compartilhar endereços.

Um link público para este GitHub permite baixar o **código-fonte**. Ele não instala automaticamente um app não assinado no iPhone.

- **Conta Apple gratuita / Personal Team:** permite testes pessoais com limitações; o provisionamento expira após 7 dias e exige nova instalação. Veja as [regras da conta de desenvolvimento](https://developer.apple.com/help/account/basics/about-your-developer-account).
- **Apple Developer Program:** custa US$ 99 por ano, ou o preço local apresentado pela Apple. Veja o [programa oficial](https://developer.apple.com/programs/).
- **TestFlight:** permite convidar testadores e distribuir por link, após configurar o App Store Connect; testes externos podem exigir revisão da Apple e os builds expiram após 90 dias. Este fork ainda não foi enviado ao TestFlight. Consulte o [TestFlight](https://developer.apple.com/testflight/) e a [visão geral](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

A aceitação pela Apple, inclusive do uso de áudio em segundo plano, não é garantida. O código aberto pode ser usado e modificado conforme a licença MIT; serviço de dados móveis e infraestrutura opcional têm seus próprios custos.

## 9. Testes para desenvolvedores

Na raiz do repositório:

```bash
./scripts/test.sh
cd ios && xcodegen generate && cd ..
xcodebuild -project ios/MobilePhoneProxy.xcodeproj \
  -scheme MobilePhoneProxy -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

Os testes cobrem estado da rotação, sanitização dos logs, admissão local, recuperação/propriedade do túnel USB e estrutura do atalho. Eles **não** contatam um iPhone nem executam modo avião. O build do simulador verifica compilação e empacotamento, não valida a saída pela rede celular. Android, Windows, relay e integrações herdadas não foram revalidados neste fork.
