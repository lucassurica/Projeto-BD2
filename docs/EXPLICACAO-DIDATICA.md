# Explicação didática do projeto

Este documento explica **por que** cada coisa do código foi feita. Ele serve para o grupo estudar, revisar e responder às perguntas do professor na apresentação. Os comentários `--` no SQL dizem o "o quê" em uma linha; aqui está o raciocínio completo.

Sempre que possível, a explicação aponta o conceito da aula que sustenta a decisão:
- Aula 02 e 04: índices e B+-tree.
- Aula 03: índice hash.
- Aula 05: índices no PostgreSQL.
- Aula 12: catálogo e estatísticas.
- Aula 13: PL/pgSQL e triggers.
- Aula 14: visões.
- Aula 15: transações.

Também aponta o que o professor pediu na consultoria.

---

## Sumário

1. [Mapa: o que o professor pediu e onde está](#1-mapa-o-que-o-professor-pediu-e-onde-está)
2. [A ordem do trabalho](#2-a-ordem-do-trabalho)
3. [Design físico (01_ddl.sql)](#3-design-físico-01_ddlsql)
4. [Triggers (02_ddl_estendida.sql, parte 1)](#4-triggers)
5. [Functions de inserção e transações (02, parte 2)](#5-functions-de-inserção-e-transações)
6. [Visões (02, parte 3)](#6-visões)
7. [Povoamento (03_povoamento.sql)](#7-povoamento)
8. [Consultas (04_consultas.sql)](#8-consultas)
9. [Índices (05_indices.sql)](#9-índices)
10. [O que mudou em relação ao que o grupo já tinha](#10-o-que-mudou-em-relação-ao-que-o-grupo-já-tinha)
11. [O que decidimos NÃO fazer, e por quê](#11-o-que-decidimos-não-fazer-e-por-quê)
12. [Perguntas que o professor pode fazer](#12-perguntas-que-o-professor-pode-fazer)
13. [Glossário rápido](#13-glossário-rápido)

---

## 1. Mapa: o que o professor pediu e onde está

| Pedido (enunciado ou consultoria) | Onde está |
|---|---|
| Entre 1.000 e 10.000 tuplas por tabela | `03_povoamento.sql`. O `dev/verificacoes.sql` confere as 20 tabelas. |
| Distribuição de dados realista, não uniforme | `03_povoamento.sql`, função `pop_concentrado` (seção 7). |
| Identificadores artificiais, UNIQUE e NOT NULL criteriosos | `01_ddl.sql` (seção 3). |
| PK numérica, nunca string | Todas as PKs são inteiras (seção 3.1). |
| Chaves compostas colapsadas, no máximo 2 ou 3 atributos | Nenhuma PK passa de 2 atributos (seção 3.2). |
| ENUMs bem definidos | 3 ENUMs (seção 3.4). |
| Políticas ON DELETE e ON UPDATE em toda FK | Todas comentadas no `01_ddl.sql` (seção 3.5). |
| Até 5 visões, justificando cada uma: por que materializada, por que virtual | `02`, parte 3 (seção 6). |
| Até 5 índices, considerando o overhead de inserção | `05_indices.sql` e `medicoes/` (seção 9). |
| Medir os índices com e sem, repetindo | `medicoes/medir_indices.sql` e `resultados.md`. |
| Triggers para todos os atributos derivados e regras | 7 triggers (seção 4). |
| Inserções por functions que validam antes | 11 functions `inserir_*` (seção 5). |
| Functions parametrizadas para as 12 consultas | `04_consultas.sql` (seção 8). |
| Pelo menos uma function polimórfica | Consultas 5 e 12 (seção 8.2). |
| Transações (opcional, mas o professor gostaria) | Carga em transação única, `FOR UPDATE` nas triggers e atomicidade das functions (seção 5.2). |
| Arquivos separados | 5 arquivos `sql/01` a `sql/05`. |
| Decisões comentadas no SQL com `--` | Todos os arquivos. |
| README com o passo a passo | `README.md` |

---

## 2. A ordem do trabalho

O professor insistiu em uma ordem: **design físico, depois povoamento, depois consultas, e só então índices e visões**. A razão:

- O design é a primeira peça do dominó. Um erro nele "vira bola de neve" e se propaga para as consultas e os índices.
- Sem dados, não dá para saber quanto custa uma consulta.
- Sem as consultas, não dá para saber quais índices ajudam. O índice depende do predicado (o `WHERE`) da consulta.

Seguimos essa ordem, e os arquivos são numerados nela.

---

## 3. Design físico (01_ddl.sql)

O modelo relacional do enunciado já estava normalizado. O trabalho aqui foi transformá-lo em um **projeto físico para o PostgreSQL**: escolher tipos, chaves, constraints e políticas de FK.

### 3.1 Por que chaves primárias numéricas

No PostgreSQL, toda PK vira automaticamente um **índice B+-tree**. O professor disse que não quer ver PK em string, por três motivos:

1. **Comparar inteiros é mais barato que comparar strings.** Um inteiro se compara em uma instrução. Uma string se compara caractere por caractere e ainda depende de regras de ordenação de idioma (collation).
2. **A chave fica menor.** Um `INTEGER` ocupa 4 bytes; um nick `VARCHAR(63)` pode passar de 60. Chave menor significa mais entradas por nó da B+-tree, árvore mais baixa e menos acessos a disco (Aulas 02 e 04).
3. **Toda FK que aponta para a tabela carrega a chave.** Com nick como PK, cada comentário, inscrição e participação repetiria o nick. Com `nro_usuario`, repete um número de 8 bytes.

**Como fizemos:** cada tabela cuja chave natural era string, ou composta de muitos atributos, ganhou uma coluna `GENERATED ALWAYS AS IDENTITY`. É um contador que o próprio banco preenche.

- `ALWAYS`, e não `BY DEFAULT`, faz o banco **rejeitar** quem tentar informar o valor na mão. Isso evita conflito com o contador.
- **A chave natural antiga não some.** Ela vira `UNIQUE + NOT NULL`. O professor lembrou que a chave artificial precisa **preservar a unicidade** da original; sem o UNIQUE, poderiam existir dois usuários com o mesmo nick.

**Qual tipo inteiro para cada chave.** O professor perguntou isso na consultoria: "vou mudar para INTEGER, BIGINT, UUID?". Escolhemos pela cardinalidade esperada, mantendo o tamanho da chave proporcional ao volume real:

| Tabela | Chave | Tipo | Por quê |
|---|---|---|---|
| conversao | id | SMALLINT (2 bytes) | Existem menos de 200 moedas. |
| pais | ddi | SMALLINT | O DDI já é numérico e natural, com no máximo 4 dígitos. Não precisou de chave artificial. |
| empresa, plataforma | nro_* | INTEGER (4 bytes) | Milhares, talvez milhões. |
| canal | id_canal | INTEGER | Muito menos canais que vídeos. Economiza 4 bytes em cada FK para canal. |
| usuario | nro_usuario | BIGINT (8 bytes) | Plataformas reais passam de 2 bilhões de contas, o limite do INTEGER. |
| video, comentario, doacao | id_* | BIGINT | São as tabelas que crescem sem parar. |

**Por que não UUID:** o UUID ocupa 16 bytes e é aleatório. Inserções caem em pontos espalhados da B+-tree e causam muitos *splits*, divisões de nó (Aula 04). Ele vale a pena quando vários servidores geram ids sem se coordenar. Aqui o sistema é **monolítico e centralizado**, como o professor lembrou, então um contador sequencial basta e é mais eficiente.

### 3.2 Colapso de chaves compostas

O professor pediu chaves compostas pequenas (2 ou 3 atributos no máximo) e poucas. Veja o que aconteceu com as maiores:

| Tabela | Chave no modelo relacional | Chave no físico |
|---|---|---|
| video | (nome_canal, nro_plataforma, titulo, dataH): 4 atributos | `id_video` (1). A antiga vira `UNIQUE (id_canal, titulo, dataH)`. |
| comentario | (nome_canal, nro_plataforma, titulo_video, dataH_video, nick_usuario, seq): 6 | `id_comentario` (1) + `UNIQUE (id_video, seq)`. |
| doacao | os 6 acima + seq_pg: 7 | `id_doacao` (1) + `UNIQUE (id_comentario, seq_doacao)`. |
| bitcoin, paypal, cartao, mecanismo | 7 atributos (os da doação) | `id_doacao` (1). |
| canal | (nome, nro_plataforma): 2 | `id_canal` (1) + `UNIQUE (nro_plataforma, nome_canal)`. |

O efeito em cascata é grande. No modelo relacional, cada linha de bitcoin carregaria 7 colunas só de chave. Agora carrega 1.

As PKs compostas que sobraram têm **2 atributos**, todos numéricos: plataforma_usuario, streamer_pais, empresa_pais, patrocinio, nivel_canal, inscricao e participa. São tabelas de junção (N:N), em que a PK composta é a forma natural de dizer "este par só pode aparecer uma vez". Criar um id artificial nelas só acrescentaria uma coluna e um índice sem ganho.

### 3.3 Escolha de tipos (os detalhes que o professor disse que "cada tabela tem")

- **Dinheiro é `NUMERIC`, nunca `FLOAT`/`REAL`.** Ponto flutuante não representa 0,1 exatamente, e somar milhares de doações acumularia erro de centavos. O `NUMERIC(14,2)` é exato.
- **Fator de conversão é `NUMERIC(18,6)`.** Taxas como 0,182345 precisam de 6 casas.
- **Telefone, CNPJ, passaporte e número do cartão são `VARCHAR`, não número.** Eles têm `+`, letras, pontuação e zeros à esquerda (que um número perderia), e ninguém faz conta com eles.
- **Código da moeda é `CHAR(3)`; TxID do bitcoin é `CHAR(64)`.** O tamanho é sempre fixo: o padrão ISO tem 3 letras, e um hash SHA-256 em hexadecimal tem 64 caracteres.
- **O GIF do nível guarda o caminho do arquivo (`VARCHAR`), não o arquivo (`BYTEA`).** Guardar imagens dentro do banco incha a tabela e os backups. O arquivo fica num servidor de arquivos.
- **`DATE` para nascimento e fundação, `TIMESTAMP` para vídeo, comentário e cartão.** A hora só importa nos eventos.
- **`coment_on` é `BOOLEAN`.** Só existem dois estados, online e offline.

### 3.4 ENUMs

O enunciado define três domínios fechados:
- tipo do canal: {privado, público, misto};
- status da doação: {recusado, recebido, lido};
- bandeira do cartão.

Para eles usamos `CREATE TYPE ... AS ENUM`. Comparado com `VARCHAR + CHECK`:

- O ENUM ocupa 4 bytes por linha, contra o texto inteiro repetido.
- O domínio fica documentado num lugar só e pode ser reaproveitado.
- Rejeita qualquer valor fora da lista.

**E se aparecer um valor novo?** O ENUM não fica engessado: `ALTER TYPE ... ADD VALUE` acrescenta o valor sem reescrever a tabela. Por isso a bandeira do cartão também virou ENUM: bandeiras novas são raras.

### 3.5 Políticas de FK: ON DELETE e ON UPDATE

O professor pediu as políticas "bem definidas para todas as chaves estrangeiras". A regra que usamos:

- **`ON UPDATE RESTRICT` em todas.** As PKs referenciadas são IDENTITY (ou DDI) e nunca mudam, então bloquear a alteração é coerente.
- **`ON DELETE CASCADE`** quando o filho **não tem sentido sem o pai** e não é registro importante:
  - níveis de um canal;
  - passaportes de um usuário;
  - contas nas plataformas;
  - inscrições;
  - participações;
  - comentários de um vídeo;
  - dados específicos de uma forma de pagamento.
- **`ON DELETE RESTRICT`** quando apagar o pai **destruiria informação importante em silêncio**:
  - não se apaga país com usuários, nem moeda usada por país;
  - não se apaga empresa que fundou plataforma ou que patrocina canal;
  - não se apaga canal com vídeos ou patrocínio vigente;
  - não se apaga comentário com doação, porque doação é registro financeiro.
- **`SET NULL` nunca foi usado:** todas as FKs são `NOT NULL`.

Um caso para notar: `comentario -> video` é CASCADE, mas `doacao -> comentario` é RESTRICT. Na prática, apagar um vídeo cujos comentários têm doação **é bloqueado**. É a intenção: doações não podem sumir junto com um vídeo.

### 3.6 Onde fica cada validação (regra da consultoria)

O professor separou as verificações em três lugares:

| Tipo de regra | Onde fica | Exemplo no trabalho |
|---|---|---|
| Formato (data bem digitada, e-mail com @) | Front-end | Não validamos formato no banco. Seria peso a mais a cada inserção. |
| Regra de negócio que muda com o tempo | Back-end (aplicação) | Por exemplo, idade mínima para ter canal. Não pusemos no banco. |
| Regra de negócio estável, que "quase nunca muda" | Banco | Nível de 1 a 5 (`CHECK`), valores positivos, status em ENUM, unicidades, dono de canal precisa ser streamer (trigger T7), doação de uma só forma (trigger T6). |

O próprio professor usou o nível de 1 a 5 como exemplo de regra que deve ir direto para o banco.

### 3.7 A moeda das doações (uma decisão de interpretação)

O enunciado diz que o patrocínio é em dólares, mas não diz a moeda da doação. Se tudo estivesse em dólar, a tabela `conversao` não teria utilidade. Interpretamos assim:

- O valor da doação está na **moeda do país de residência de quem doou** (`usuario.pais_residencia -> pais.moeda_id -> conversao`).
- As consultas convertem para dólar multiplicando por `fator_conver`.

**Por que não guardar a moeda na própria doação?** Seria um atributo fora do modelo. Além disso, a moeda já é alcançável pelo usuário que comentou, e guardá-la de novo seria redundância.

**Limitação, para citar se perguntarem:** se o usuário mudar de país, as doações antigas passam a ser lidas na moeda nova. Como o sistema não guarda histórico (o mesmo vale para patrocínios e membros, pelo enunciado), aceitamos essa limitação.

Os níveis de membro foram assumidos em dólar, como o patrocínio.

---

## 4. Triggers

A Aula 13 define uma trigger por três coisas:
- **evento**: INSERT, UPDATE ou DELETE;
- **timing**: BEFORE ou AFTER;
- **nível**: ROW, uma vez por linha, ou STATEMENT, uma vez por comando.

Cada trigger abaixo é explicada nesses termos.

### 4.1 T1 e T2: os dois atributos derivados

O professor disse na consultoria: "tem duas tabelas que têm atributos derivados armazenados; a gente tem que garantir que o valor armazenado corresponde ao valor real". São elas:

- `plataforma.qtd_users`, que é o número de contas em `plataforma_usuario`;
- `canal.qtd_visualizacoes`, que é a soma de `visu_total` dos vídeos do canal.

**Por que manter a coluna, em vez de calcular sempre?** O enunciado lista esses atributos, e eles são **lidos muito mais vezes do que mudam**: toda página de canal mostra as visualizações. Calcular `SUM` a cada leitura seria caro. Guardar e manter por trigger é uma **redundância controlada**.

| | T1 (`trg_plataforma_usuario_qtd`) | T2 (`trg_video_qtd_visualizacoes`) |
|---|---|---|
| Evento | INSERT, DELETE e UPDATE de nro_plataforma em plataforma_usuario | INSERT, DELETE e UPDATE de visu_total ou id_canal em video |
| Timing | AFTER: só mexe no contador depois que a linha foi gravada de fato; se o INSERT falhar, o contador não muda | AFTER |
| Nível | ROW: cada conta soma ou subtrai 1 | ROW: soma a diferença (delta) |
| Ideia | `qtd_users + 1` ou `- 1` | `qtd_visualizacoes - OLD.visu_total + NEW.visu_total` |

**Por que somar a diferença e não recalcular o total?** Recalcular faria um `SUM` sobre todos os vídeos do canal a cada vídeo novo. Somar a diferença tem custo constante.

**Proteção contra alteração manual:** o par `trg_plataforma_protege_qtd` e `trg_canal_protege_qtd` (BEFORE INSERT/UPDATE) faz duas coisas:
- No INSERT, força o contador a começar em 0.
- No UPDATE, recusa qualquer mudança no contador que não venha de dentro de outra trigger.

Como sabemos de onde veio? `pg_trigger_depth()` vale 1 quando o UPDATE veio direto do usuário e 2 quando veio de dentro da T1 ou da T2. Sem essa proteção, um `UPDATE plataforma SET qtd_users = 0` deixaria o valor errado para sempre.

### 4.2 T3, T4 e T5: os números sequenciais

O enunciado pede três sequenciais que **recomeçam** em cada contexto:

| Trigger | Sequencial | Recomeça em cada... |
|---|---|---|
| T3 `trg_comentario_seq` | `comentario.seq` | vídeo |
| T4 `trg_doacao_seq` | `doacao.seq_doacao` | comentário |
| T5 `trg_mecanismo_plat_seq` | `mecanismo_plat.seq_plataforma` | par (usuário, plataforma) |

- **Evento:** INSERT.
- **Timing:** BEFORE, porque precisamos preencher `NEW.seq` antes de a linha ser gravada.
- **Nível:** ROW.

O cálculo é `MAX(seq) + 1` dentro do contexto.

**Por que não usar uma SEQUENCE do PostgreSQL?** A SEQUENCE é um contador **global**. Ela daria 1, 2, 3 para comentários de vídeos diferentes, e não recomeçaria em cada vídeo.

**O problema da concorrência, ligado à Aula 15 (Transações).** Imagine duas pessoas comentando no mesmo vídeo no mesmo instante. As duas transações calculam `MAX(seq) + 1 = 8` ao mesmo tempo e tentam gravar 8. Para evitar isso, a trigger primeiro faz `SELECT ... FOR UPDATE` na linha do vídeo:
- Isso **trava** a linha até o fim da transação.
- A segunda transação espera a primeira terminar e então calcula 9.
- O `UNIQUE (id_video, seq)` continua como rede de segurança.

**Por que o MAX é barato?** O `UNIQUE (id_video, seq)` cria uma B+-tree ordenada por vídeo e depois por seq. Achar o maior seq de um vídeo é ir até a última folha daquele vídeo, sem varrer a tabela.

**A T5 é mais cara.** Usuário e plataforma não estão na tabela `mecanismo_plat`; eles são alcançados pelo caminho doação, comentário, vídeo, canal. Por isso a T5 faz junções, e foi ela que motivou o índice I1 (seção 9).

**Bloqueio de alteração:** T3 e T4 também recusam um UPDATE que tente trocar o vídeo/comentário ou o próprio seq. Isso quebraria a numeração.

### 4.3 T6: a especialização disjunta das doações

No modelo ER, a doação se especializa com um "d" (disjunta) em cartão, PayPal, bitcoin e mecanismo da plataforma. Ou seja, **uma doação é de uma forma só**.

- A PK de cada subtabela já impede repetir a mesma doação **dentro** dela.
- Nenhuma constraint declarativa (PK, UNIQUE, CHECK, FK) consegue olhar **outra** tabela. Só uma trigger consegue impedir a mesma doação em bitcoin e em PayPal ao mesmo tempo.

Como funciona:
- **Evento:** INSERT e UPDATE de id_doacao em cada uma das 4 subtabelas.
- **Timing:** BEFORE, para bloquear antes de gravar.
- **Nível:** ROW.
- **Uma função para 4 tabelas:** a variável automática `TG_TABLE_NAME` (Aula 13, "variáveis automáticas") diz qual tabela disparou, e a função verifica as outras três.

**E a doação sem nenhuma forma?** Ela é evitada pelas functions de inserção (seção 5): toda forma de inserir doação grava a superclasse e a subclasse juntas.

### 4.4 T7: dono de canal e participante precisam ser streamers

O requisito diz que "canais estão associados a streamers em plataformas". No ER, o streamer é uma especialização do usuário. No físico, **streamer = usuário com passaporte em `streamer_pais`**. Duas triggers BEFORE garantem a regra:

- `trg_canal_valida_dono`:
  - O dono do canal tem passaporte, ou seja, é streamer.
  - Ele tem conta (`plataforma_usuario`) na plataforma do canal.
- `trg_participa_valida_streamer`: quem participa de um vídeo também é streamer.

É uma regra estável, então vai no banco (seção 3.6).

### 4.5 Por que ROW e não STATEMENT?

Com nível STATEMENT, a trigger roda uma vez por comando e precisaria descobrir sozinha quais linhas mudaram. Em todas as nossas triggers a lógica é "para esta linha, faça X", então ROW é o natural.

Numa carga em massa, uma trigger STATEMENT com *transition tables* (`REFERENCING NEW TABLE`) seria mais eficiente. Com 10.000 linhas a carga inteira leva poucos segundos, então não compensou a complexidade.

---

## 5. Functions de inserção e transações

### 5.1 Por que inserir por functions

O professor pediu: "inserir um streamer: garantir que existe a plataforma, existe tal coisa, para depois inserir o streamer". Criamos 11 functions:

| Function | O que faz além do INSERT |
|---|---|
| `inserir_usuario` | Confere se o país existe e se o nick está livre, com mensagem clara. |
| `inserir_streamer` | Grava usuário + passaporte **juntos**. |
| `inserir_conta_plataforma` | Confere se usuário e plataforma existem. A T1 atualiza o contador. |
| `inserir_canal` | Confere a plataforma. A T7 confere se o dono é streamer com conta lá. |
| `inserir_video` | Confere o canal. A T2 soma as visualizações. |
| `inserir_comentario` | Confere vídeo e usuário. A T3 gera o seq. |
| `inserir_doacao_bitcoin`, `_paypal`, `_cartao`, `_plataforma` | Gravam doação + forma de pagamento **juntas**. |
| `inserir_doacao_base` | Parte comum das 4 acima (não é para ser chamada sozinha). |

O ganho:
- **Mensagens claras.** "País de residência com DDI 9999 não existe", em vez do erro genérico de violação de FK.
- **Operações de várias tabelas viram uma só.** Ninguém consegue gravar meio streamer.
- **Encapsulamento.** O seq não é parâmetro: quem chama nem precisa saber que ele existe.

Tabelas de domínio simples (país, moeda, empresa, níveis, patrocínios...) são inseridas com `INSERT` direto no povoamento. Nelas a FK e os CHECKs já bastam e não há regra entre várias tabelas.

### 5.2 Onde entram as transações (Aula 15)

O professor disse que transação não é obrigatória, mas que gostaria de ver. Elas aparecem em três lugares:

1. **Toda function é atômica.** Ela roda dentro da transação de quem a chamou. Se o INSERT da subclasse falhar em `inserir_doacao_paypal`, por exemplo por um `id_paypal` repetido, o INSERT da doação feito antes **também é desfeito**. É o "A" de ACID: tudo ou nada.
2. **O povoamento inteiro está entre `BEGIN` e `COMMIT`.** Se qualquer etapa falhar, o banco volta a ficar vazio, sem carga pela metade.
3. **`SELECT ... FOR UPDATE` nas triggers de sequencial.** É controle de concorrência: trava a linha para duas transações simultâneas não gerarem o mesmo número. Essa é a parte de "isolamento" (o "I" de ACID).

O `dev/verificacoes.sql` também usa transação: faz uma inserção completa de teste e no fim dá `ROLLBACK`, deixando o banco como estava.

---

## 6. Visões

### 6.1 Virtual ou materializada: o critério

O professor pediu para justificar cada uma ("por que essa é materializada? por que essa é virtual?").

- **Visão virtual** (Aula 14) é uma consulta guardada com nome. Toda vez que alguém faz `SELECT` nela, o banco roda a consulta de novo.
  - Vantagens: está sempre atualizada e não ocupa disco.
  - Desvantagem: custa o mesmo que a consulta original, toda vez.
- **Visão materializada** grava o **resultado** em disco, como uma tabela.
  - Vantagem: a leitura é barata.
  - Desvantagem: o dado só muda quando alguém roda `REFRESH MATERIALIZED VIEW`. Entre um refresh e outro, ela pode ficar desatualizada.

O critério que usamos:
- **Materializada** quando a consulta é cara (junções e agregações nas tabelas grandes) **e** o resultado é lido muito mais do que muda **e** um pequeno atraso é aceitável. Rankings e relatórios de faturamento são assim.
- **Virtual** quando a consulta é barata, ou quando o dado precisa estar sempre atualizado.

### 6.2 As 5 visões

| Visão | Tipo | Usada nas consultas | Por que esse tipo |
|---|---|---|---|
| `vw_canal_info` | Virtual | 3, 4 (exibição de nomes) | Só junta 3 tabelas pela PK, o que é barato. Um canal novo precisa aparecer na hora. |
| `mv_interacoes_video` | **Materializada** | 2, 3 | Agrega a tabela `comentario`, a maior do banco. Contagem de interações para ranking tolera minutos de atraso. |
| `mv_doacoes_canal` | **Materializada** | 4, 7, 10, 11 | A mais cara do trabalho: junta 6 tabelas para converter cada doação para dólar. Um único cálculo serve 4 consultas. |
| `vw_membros_canal` | Virtual | 9, 11 | Junta só inscrição e nível pela PK do nível. Membros entram e saem todo dia. |
| `vw_faturamento_canal` | Virtual | 11 | Só combina resultados já agregados: patrocínio (tabela pequena), `vw_membros_canal` e `mv_doacoes_canal`, que já é materializada. Materializar de novo duplicaria dados e exigiria mais um REFRESH. |

### 6.3 Detalhes que podem ser perguntados

- **`WITH NO DATA`:** as visões materializadas são criadas vazias no `02`, porque ainda não há dados. O povoamento (`03`) chama `atualizar_visoes_materializadas()` no fim.
- **Política de refresh:** periódica (por exemplo, a cada hora ou de madrugada, por um agendador como o pg_cron) e após cargas grandes.
- **Por que não um REFRESH por trigger a cada comentário?** O banco recalcularia a visão inteira a cada inserção, o que é muito pior do que não ter visão.
- **`LEFT JOIN` em `mv_interacoes_video`:** vídeos sem nenhum comentário aparecem com 0. Isso importa para a média de interações por vídeo da consulta 3. Sem o LEFT JOIN, a média só consideraria vídeos comentados e sairia inflada.
- **Doações "recusado" ficam de fora de `mv_doacoes_canal`:** não geraram dinheiro.

---

## 7. Povoamento

### 7.1 O que o professor pediu

"O valor do dado não tem importância; a distribuição do dado é importante." Dados uniformes (cada canal com o mesmo número de vídeos, cada vídeo com o mesmo número de comentários) não refletem o mundo real e **distorcem a escolha dos índices**.

Por quê? O otimizador decide entre usar um índice e varrer a tabela pela **seletividade** do predicado, ou seja, quantas linhas o filtro devolve. Num canal gigante, o filtro devolve muitas linhas e varrer pode ser melhor. Num canal pequeno, o índice ganha. Com dados uniformes, essa diferença some e o teste de índices fica artificial.

### 7.2 Como geramos a concentração

A função `pop_concentrado(n, e)` sorteia um número de 1 a n com `1 + floor(n * random()^e)`:

- Com `e = 1`, o sorteio é uniforme.
- Com `e = 3`, cerca de **46% dos sorteios caem nos primeiros 10%** dos itens, porque 0,1^(1/3) ≈ 0,46.

Ela foi usada em quase tudo:
- poucas plataformas (YouTube, Twitch) concentram as contas;
- poucos canais concentram vídeos, membros e patrocínio;
- os vídeos mais vistos concentram os comentários;
- poucos usuários comentam muito;
- o nível 1 de membro, o mais barato, é o mais comum;
- os valores (visualizações, patrocínio, doação) seguem uma exponencial: muitos valores pequenos e poucos enormes (cauda longa).

Resultado medido:
- O canal mais forte tem 708 vídeos e 1.026 membros.
- Mais da metade dos vídeos (5.214) não tem comentário.
- **1% dos vídeos concentra 22,5% dos comentários.**
- O YouTube tem 907 contas; centenas de plataformas fictícias têm poucas ou nenhuma.

### 7.3 Volumes

Todas as tabelas ficam entre 1.000 e 10.000 tuplas (o `dev/verificacoes.sql` confere). As subtabelas de doação foram o que mais pesou no dimensionamento: para cada uma ter pelo menos 1.000 linhas, foram necessárias pelo menos 4.000 doações. Geramos 5.000, com 1.250 de cada forma.

### 7.4 Reprodutibilidade

`SELECT setseed(0.2026)` fixa a semente do `random()`. Rodar o povoamento de novo gera **exatamente os mesmos dados**, o que permite ao professor reproduzir os mesmos números.

O povoamento termina com `ANALYZE`, que atualiza as estatísticas do catálogo (Aula 12). O otimizador usa essas estatísticas para estimar a seletividade; sem elas, estimaria às cegas.

---

## 8. Consultas

### 8.1 Por que functions

Nas palavras do professor: o SELECT é "fechadinho". Para ter o top 3 e o top 5, seria preciso copiar a consulta e mudar o número. A function recebe `k` e os filtros como parâmetros e pode ser chamada quantas vezes for preciso.

Os padrões usados:

- **`RETURNS TABLE (...)` + `RETURN QUERY`:** a function devolve linhas, e você usa `SELECT * FROM consultaN(...)` como se fosse uma tabela.
- **Filtro opcional = parâmetro `DEFAULT NULL`.** Chamar `consulta1_streamers_mais_videos()` lista todos; chamar `consulta1_streamers_mais_videos(2)` filtra a plataforma 2. Dentro dela, `WHERE p IS NULL OR coluna = p`.
- **`#variable_conflict use_column`:** as colunas de saída têm o mesmo nome de colunas das tabelas (ex.: `nick`). A diretiva diz ao PL/pgSQL que, dentro do SQL, o nome se refere à coluna.
- **Validação de `k`:** a function `valida_k` recusa k nulo, zero ou negativo (IF da Aula 13).

### 8.2 Polimorfismo

O professor disse que "pelo menos uma tem que ser polimórfica". No PostgreSQL, polimorfismo por **sobrecarga** significa duas functions com o **mesmo nome** e parâmetros de **tipos diferentes**. O banco escolhe qual executar pelo tipo do argumento:

```sql
SELECT * FROM consulta5_patrocinios(10);                  -- INTEGER -> versão por número da empresa
SELECT * FROM consulta5_patrocinios('Empresa 10 S.A.');   -- texto   -> versão por nome
SELECT * FROM consulta12_top_k_plataformas(5, 2);         -- INTEGER -> por número da plataforma
SELECT * FROM consulta12_top_k_plataformas(5, 'Twitch');  -- texto   -> por nome
```

A versão por nome converte o nome no número e chama a versão por número. Assim a lógica da consulta existe uma vez só.

### 8.3 As 12 consultas e suas interpretações

| # | Function | Fonte | Interpretação que adotamos |
|---|---|---|---|
| 1 | `consulta1_streamers_mais_videos(plataforma)` | canal + video | "Publicados" = vídeos dos canais de que o streamer é dono. |
| 2 | `consulta2_videos_mais_comentados(canal)` | `mv_interacoes_video` | Só lista vídeos com pelo menos 1 comentário. |
| 3 | `consulta3_canais_mais_interacoes(streamer)` | `mv_interacoes_video` | A média por vídeo inclui os vídeos sem comentário. |
| 4 | `consulta4_canais_media_doacao(plataforma)` | `mv_doacoes_canal` | Média por comentário = total recebido / nº de comentários que trouxeram doação. |
| 5 | `consulta5_patrocinios(empresa)` | patrocinio | Polimórfica. |
| 6 | `consulta6_membros_por_usuario(usuario)` | inscricao + nivel_canal | Valor mensal = soma dos valores dos níveis. |
| 7 | `consulta7_canais_com_doacoes(canal)` | `mv_doacoes_canal` | Só doações recebidas ou lidas. |
| 8 | `consulta8_top_k_patrocinio(k)` | patrocinio | Soma dos patrocínios vigentes. |
| 9 | `consulta9_top_k_membros(k)` | `vw_membros_canal` | Soma mensal dos membros. |
| 10 | `consulta10_top_k_doacoes(k)` | `mv_doacoes_canal` | Total em dólar de todos os vídeos do canal. |
| 11 | `consulta11_top_k_faturamento(k)` | `vw_faturamento_canal` | Soma das 3 fontes, e mostra cada parcela. |
| 12 | `consulta12_top_k_plataformas(k, plataforma)` | plataforma + canal | Streamers = streamers distintos com canal na plataforma. Ordena por streamers e desempata por canais. Polimórfica. |

**Ressalva da consulta 11, para citar se perguntarem:** membros é uma receita **mensal**, enquanto patrocínio e doações são valores registrados (vigentes ou acumulados). Somamos como o enunciado pede, mas mostramos cada parcela separada para a leitura não enganar.

---

## 9. Índices

### 9.1 O processo (não é tentativa e erro)

O professor foi enfático: escolher índice "não é tentativa e erro". É identificar o problema, conhecer as ferramentas e medir para decidir entre alternativas. Seguimos 4 passos:

**Passo 1: só consultas com predicado.** Consulta sem `WHERE` seletivo, como os top-k que leem tudo para ordenar, não melhora com índice. Restaram:
- as consultas com filtro (1 a 7 e 12);
- as escritas frequentes (inserir comentário, inserir Super Chat);
- o REFRESH das visões.

**Passo 2: ver o que já tem índice.** O PostgreSQL cria um índice B+-tree para cada PK e cada UNIQUE. Um índice composto serve para buscas pela **primeira** coluna dele. Por isso, várias colunas que pareciam precisar de índice já tinham:

| Coluna filtrada | Já coberta por | Consultas |
|---|---|---|
| `canal.nro_plataforma` | `UNIQUE (nro_plataforma, nome_canal)` | 1, 4, 12 |
| `patrocinio.nro_empresa` | PK `(nro_empresa, id_canal)` | 5 |
| `comentario.id_video` | `UNIQUE (id_video, seq)` | trigger T3, REFRESH |
| `doacao.id_comentario` | `UNIQUE (id_comentario, seq_doacao)` | trigger T4, REFRESH |

**Passo 3: medir cada candidato** com o script `medicoes/medir_indices.sql`:
- Mede a linha de base sem índice.
- Cria um índice candidato, roda `ANALYZE`, mede tudo de novo e apaga o índice.
- Repete para cada candidato.
- Cada consulta roda 300 vezes, e cada escrita, 20. A primeira execução é descartada, porque só aquece o cache (o "cuidado com cache" da consultoria).
- As escritas são desfeitas depois de medidas, para não alterar os dados entre uma medição e outra.

**Passo 4: escolher os 5 de maior ganho** em operações relevantes, considerando o custo extra na inserção.

### 9.2 Os 5 escolhidos

| # | Índice | Tipo | Ganho medido | Por quê |
|---|---|---|---|---|
| I1 | `comentario(nro_usuario)` | Hash | Inserir 100 Super Chats: de ~17 ms para ~4 ms (**3,4x a 4,1x**) | A trigger T5 procurava "doações deste usuário nesta plataforma" varrendo os 10.000 comentários a cada Super Chat. É a escrita mais frequente numa live. Também acelera a checagem da FK ao apagar usuário. |
| I2 | `mv_interacoes_video(id_canal)` | B+-tree | Consulta 2 com filtro: **5,3x**; consulta 3: 1,9x a 2,0x | Sem índice, filtrar um canal lê a visão inteira. Visão materializada é gravada como tabela, então aceita índice. |
| I3 | `inscricao(nro_usuario)` | Hash | Consulta 6 com filtro: **3,9x** | A PK de inscrição começa por `id_canal`, então não serve para buscar pelo usuário. |
| I4 | `mv_doacoes_canal(id_canal)` | B+-tree | Consulta 7 com filtro: **2,2x** | É a consulta que a página do canal chamaria a cada acesso. |
| I5 | `canal(nro_streamer)` | Hash | Consulta 3 com filtro: **~1,35x** (o menor dos cinco) | Acha os canais do streamer sem varrer os 3.000. Também acelera a checagem da FK ao apagar usuário. |

### 9.3 Hash ou B+-tree?

- **Hash** (Aula 03) responde só a igualdade (`=`), em cerca de 1 acesso.
- **B+-tree** (Aula 04) responde a igualdade, intervalo (`<`, `>`, `BETWEEN`) e ordenação.

Medimos os dois para cada finalista, em duas rodadas, e eles **empataram**. A vantagem trocava de lado de uma rodada para outra: no `comentario(nro_usuario)`, a B+-tree deu 4,07x na rodada A e o hash deu 4,08x na rodada B. Como a medição não decide, o desempate foi conceitual:

- **Hash nas tabelas-base** (I1, I3, I5): essas colunas só são consultadas por igualdade ("os comentários do usuário X"). Nunca há busca por intervalo de `nro_usuario`, então a ordem que a B+-tree oferece não seria usada.
- **B+-tree nas visões materializadas** (I2, I4): `id_canal` também é a coluna de **junção** com `canal` e entre as visões (`vw_faturamento_canal`). A B+-tree entrega as linhas já ordenadas, o que permite ao otimizador um *merge join*. O hash não oferece ordem.

É uma boa resposta para o professor: medimos, deu empate, e então decidimos pelo que cada estrutura oferece.

### 9.4 O overhead de inserção

Todo índice tem um custo: cada INSERT ou UPDATE precisa atualizar também o índice. O enunciado manda considerar isso. Na medição:
- **Inserir 100 comentários** não ficou mais lento com nenhum dos 5 índices além do ruído de medição.
- **O custo dos índices das visões aparece no REFRESH.** É um custo aceitável, porque o REFRESH roda poucas vezes, enquanto as consultas rodam o tempo todo.

### 9.5 Por que o ganho absoluto é pequeno

As consultas levam frações de milissegundo porque o enunciado limita cada tabela a 10.000 linhas, e tudo cabe na memória. O que vale para a justificativa é o **ganho relativo**:

- Sem índice, o custo cresce com o tamanho da **tabela**, porque é preciso varrer tudo.
- Com índice, o custo cresce com o tamanho do **resultado**.

Com um milhão de comentários, a T5 sem índice ficaria 100 vezes mais lenta. Com índice, ficaria praticamente igual. É o raciocínio de "ordem de grandeza" que o professor usou na consultoria.

### 9.6 Comparação com os 5 índices que o grupo tinha rascunhado

| Rascunho do grupo | O que aconteceu |
|---|---|
| `Canal USING hash (nick_streamer)` | Virou **I5** `canal(nro_streamer)`. A coluna nick_streamer não existe mais; o canal aponta para o `nro_streamer` numérico. |
| `Inscricao USING hash (nick_membro)` | Virou **I3** `inscricao(nro_usuario)`, pelo mesmo motivo. |
| `Canal USING hash (nro_plataforma)` | **Removido:** já é coberto por `UNIQUE (nro_plataforma, nome_canal)`. Medido, não teve ganho. |
| `Patrocinio USING btree (nome_canal, nro_plataforma)` | **Removido:** as colunas não existem mais (agora é `id_canal`). A consulta 8 lê o patrocínio inteiro, sem predicado, então índice não ajuda. |
| `Doacao ... WHERE status IN ('recebido','lido')` (parcial) | **Removido:** a ideia de índice parcial é boa (Aula 05). Mas as consultas 4, 7, 10 e 11 agora leem a visão materializada, e a busca por comentário já é coberta pelo UNIQUE. Medido, não teve ganho. |

A justificativa antiga "B-tree porque tem duas colunas" também precisava de ajuste. O motivo real é que **o índice hash do PostgreSQL só aceita uma coluna** e só serve para igualdade. Um índice de duas colunas precisa ser B+-tree.

---

## 10. O que mudou em relação ao que o grupo já tinha

O `schema.sql` original virou `sql/01_ddl.sql` e recebeu estas mudanças. Os comentários do grupo foram mantidos onde continuavam valendo.

1. **Criadas as 5 tabelas que faltavam:** `doacao`, `bitcoin`, `paypal`, `cartao_credito`, `mecanismo_plat`, além dos ENUMs `status_doacao_enum` e `bandeira_cartao_enum`.
2. **`comentario` passou a referenciar `video` por `id_video`.** Antes usava a chave natural de 3 colunas (`nro_canal, titulo_video, dataH_video`), o que contradizia a chave artificial já criada no vídeo. O `UNIQUE` do comentário passou a ser `(id_video, seq)`.
3. **`qtd_users` e `qtd_visualizacoes` foram mantidos, com trigger.** Os comentários `--!` sugeriam removê-los, mas o enunciado os lista e o professor pediu um mecanismo que garanta o valor. Ver seção 4.1.
4. **`canal.id_canal` passou de BIGINT para INTEGER,** pela cardinalidade (seção 3.1).
5. **Nome da FK para canal padronizado como `id_canal`** em todas as tabelas. Antes havia `nro_canal` em umas e `id_canal` em outras.
6. **Constraints nomeadas** em `conversao` (`pk_conversao`, `uq_conversao_moeda`...) para seguir o padrão do resto do arquivo.
7. **Adicionado `CHECK (ddi > 0)` em país.**

**Para o relatório no Google Docs:** o bloco da `plataforma` lá está sem vírgulas entre as constraints (`UNIQUE (nome)` seguido de `CONSTRAINT ck...`). Copie a versão do `01_ddl.sql`, que está correta.

---

## 11. O que decidimos NÃO fazer, e por quê

| Ideia | Por que ficou de fora |
|---|---|
| Particionar `comentario` e `video` (fragmentação horizontal, Aula 06), como sugere o rascunho do relatório | Particionar ajuda quando a tabela é enorme e as consultas filtram pela chave de partição (por exemplo, por data). Com no máximo 10.000 linhas por tabela e nenhuma consulta filtrando por data, o custo de gerenciar partições não se paga. Se o volume crescer, a partição por intervalo de `dataH` seria o caminho. |
| `CLUSTER` ("tabela por índice", Aula 05) | O CLUSTER reordena a tabela uma única vez e não se mantém com as inserções seguintes. Para tabelas que recebem inserções contínuas, o efeito se perde. |
| Mais de 5 índices | Limite do enunciado. Além disso, cada índice cobra custo em toda inserção. |
| REFRESH das visões por trigger | Recalcular a visão a cada comentário anularia o ganho (seção 6.3). |
| Guardar o número completo do cartão de forma segura | Num sistema real se guardaria só um token ou os 4 últimos dígitos (norma PCI-DSS). Seguimos o enunciado, que pede o número, e deixamos a observação no código. |
| Validar formato de e-mail, telefone e data no banco | Orientação da consultoria: isso é verificação de front-end (seção 3.6). |

---

## 12. Perguntas que o professor pode fazer

**"Por que vocês trocaram o nick pela chave artificial? O nick já era único."**
A PK vira uma B+-tree, e toda FK repete a chave. Comparar e armazenar um BIGINT de 8 bytes é mais barato que um VARCHAR de até 63. O nick continua `UNIQUE + NOT NULL`, então a unicidade do modelo foi preservada. Seção 3.1.

**"Por que BIGINT no usuário e INTEGER no canal?"**
Tamanho proporcional à cardinalidade. Usuários chegam a bilhões, além do limite do INTEGER (cerca de 2,1 bilhões). Canais são ordens de grandeza menos numerosos, e cada FK para canal economiza 4 bytes.

**"Por que não UUID?"**
16 bytes, e inserção aleatória na B+-tree, com muitos splits. UUID resolve geração distribuída de ids, e o nosso sistema é centralizado.

**"Como vocês garantem que `qtd_visualizacoes` está certo?"**
A trigger AFTER em vídeo soma a diferença a cada inserção, alteração ou remoção. Outra trigger BEFORE em canal bloqueia alteração manual (usa `pg_trigger_depth()`). O `dev/verificacoes.sql` compara o valor guardado com o `SUM` real e confirma que não há divergência.

**"E se dois comentários chegarem ao mesmo tempo no mesmo vídeo?"**
A trigger faz `SELECT ... FOR UPDATE` na linha do vídeo. A segunda transação espera a primeira terminar e só então calcula o próximo seq. O `UNIQUE (id_video, seq)` é a rede de segurança.

**"Por que essa visão é materializada?"**
`mv_doacoes_canal` junta 6 tabelas e converte moeda, e serve 4 consultas. `mv_interacoes_video` agrega a maior tabela. As duas alimentam rankings, que toleram atraso. Seção 6.2.

**"E por que essa é virtual?"**
É barata, ou precisa estar sempre atualizada. `vw_faturamento_canal` só combina resultados que já estão agregados. Seção 6.2.

**"Como as materializadas são atualizadas?"**
Com REFRESH periódico e após cargas, pela function `atualizar_visoes_materializadas()`. Não por trigger, porque recalcular a cada inserção anularia o ganho.

**"Por que esse índice e não outro?"**
Medimos, em duas rodadas. A tabela está em `medicoes/resultados.md`. Por exemplo, I1 deixou a inserção de Super Chat cerca de 4 vezes mais rápida. Vários candidatos foram descartados porque a coluna já era coberta por PK ou UNIQUE.

**"Por que hash?"**
As colunas só são buscadas por igualdade. Hash responde igualdade em cerca de 1 acesso e não oferece intervalo, que não usamos. Na medição empatou com a B+-tree.

**"A consulta 8 não precisa de índice?"**
Não. Ela lê todos os patrocínios para somar e ordenar; não há predicado seletivo. Como disse o professor, "tem consulta que não precisa de índice".

**"Onde está o polimorfismo?"**
Nas consultas 5 e 12: o mesmo nome com parâmetro INTEGER ou VARCHAR. O PostgreSQL escolhe a versão pelo tipo do argumento.

**"Por que inserir por function, se o FK já garante a existência?"**
Mensagem de erro clara, operação atômica em várias tabelas (usuário + passaporte; doação + forma de pagamento) e encapsulamento do seq.

**"A distribuição dos dados é realista?"**
É concentrada de propósito: 1% dos vídeos têm 22,5% dos comentários, o maior canal tem 708 vídeos e mais da metade dos vídeos não tem comentário. Seção 7.2.

**"Por que a doação está na moeda do usuário?"**
Para a tabela de conversão ter uso real. O enunciado fixa só o patrocínio em dólar. Seção 3.7.

**"Uma doação pode ser bitcoin e PayPal ao mesmo tempo?"**
Não. A trigger T6 bloqueia, porque a especialização é disjunta. Nenhuma constraint declarativa olha outra tabela; só trigger consegue.

---

## 13. Glossário rápido

| Termo | Em uma frase |
|---|---|
| Chave artificial | Número sem significado criado só para identificar a linha (ex.: `id_video`). |
| Chave natural | Atributo do mundo real que já identifica (ex.: nick). Aqui vira `UNIQUE`. |
| IDENTITY | Contador automático do PostgreSQL para a chave artificial. |
| Cardinalidade | Quantas linhas (ou valores distintos) uma tabela ou coluna tem. |
| Seletividade | Fração das linhas que um filtro devolve. Filtro seletivo devolve poucas linhas, e aí o índice ajuda. |
| Atributo derivado | Valor que pode ser calculado a partir de outras tabelas (ex.: total de visualizações). |
| Redundância controlada | Guardar um valor derivado de propósito, com um mecanismo (trigger) que o mantém certo. |
| Trigger BEFORE / AFTER | Roda antes de gravar (pode alterar ou barrar a linha) ou depois (reage ao que foi gravado). |
| Nível ROW / STATEMENT | Roda uma vez por linha ou uma vez por comando. |
| `FOR UPDATE` | Trava a linha lida até o fim da transação, para outra transação esperar. |
| Atomicidade | Tudo ou nada: se um passo falha, todos são desfeitos. |
| Visão virtual | Consulta guardada com nome; roda a cada uso. |
| Visão materializada | Resultado gravado em disco; só muda com REFRESH. |
| B+-tree | Índice em árvore ordenada; serve para igualdade, intervalo e ordenação. |
| Hash | Índice por função de espalhamento; serve só para igualdade. |
| Overhead de inserção | Custo extra que cada índice impõe a INSERT e UPDATE. |
| Sobrecarga (polimorfismo) | Funções com o mesmo nome e tipos de parâmetro diferentes. |
| `ANALYZE` | Atualiza as estatísticas que o otimizador usa para estimar custos. |
