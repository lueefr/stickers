# APK e inicialização — auditoria e validação

## Diagnóstico

Base analisada: `934331a3` (`1.5.9+27`). O release GitHub `v1.5.9+27`
publicava **um APK debug universal de 179.425.492 bytes (171,11 MiB)**.
Não é uma medida do tamanho inevitável do app: ele inclui o runtime de
**desenvolvimento/JIT**, sem as otimizações de distribuição e com três ABIs.

A abertura também disparava a leitura/cópia/registro de todas as fontes e
compilação de três shaders usados somente no editor. Mesmo sem `await`, esse
trabalho concorre por disco, platform thread, engine e CPU com o primeiro frame.
A leitura de PackageInfo estava na barreira anterior ao `runApp`.

## Alterações

| Área | Implementação | Preservado / ressalva |
|---|---|---|
| Flutter/Android | Release/AOT, R8, resource shrinking otimizado, icon tree shaking padrão | Não se distribui mais debug/JIT; depuração continua disponível localmente |
| Distribuição | APKs arm64-v8a, armeabi-v7a e x86_64; universal de fallback | Nenhuma arquitetura existente removida |
| Atualizador | Consulta `Build.SUPPORTED_ABIS`, escolhe split compatível, fallback universal/página | APKs antigos continuam encontrando universal; nunca oferece split incompatível |
| Símbolos | `--split-debug-info`, símbolos Dart e mapping R8 em artifact separado | Mantém capacidade de investigar crashes, sem empacotar símbolos Dart no APK |
| WebP/JNI | Visibilidade hidden do codec estático, ThinLTO e GC de seções não alcançadas | Entradas JNI e campos lidos via JNI protegidos; SIMD, encode/decode e animações mantidos |
| Primeiro frame | Aguarda somente configurações, biblioteca e diretórios necessários | Primeira tela é a biblioteca real, com tema/idioma salvos, não um splash disfarçando loading |
| Fontes | Inicialização única sob demanda, aguardada por editor/gerenciador, com retry | Todas as 11 TTFs, classic do sistema, fontes customizadas/Google e licença mantidas |
| Shaders | Preparação no acesso ao editor, futures deduplicados, carga paralela | HSL e animações mantidos; fallback anterior em falha continua disponível |
| Vídeo Android | Instâncias de conversores lazy; destruir Activity não os instancia | Fluxos de progresso, cancelamento e codificação mantidos |
| Bibliotecas grandes | JSON >= 64 KiB decodificado e convertido em isolate | Todos os metadados e ordem preservados; biblioteca pequena não paga spawn de isolate |
| Compartilhamento | Após primeiro frame, importações serializadas, subscription cancelada no dispose | Evita corrida com Navigator ainda não montado e quick-add concorrente |
| Dependências | Gerador de ícones movido para dev_dependencies; Flutter 3.47.4 fixado no CI | Plugins de features mantidos; não se atribui economia de bytes sem medida |

### Áreas inspecionadas e deliberadamente mantidas

- Lista/grid de pacotes e thumbnails: já usam builders, cache de decode limitado
  por resolução e RepaintBoundary; `OpenContainer` e WebP animado permanecem.
- Crop, editor, drawing/text/image layers e vídeo: decodificação/transformações
  caras são solicitadas pela ação do usuário, não pela home. Não se reduziu
  resolução de exportação, qualidade de sticker, FPS ou duração de animação.
- Backup/importação/exportação, WhatsApp e compartilhamento: plugins mantidos;
  shrinking depende dos consumer rules e de referências reais, não de excluir
  bibliotecas manualmente.
- 40 traduções ARB, todos os glifos das fontes e os três shaders: não foram
  eliminados para obter economia artificial. Subsetting de fontes por alfabeto
  quebraria textos do usuário e idiomas suportados.
- Settings, update, licenças e fontes Google: nada removido, inclusive a chave
  Google Fonts continua passando por `--dart-define` quando configurada no CI.
- Cache de imagem: limite anterior preservado; reduzir cache às cegas pode
  trocar RAM por mais decodes/jank. Requer perfil em aparelho representativo.
- Não se comprimiu manualmente `.so` nem se habilitou extração forçada apenas
  para reduzir o ZIP: isso pode aumentar instalação/disco e piorar mmap/startup.

## Assinatura e segurança

Builds comunitários do CI são **release** (não debuggable), mas usam a chave de
assinatura debug **pública e estável que o projeto já distribuía**. A opção é
explícita: `ORG_GRADLE_PROJECT_communitySigning=true`. Isso permite atualizar
APKs antigos sem desinstalar/apagar pacotes. **Não é uma assinatura privada de
produção.** Com `android/key.properties`, a assinatura privada tem prioridade.
Sem ambas as opções, o release local continua não assinado.

