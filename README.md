# Docly

Docly é um editor de documentos com páginas em formato de folha, texto formatável e ferramentas visuais. O projeto é desenvolvido em Lua com [LÖVE (LÖVE2D) 11.5](https://love2d.org/) e pode ser executado no Windows, macOS e Linux.

## Funcionalidades

- Criação e gerenciamento de documentos.
- Páginas em formato de folha, com navegação entre elas.
- Texto UTF-8 com tamanhos de fonte e marca-texto.
- Seleção, copiar, colar e formatação básica.
- Desenho à mão livre e borracha.
- Formas retangulares, elípticas e linhas.
- Caixas de texto, imagens e anexos.
- Salvamento automático local a cada intervalo de execução.
- Exportação para `.docly` e `.txt`.
- Importação de arquivos `.docly`.
- Arrastar arquivos para a janela.

## Arquitetura

### Fluxo geral

1. [`main.lua`](./main.lua) define os callbacks do LÖVE e um loop personalizado que redesenha apenas após eventos ou durante uma animação.
2. [`src/core/app.lua`](./src/core/app.lua) recebe os eventos e coordena a tela inicial, o editor, a barra lateral e o salvamento periódico.
3. [`src/editor/editor.lua`](./src/editor/editor.lua) concentra o estado e a interação do documento aberto.
4. [`src/editor/document_manager.lua`](./src/editor/document_manager.lua) cria documentos, controla páginas e lê ou grava os dados.
5. Os módulos de interface desenham a tela e transformam entradas do mouse em ações.

### Estrutura do projeto

```text
.
├── main.lua                 # Pontos de entrada e loop principal do LÖVE
├── conf.lua                 # Configuração da janela e da versão do LÖVE
├── docly.love              # Pacote executável do jogo/aplicativo
├── assets/
│   └── fonts/              # Fonte opcional; o projeto usa fonte padrão em fallback
├── src/
│   ├── core/
│   │   ├── app.lua         # Coordenador geral e distribuição de eventos
│   │   ├── fonts.lua       # Carregamento e cache das fontes
│   │   └── file_dialog.lua # Seletores nativos de arquivo por sistema operacional
│   ├── editor/
│   │   ├── editor.lua      # Editor visual, objetos, ferramentas e eventos
│   │   ├── document_manager.lua
│   │   │                   # Documentos, páginas, persistência e exportação
│   │   ├── text_edit.lua   # Modelo UTF-8 do texto e estilos por caractere
│   │   └── text_layout.lua # Quebra de linhas, runs e cache do layout
│   ├── interface/
│   │   ├── homepage.lua    # Tela inicial e documentos recentes
│   │   ├── sidebar.lua     # Barra de ferramentas
│   │   ├── toolbar.lua     # Arquivo reservado para a interface da barra
│   │   └── workspace.lua   # Arquivo reservado para o workspace
│   └── tools/
│       └── draw.lua        # Rabiscos e recorte geométrico da borracha
├── templates/              # Arquivos futuros ou modelos do projeto
└── plugins/                # Espaço reservado para extensões
```

## Como os dados são armazenados

O estado local é gravado pelo `DocumentManager` no diretório de dados do LÖVE, no arquivo `documents.docly`. Os dados são escritos em JSON com formato próprio:

```json
{
  "format": "docly",
  "version": 1,
  "documents": []
}
```

Cada documento contém:

- `id`
- `title`
- `currentPage`
- `pages`

Cada página pode conter:

- `content`: texto UTF-8 da página.
- `cursor` e `anchor`: posição e seleção do texto.
- `sizes`: tamanho da fonte por caractere.
- `marks`: marcações de texto por caractere.
- `drawings`: coordenadas dos rabiscos.
- `objects`: imagens, anexos, formas e caixas de texto.

A classe `DocumentManager` trata os objetos da página sem converter imagens para o JSON: ela remove temporariamente os dados de runtime e grava imagens em Base64 no campo `imageData`. Imagens são reconstruídas ao carregar o arquivo.

### Exportação

- `.docly`: preserva documentos, páginas, estilos, marcações, objetos e imagens.
- `.txt`: gera título e conteúdo textual. Caixas de texto e anexos são incluídos em uma representação simples.

## Modificando o projeto

### Alterar o comportamento geral

Use [`src/core/app.lua`](./src/core/app.lua) para:

- mudar o que ocorre ao abrir ou fechar o aplicativo;
- controlar o estado do documento atual;
- adicionar handlers globais;
- ajustar a frequência de salvamento.

Os callbacks de [`main.lua`](./main.lua) devem continuar chamando o `App`; normalmente não é necessário alterá-los.

### Modificar a tela inicial

Edite [`src/interface/homepage.lua`](./src/interface/homepage.lua) para adicionar cards, botões ou uma nova forma de criar/abrir documentos.

Se um novo documento precisar de dados adicionais, inicialize-os em `Documents.create()` e ajuste `plainDocument()` e `restoreDocument()` em [`src/editor/document_manager.lua`](./src/editor/document_manager.lua).

### Adicionar ou alterar ferramentas

As ferramentas disponíveis são declaradas em [`src/interface/sidebar.lua`](./src/interface/sidebar.lua):

```lua
local tools = {
    "draw",
    "eraser",
    "image",
    "shape",
    "text",
    "highlight",
    "attachment"
}
```

Para uma ferramenta nova:

1. Adicione o identificador em `tools` e em `implemented`.
2. Inclua o ícone em `drawIcon`.
3. Defina cursor e controles no `Editor`.
4. Trate `activeTool` em `Editor.mousepressed`, `mousemoved`, `mousereleased` e nos métodos de teclado necessários.
5. Persista os novos objetos em `plainDocument()` e restaure-os em `restoreDocument()` caso sejam parte do documento.

Os efeitos visuais da ferramenta podem ficar em um novo módulo dentro de [`src/tools/`](./src/tools/).

### Alterar texto e formatação

- [`src/editor/text_edit.lua`](./src/editor/text_edit.lua): operações sobre o texto, cursor, seleção e estilos por caractere.
- [`src/editor/text_layout.lua`](./src/editor/text_layout.lua): quebra automática de linhas, largura e cache.
- [`src/editor/editor.lua`](./src/editor/editor.lua): barra de formatação, inserção pelo teclado e desenho do texto.

O cache de layout é invalidado pela versão `page.rev`. Toda alteração no conteúdo ou no estilo deve chamar a função apropriada de `TextEdit` para incrementar essa versão.

### Trocar a fonte

Coloque uma fonte em [`assets/fonts/`](./assets/fonts/) e atualize `FONT_PATH` em [`src/core/fonts.lua`](./src/core/fonts.lua). Se o arquivo não estiver disponível ou não puder ser carregado, o LÖVE usa uma fonte padrão.

### Alterar a janela

Edite [`conf.lua`](./conf.lua):

```lua
function love.conf(t)
    t.identity = "Docly"
    t.version = "11.5"
    t.window.title = "Docly"
    t.window.width = 1280
    t.window.height = 800
    t.window.resizable = true
end
```

### Alterar a persistência

As constantes e operações principais estão em [`src/editor/document_manager.lua`](./src/editor/document_manager.lua). Use `markDirty()` depois de mudanças que devam ser persistidas automaticamente.

Ao alterar o formato JSON, mantenha compatibilidade com arquivos existentes ou implemente migração em `loadAppData()`. O formato atual usa `format = "docly"` e `version = 1`.

## Baixar

Baixe gratis a ultima versão em releases
Consulte a pagina [`RELEASES`](./RELEASES).

## Licença

O projeto é distribuído sob a licença GNU General Public License. Consulte o arquivo [`LICENSE`](./LICENSE).