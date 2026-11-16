# Scene Suite — plugins para o Scene do Firecast

Seis plugins **independentes** que ampliam o tabuleiro (Scene) do Firecast,
pensados para Pathfinder 1e e Final Fantasy d20, mas úteis em qualquer sistema
d20. Instale só os que quiser: cada um tem seu próprio `module.xml`/ID e não
depende dos outros.

| Plugin (pasta) | O que faz | Quem precisa ter instalado para **ver** |
|---|---|---|
| `SceneSuite_Conditions` — **Condições** | Ícones de condição sobre o token, com duração em rodadas, avanço de rodada e lista de PF1e, magias comuns e status do FFd20 | Só quem aplica (o desenho fica salvo no token) |
| `SceneSuite_Auras` — **Auras** | Até 3 auras por token: emanação, quadrado, cone (90°) ou linha, medidas em ft/m/quadrados | Só quem aplica |
| `SceneSuite_Reach` — **Alcance** | Quadrados ameaçados a partir do alcance digitado, arma de haste e exceção de 10 ft, bem translúcido | Só quem aplica |
| `SceneSuite_SpellAreas` — **Áreas de Magia** | Áreas de efeito digitando o tamanho em ft ou m (explosão, emanação, cilindro, cone, linha, quadrado) | Só quem cria |
| `SceneSuite_Weather` — **Clima** | Chuva, tempestade, neve, nevasca, névoa, vendaval, areia, cinzas, folhas, noite, submerso, vaga-lumes | **Todos** que quiserem ver o efeito |
| `SceneSuite_SpellFX` — **Animações de Magia** | 32 animações (bola de fogo, relâmpago, mísseis mágicos, raios, curas, explosões de luz...) | **Todos** que quiserem ver a animação |

Os quatro primeiros gravam o desenho como *operações gráficas* no próprio
token/desenho do tabuleiro. O Firecast sincroniza isso e desenha para todo
mundo, mesmo para quem não instalou o plugin. Clima e animações são desenhados
na tela de cada um, em tempo real. Por isso esses dois só aparecem para quem
tem o plugin, e por isso também não bloqueiam cliques nos tokens.

Cada plugin tem **seu próprio botão** na barra de ferramentas do Scene
(Condições, Auras, Alcance, Áreas de Magia, Clima, Animações de Magia). Clicar
no botão ativa a ferramenta principal; passar o mouse mostra só as opções
daquele plugin.

---

## Instalação

Você precisa do SDK do Firecast (ferramenta `rdk`), disponível em
<https://firecast.app/para-programadores/>.

**Um plugin:** abra o prompt de comando dentro da pasta do plugin (por
exemplo `plugins\SceneSuite_Conditions`) e rode:

```
rdk p      (apenas na primeira vez: prepara a pasta e copia o SDK)
rdk i      (compila e instala no Firecast aberto)
```

