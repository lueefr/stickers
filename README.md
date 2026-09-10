AI HAS BEEN USED

## Building

```sh
flutter pub get
flutter build apk --release
```

### Android toolchain

The Flutter Gradle plugin refuses to build below hard minimums — as of Flutter
3.50 the floors are Gradle 9.1.0, AGP 9.0.1 and Kotlin 2.3.20 — so the Android
side is pinned to:

| Where | What | Version |
| --- | --- | --- |
| `android/gradle/wrapper/gradle-wrapper.properties` | Gradle | 9.1.0 |
| `android/settings.gradle` | Android Gradle Plugin | 9.0.1 |
| `android/settings.gradle` | Kotlin Gradle plugin | 2.4.0 |

Gradle 9.1.0 is the minimum AGP 9.0.1 supports and Kotlin 2.4.0 fully supports
Gradle 7.6.3–9.5.0 and AGP 8.5.2–9.1.0. AGP 9 requires the compatibility flags
in `android/gradle.properties`:

```properties
android.newDsl=false
android.builtInKotlin=false
```

Those flags keep the legacy `kotlin-android` plugin working until all
transitive plugins migrate to built-in Kotlin. With them, the build has zero
warnings about Gradle/AGP/Kotlin versions, Java 8 obsolescence, or SDK XML v4.

`python3 tool/check_android_versions.py` re-checks the three files against the
thresholds the Flutter tool enforces (plus the signing-config guard below).

### Atualizações pelo GitHub (APK de depuração)

O app consulta a versão estável mais recente em
[`lueefr/stickers/releases`](https://github.com/lueefr/stickers/releases) ao
iniciar (no máximo uma vez a cada 12 horas). Também é possível verificar
manualmente em **Configurações → Verificar atualizações**. Quando existe uma
versão mais nova, o botão de atualização abre diretamente o APK anexado à
GitHub Release no navegador; o Android pede a confirmação da instalação.

O workflow `.github/workflows/debug-apk-release.yml`:

- testa e compila o APK de depuração em pull requests;
- após um push para `main` (ou execução manual), cria a Release
  `v<versão>+<build>` se ela ainda não existir;
- anexa o APK universal e seu SHA-256 à Release.

Para publicar a atualização seguinte, incremente `version:` em `pubspec.yaml`
antes de enviar as mudanças para `main`. O endpoint `releases/latest` ignora
rascunhos e pré-lançamentos, portanto somente Releases estáveis são oferecidas
pelo app.

Os APKs de depuração do workflow usam a chave estável
`android/app/debug-signing.p12`. Ela é intencionalmente pública e serve **apenas
para testes**, nunca para uma distribuição de produção. Um APK debug instalado
anteriormente e assinado pela chave de outra máquina não pode ser atualizado
por este workflow. Nesse primeiro uso, exporte os pacotes, desinstale o APK
antigo e instale o APK da Release; as atualizações seguintes serão instaladas
normalmente por cima dele.

### Release signing (optional)

`android/key.properties` is gitignored, so a fresh checkout builds an *unsigned*
release APK and just prints a warning. To produce a signed, publishable build,
create `android/key.properties` (the folder that also contains `app/build.gradle`):

```properties
storePassword=<keystore password>
keyPassword=<key password>
keyAlias=<key alias>
storeFile=<path to the .jks/.keystore>
```

`storeFile` may be absolute or relative to `android/`.

### Google Fonts search (optional)

Browsing/downloading Google Fonts inside the app requires a free
[Google Fonts Developer API key](https://developers.google.com/fonts/docs/developer_api).
Pass it at build time — without it the app still builds and runs, only the
font list download is disabled (a previously cached list keeps working):

```sh
flutter build apk --release --dart-define=GOOGLE_FONTS_API_KEY=<your-key>
```

`build_all.cmd` (Windows) and `build_all.sh` (Linux/macOS) build the split-per-abi
APKs, the combined APK and the app bundle, and pick the key up from a
`GOOGLE_FONTS_API_KEY` environment variable automatically:

```sh
GOOGLE_FONTS_API_KEY=<your-key> ./build_all.sh   # Linux/macOS
set GOOGLE_FONTS_API_KEY=<your-key> && build_all.cmd   # Windows
```

### Troubleshooting

`Error when reading 'lib/src/api_keys.dart'` or `'ImageSource' is imported from
both ...` means the checkout predates commit `1c7f0bf`, where the API key moved to
a `--dart-define`. Update the checkout (or re-download it) and rebuild; no file
has to be created by hand.

### Exportar e restaurar pacotes

- Na lista de pacotes, pressione e segure um pacote (ou toque no botão de seleção).
- Marque os pacotes desejados; use “Select all” para selecionar todos.
- Toque em exportar/compartilhar e salve o arquivo **`sticker_pack.zip`** usando o menu do sistema.
- Para restaurar, toque no botão de importar (ícone de arquivo com seta) e selecione o ZIP. Todos os pacotes contidos nele serão adicionados ao aplicativo, sem substituir os existentes.

O backup preserva nomes, autores, emojis, ícones e figurinhas estáticas ou animadas. ZIPs antigos com um único `pack.json` também continuam sendo aceitos. O nome do arquivo pode ser alterado sem impedir a importação.

O novo formato contém um `packs.json` (`version: 1`, lista `packs`) e uma pasta `pack_N` com a mídia de cada pacote. Os caminhos no manifesto são relativos à raiz do ZIP.