## CI

Arquivo: `.github/workflows/debug-apk-release.yml` (nome histórico do arquivo).

1. Python tooling tests, Flutter analyze e todos os Flutter tests.
2. Compila release por ABI + universal com a mesma versão/chave.
3. `tool/apk_report.py` mede bytes reais no ZIP, discrimina libs por ABI,
   assets/Dex/recursos, lista os maiores arquivos e rejeita payload debug,
   ausência de AOT/fontes/shaders/licença ou símbolos JNI exportados.
4. Android 35 x86_64: compara seis aberturas do debug histórico com seis do
   release, atualizando por cima da instalação existente (testa a assinatura).
   Mantém animações ligadas e captura am start, logcat e screenshots. Abre
   Settings → Fonts manager e exige que Lobster apareça após registro nativo.
5. Publicação/version bump **somente em main, após build e smoke passarem**.
   Push nesta branch apenas valida e disponibiliza artifacts; não cria release.

Artifacts:
- `stickers-<versão>-release`: quatro APKs e SHA-256.
- `performance-diagnostics-<run>`: relatório JSON, analyze/build log, símbolos,
  mapping R8, pubspec.lock resolvido e versão exata do Flutter.
- `startup-evidence-<run>`: JSON, logcat, informações do dispositivo e screenshots.

## Medição honesta de startup

`home_ready_ms` cobre a construção da Activity até **ambos**: dados de startup
prontos/primeiro frame Flutter construído e callback nativo de Flutter visível.
`am_total_ms` é a medida separada de `am start -W`. Nenhuma delas afirma medir
o tempo entre o dedo no launcher e todos os thumbnails terminarem de decodificar.

O primeiro lançamento inclui inicialização de instalação/atualização; as cinco reinicializações
seguintes têm processo frio, mas caches de disco/sistema quentes. CI usa emulador,
não celular. Não há limite arbitrário de 100 ms nem garantia de “instantâneo”.
Uma home vazia também não representa uma biblioteca com milhares de stickers.

Para medir no celular conectado (ADB habilitado):

```sh
python3 tool/startup_smoke.py /caminho/stickers-<versão>-arm64-v8a-release.apk
```

**Atenção:** instala/atualiza e força o encerramento do app seis vezes, sem limpar
os dados. Use um aparelho de teste e faça backup antes. Nunca compare debug de
um aparelho com release de outro como se fossem um benchmark controlado.

Para profile detalhado: `flutter run --profile --trace-startup`; usar DevTools/
Perfetto com biblioteca vazia e grande, cold/warm start, aparelho simples e atual,
com tema claro/escuro, idioma escolhido e sem rede.

## Checklist funcional no aparelho antes de produção

O smoke automatizado não substitui teste completo de todas as features:
- Atualizar por cima do debug antigo e conferir pacotes, settings e fontes.
- Criar, editar, duplicar, apagar e exportar/importar pacotes (inclusive grandes).
- Compartilhar foto/ZIP com app fechado e aberto; quick mode ligado/desligado.
- Texto com cada fonte bundled, customizada e Google; cores HSL/eyedropper.
- GIF/vídeo animado: trim, rotação, crop/stretch, overlay, encode e cancelamento.
- Enviar estáticos/animados ao WhatsApp; seleção múltipla e atualização de sticker.
- Navegar/rolar listas e editor observando animações e frame timings.

## Resultados

A referência histórica debug acima foi obtida da API de releases do GitHub.
Primeiro run completo: [34712435788](https://github.com/lueefr/stickers/actions/runs/34712435788)
(commit `5eef149`, todos os jobs passaram):

| APK | Bytes | MiB | Redução sobre debug universal |
|---|---:|---:|---:|
| ARM64 | 22.141.582 | 21,12 | 87,66% |
| ARM 32 bits | 19.466.028 | 18,56 | 89,15% |
| x86_64 | 23.754.271 | 22,65 | 86,76% |
| Universal | 60.274.971 | 57,48 | 66,41% |

O split compara download de **uma** arquitetura com o antigo universal. A linha
universal permite comparar a mesma cobertura de arquiteturas. Ambos os efeitos
(release e divisão por ABI) contribuem, não se atribui tudo ao código Dart.

Nesse run, primeiro lançamento no emulador: 2.361 ms; mediana de processo frio:
4.303 ms; máximo: 5.633 ms. Isso valida funcionamento, **não** demonstra startup
instantâneo ou ganho sobre o app antigo. O smoke estendido adiciona comparação
com o debug no mesmo emulador e discrimina fases Dart para investigar a diferença.

Os tamanhos e tempos finais são os do run/JSON final; não são estimativas pela
soma de arquivos fonte. O engine Flutter e as bibliotecas dos plugins continuam
sendo um piso real de tamanho e inicialização.