O `rdk c` gera o `.rpk` em `output\`. É esse arquivo que você distribui para
os jogadores, que só precisam dar dois cliques nele.

**Vários plugins:** rode `instalar_todos.bat` na raiz do repositório. Ele faz
`rdk p` + `rdk i` em cada pasta de `plugins\`. Para instalar só alguns,
apague (ou mova) as pastas que você não quer antes de rodar.

> Os IDs são `SceneSuite.Conditions`, `SceneSuite.Auras`, `SceneSuite.Reach`,
> `SceneSuite.SpellAreas`, `SceneSuite.Weather` e `SceneSuite.SpellFX`. Se for
> publicar com outro nome, troque o `<id>` no `module.xml` **antes** da
> primeira publicação. Depois disso, não mude mais.

---

## 1. Condições

- **Condições** (ferramenta): clique num token. Se já houver tokens
  selecionados, o painel abre direto para todos eles. O painel tem as
  condições de PF1e (com os nomes da tradução brasileira e o original em
  inglês), magias e efeitos comuns (Velocidade, Bênção, Armadura Arcana...) e
  os status do FFd20 (Berserk, Doom, Protect, Shell, Reflect, Regen...). Dá
  para filtrar por grupo.
- **Duração**: ao lado de cada condição há um número e a unidade —
  **rodadas, minutos ou horas** (1 minuto = 10 rodadas, 1 hora = 600). Vazio =
  indefinida. Para dar a mesma duração a todas as marcadas, use "Duração p/
  marcadas". No token, o selo mostra `3` (rodadas), `2m` ou `1h`, e os nomes
  mostram a duração restante na unidade escolhida ("Velocidade (1,9 min)").
  O avanço de rodada desconta de tudo, inclusive das durações em minutos/horas.
- **Condição personalizada**: nome, cor e duração livres.
- **Só o mestre vê**: as condições novas ficam visíveis apenas para o mestre.
- **Avançar rodada** (mestre): diminui todas as durações e remove as que
  acabaram. **Desfazer** volta o último avanço.
- **Configurar exibição** (mestre): ícones acima, abaixo ou dos lados do
  token, em 4 tamanhos. Os nomes podem aparecer ao passar o mouse, sempre, ou
  nunca.

No token, cada condição vira um ícone circular colorido por tipo (mental,
físico, movimento, sentidos, morte, benefício, magia, elemental). A duração
aparece num selo no canto do ícone.

## 2. Auras

Clique num token (ou selecione vários) com a ferramenta **Auras**. Cada token
tem 3 auras independentes. Em cada uma você escolhe:

- **Forma**: emanação (raio ao redor do token), quadrado, cone de 90° ou
  linha (com largura).
- **Alcance** em `ft`, `m` ou `q` (quadrados). Ex.: `10 ft`, `3 m`, `2 q`.
- **Cálculo**:
  - *Quadrados do grid*: marca exatamente os quadrados afetados. A distância
    é medida a partir da borda do token, com diagonais 5-10-5 do Pathfinder
    (ou a regra configurada no tabuleiro, se preferir).
  - *Forma suave*: desenha o círculo, cone ou linha geométrico.
- **Direção** (cone/linha) e a opção de **seguir a rotação do token**.
- Cor, intensidade do preenchimento, rótulo, e se aparece sempre ou só ao
  passar o mouse. Também dá para deixar visível só para o mestre.

Quando o token muda de tamanho, sai do grid ou gira, o cliente do mestre
redesenha a aura sozinho. O botão **Redesenhar todas** resolve depois de você
mudar o tamanho das células do grid.

## 3. Alcance

A ferramenta **Alcance** mostra os quadrados ameaçados em corpo a corpo:

- **Alcance natural** digitado em `ft`, `m` ou `q`. O painel lembra a tabela
  do Pathfinder: Médio 5 ft, Grande 10/5, Enorme 15/10, Imenso 20/15,
  Colossal 30/20 (alto/longo).
- **Arma de haste**: dobra o alcance e deixa de ameaçar os quadrados próximos
  (até o alcance natural). Há uma opção para continuar ameaçando adjacentes.
- **Exceção de 10 ft**: com alcance de 10 ft, alcança 2 quadrados na diagonal.
- **Cor** escolhida por você em cada token.

**Para não poluir o tabuleiro**, o alcance é um preenchimento bem translúcido
(6–10%) com contorno tracejado. Por padrão ele só aparece ao passar o mouse
ou selecionar o token. O mestre muda isso para toda a mesa com **Modo de
exibição**: *ao passar o mouse* (recomendado), *sempre* (ainda mais
translúcido) ou *ocultar todos*. Selecionando vários tokens antes de abrir o
painel, o mesmo alcance é aplicado em todos.

## 4. Áreas de Magia

Selecione a ferramenta **Área de magia**. Um painel abre no canto da tela:

1. Escolha uma magia pronta (Bola de Fogo, Mãos Flamejantes, Relâmpago, Cone
   de Frio, Coluna de Chamas, Canalizar Energia, Teia, Graxa, Silêncio...) ou
   **Personalizada**.
2. Digite o tamanho em **ft, m ou quadrados**: `20 ft`, `6 m`, `4 q`. O plugin
   lê a configuração do tabuleiro (tamanho da célula e unidade) e converte.
   Com o padrão do Firecast (célula de 1,5 m), `6 m` = `20 ft` = 4 quadrados.
3. Clique no tabuleiro:
   - explosão, emanação e cilindro: clique na interseção de origem;
   - cone, linha e quadrado: clique na origem, mire com o mouse e clique de
     novo.

   Antes de confirmar, você vê uma prévia só sua. Botão direito ou ESC cancela.
   **Shift** solta a origem do grid. **Ctrl + clique** sobre uma área a
   remove.

No modo *quadrados do grid*, a origem fica numa interseção, as diagonais
seguem 5-10-5 e o cone tem 90°, como em Pathfinder. Por exemplo, uma Bola de
Fogo de 20 ft marca 44 quadrados. Cada área vira um desenho normal do Scene,
com rótulo ("Bola de Fogo · 20 ft"), e pode ser selecionada e apagada como
qualquer desenho. Com o plugin de Animações instalado, a opção **Tocar
animação** dispara o efeito correspondente.

## 5. Clima

O mestre usa **Clima: escolher efeito** e define o efeito, a intensidade, o
vento e a opacidade (20% a 100%). O clima fica salvo no Scene e aparece para
todos que têm o plugin. O desenho é feito sobre a tela, então não intercepta
cliques: tokens e ferramentas funcionam normalmente. Qualquer pessoa pode usar
**ligar/desligar só para mim** (desempenho ou preferência).

## 6. Animações de Magia

Ferramenta **Animações de magia**: escolha o efeito no painel e:

- **projéteis, raios, cones, linhas**: selecione o conjurador antes e clique
  no alvo. Sem seleção, clique primeiro na origem e depois no alvo;
- **áreas**: clique no centro;
- **em si mesmo / toque**: clique no token;
- **Relâmpago em Cadeia**: clique nos alvos em sequência e use o botão direito
  (ou ENTER) para disparar.

Clicar num token mira o centro dele. "Quantidade" vale para Mísseis Mágicos,
Raio Ardente e Projéteis de Gelo. "Tamanho" muda o raio ou o comprimento.

**Efeitos incluídos.** Foram escolhidas as magias de ataque e área mais usadas
em PF1e (livro básico e APG):

- Bola de Fogo; Relâmpago; Mísseis Mágicos; Raio Ardente; Raio de Gelo;
  Projéteis de Gelo.
- Cone de Frio; Mãos Flamejantes; Spray de Cores; Flecha Ácida; Toque
  Chocante.
- Curar Ferimentos; Canalizar Energia (positiva e negativa); Luz Cauterizante;
  Explosão de Luz; Coluna de Chamas.
- Convocar Relâmpagos; Relâmpago em Cadeia; Desintegrar; Encantamento
  (Imobilizar/Enfeitiçar); Porta Dimensional.
- Explosão Sonora; Chuva de Meteoros; Tempestade de Gelo; Pó Reluzente; Nuvem
  Venenosa; Escuridão.
- Genéricos: Golpe, Flecha, Bênção/Proteção, Energia Negativa.

No FFd20, use Bola de Fogo/Mãos Flamejantes para *Fire*, Raio de Gelo/Projéteis
de Gelo/Cone de Frio para *Blizzard*, Relâmpago/Convocar Relâmpagos para
*Thunder*, Curar Ferimentos para *Cure* e Explosão de Luz para *Holy*.

---

## Limitações e o que conferir no primeiro uso

- Os plugins foram escritos contra a documentação e o código-fonte do SDK 3
  e testados num SDK **simulado** (veja abaixo), não num Firecast real. Faça
  um teste rápido numa mesa vazia antes da sessão. Os plugins não escrevem
  nada no chat; se algo der errado, o erro aparece em `/console`.
- Quem não é mestre só altera condições, auras e alcance dos **próprios**
  tokens.
- Em grid hexagonal, auras e áreas usam a forma suave (a regra 5-10-5 só vale
  para grid quadrado).
- Clima e animações dependem de cada pessoa ter o plugin. Os outros quatro
  aparecem para todos.

## Para desenvolvedores

```
common/fsCommon.lua        biblioteca compartilhada (unidades, 5-10-5, geometria, canvas)
plugins/<Plugin>/          um projeto de plugin por pasta (module.xml, .lua, .lfm, images/)
tools/build.py             copia a lib comum para cada plugin, gera os dados/ícones das
                           condições e o formulário, valida XML e sintaxe Lua
tools/test_harness.py      roda os 6 plugins contra um SDK do Firecast simulado
tools/test_scenarios.lua   cenários do teste (formulários, cliques, quadros de animação)
tools/render_preview.py    gera uma imagem de como condições/auras/alcance/áreas ficam
tools/render_fx_frames.py  gera quadros das animações e do clima
tools/conditions_def.py    lista de condições (edite aqui para adicionar/mudar)
assets/icons/              SVGs do game-icons.net usados (CC BY 3.0)
```

`fsCommon.lua` é **copiado** para cada plugin, porque cada plugin roda numa
sandbox isolada no Firecast. Edite sempre `common/fsCommon.lua` e rode
`python3 tools/build.py`. Dependências do build: `pip install cairosvg pillow
svgelements lupa`.

## Créditos

Ícones: [game-icons.net](https://game-icons.net), licença CC BY 3.0. Detalhes
em [CREDITS.md](CREDITS.md).
