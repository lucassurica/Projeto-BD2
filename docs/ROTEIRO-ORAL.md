# Roteiro para a prova oral de BD2

Sumário
1. Como vai ser a prova
2. Divisão do trabalho
3. Parte comum (todos leem): o projeto inteiro e o porquê de cada decisão
4. Partes individuais: Kayo, Gabriel, Lucas, Davi, João
5. Como estudar e ensaiar

---

## 1. Como vai ser a prova

O que o Prof. Bedo disse na consultoria 2: não há apresentação. Ele pega o código, roda e pergunta a cada membro, "como se fosse uma prova oral". Ele procura três coisas: **erros**, **decisões que não estão claras** e **coisas em que o grupo não pensou**.

**Pistas que ele já deu** (consultorias e enunciado), em ordem de peso:

1. **Índices são o centro.** "Eu tenho cinco índices. Sei quais consultas são mais complicadas. Vou olhar se o pessoal se atentou para essas consultas ou criou índice na tabela país." Critério dele: consulta **frequente**, **pesada**, com **predicado** e **seletividade** adequada; o tipo do predicado decide entre **B+-tree e hash**. O tempo é consequência: confere a decisão, não a motiva.
2. **O enunciado pede "considerar o overhead de inserção"** nos índices.
3. **Medição:** matar o processo do Postgres (cache frio) antes de cada execução, repetir 5–10 vezes, média e desvio padrão, gráfico antes/depois.
4. **Um índice pode servir várias consultas, e há consultas que não precisam de índice.**
5. **Visões "para otimizar o desempenho de buscas"** (enunciado), justificando cada uma.
6. **Atributos derivados:** trigger mantém o valor; para bloquear a alteração manual há 3 jeitos (DCL, trigger, DDL), e "dois dão problema".
7. **Functions:** tudo function; parâmetros de busca na assinatura; pelo menos uma polimórfica.
8. **Consulta 4:** JOIN normal, média só sobre comentários com doação. **Consulta 11:** "não tem como somar dia com mês e com ano". **Consulta 12:** "uma consulta só, complexa", com 3 agrupamentos.
9. **Design físico:** PK numérica, chave composta pequena, UNIQUE e NOT NULL, ENUMs, política de ON DELETE/ON UPDATE em toda FK.
10. **Validação:** formato é front-end; regra que muda vai no back-end; regra estável vai no banco.

---

## 2. Divisão do trabalho

Cada pessoa fica com **um índice, uma visão, pelo menos uma trigger, duas ou três consultas e as functions de inserção ligadas a elas**. Os pacotes foram montados por assunto (o índice de cada um serve uma consulta ou trigger do próprio pacote, sempre que possível) e têm carga parecida: entre 164 e 203 linhas do `sql/2_plpgsql.sql` cada (Kayo 181, Gabriel 203, Lucas 164, Davi 169, João 194). Os pacotes com menos linhas têm os itens conceitualmente mais pesados (consulta 11, V3).

| Quem | Assunto | Índice | Visão | Trigger(s) | Consultas | Functions de inserção |
|---|---|---|---|---|---|---|
| **Kayo** | Super Chat e membros | I1 `comentario(nro_usuario)` | V4 `vw_membros_canal` | T4, T5 | 9 | `inserir_usuario`, `inserir_streamer`, `inserir_doacao_base`, `inserir_doacao_plataforma` |
| **Gabriel** | Comentários e interações | I2 `mv_interacoes_video(id_canal)` | V2 `mv_interacoes_video` | T2/T2b, T3 | 2, 3 (+ padrões das consultas) | `inserir_video`, `inserir_comentario` |
| **Lucas** | Plataforma, patrocínio e faturamento | I3 `inscricao(nro_usuario)` | V5 `vw_faturamento_canal` | T1/T1b | 6, 8, 11 (+ `valida_k`) | `inserir_conta_plataforma` |
| **Davi** | Doações | I4 `mv_doacoes_canal(id_canal)` | V3 `mv_doacoes_canal` (+ REFRESH) | T6 | 4, 7, 10 | `inserir_doacao_bitcoin`, `_paypal`, `_cartao` |
| **João** | Canais, streamers e polimorfismo | I5 `canal(nro_streamer)` | V1 `vw_canal_info` | T7 (+ participante) | 1, 5, 12 | `inserir_canal` |

**Linhas de cada item no `sql/2_plpgsql.sql`**

| Item | Linhas | Item | Linhas | Item | Linhas |
|---|---|---|---|---|---|
| T1/T1b | 29–72 | `inserir_usuario` | 285–307 | Consulta 1 | 622–640 |
| T2/T2b | 73–110 | `inserir_streamer` | 308–328 | Consulta 2 | 641–661 |
| T3 | 111–145 | `inserir_conta_plataforma` | 329–346 | Consulta 3 | 662–682 |
| T4 | 146–170 | `inserir_canal` | 347–366 | Consulta 4 | 683–701 |
| T5 | 171–211 | `inserir_video` | 367–386 | Consulta 5 (2 versões) | 702–734 |
| T6 | 212–240 | `inserir_comentario` | 387–408 | Consulta 6 | 735–751 |
| T7 + participante | 241–278 | `inserir_doacao_base` | 409–428 | Consulta 7 | 752–767 |
| V1 | 484–501 | `inserir_doacao_bitcoin/paypal/cartao` | 429–466 | `valida_k` | 768–779 |
| V2 | 502–518 | `inserir_doacao_plataforma` | 467–478 | Consulta 8 | 780–796 |
| V3 | 519–550 | Padrões das consultas | 602–620 | Consulta 9 | 797–813 |
| V4 | 551–563 | I1 | 919–927 | Consulta 10 | 814–830 |
| V5 | 564–588 | I2 | 928–937 | Consulta 11 | 831–852 |
| REFRESH | 589–596 | I3 | 938–946 | Consulta 12 (2 versões) | 853–910 |
|  |  | I4 | 947–956 | I5 | 957–964 |

O `sql/1_ddl.sql` e a medição dos índices estão na parte comum: **todos leem**.

---

## 3. Parte comum (todos leem): o projeto inteiro e o porquê de cada decisão

Cada tema tem duas explicações: **"Na linguagem da aula"**, com os conceitos dos slides (o número da aula vem entre parênteses), e **"Explicando do zero"**, para quem nunca ouviu falar do assunto.

### 3.1 O projeto em uma página

**Na linguagem da aula.** O trabalho pega um modelo relacional já normalizado (streamers, canais, vídeos, comentários, doações, patrocínios e membros) e faz o **projeto físico** dele no PostgreSQL, um SGBD **monolítico e centralizado**. A ordem é a que o professor pediu: (1) design físico (`1_ddl.sql`), (2) povoamento com distribuição realista (`3_dados.sql`), (3) consultas como functions PL/pgSQL, e só então (4) índices e visões, escolhidos olhando as consultas. Triggers mantêm a consistência (atributos derivados, sequenciais, regras que constraint não expressa). A entrega tem 4 arquivos SQL e um relatório de decisões.

**Explicando do zero.** Imagine um "YouTube + Twitch" de mentira. O banco de dados é o arquivo onde ficam todos os canais, vídeos, comentários e doações. Primeiro a gente desenhou as gavetas (tabelas). Depois encheu de dados parecidos com os reais. Depois escreveu as perguntas que o sistema precisa responder ("quais canais mais faturam?"). Só no fim a gente deixou as perguntas mais rápidas, com atalhos (índices) e resumos prontos (visões). Fazer nessa ordem importa: se a gaveta foi mal desenhada, todo o resto fica torto.

### 3.2 Design físico (`1_ddl.sql`)

**Na linguagem da aula.**
- **PK numérica:** a PK vira um índice **B+-tree** (Aula 04). Chave inteira é menor que texto, então cabem mais chaves por nó (cada nó ocupa uma página de disco), a árvore fica mais baixa e a busca faz menos acessos a disco, da ordem de log_B(n).
- **Chave artificial preserva a unicidade e a cardinalidade:** a chave natural antiga vira `UNIQUE NOT NULL`. O Postgres cria índice para PK e UNIQUE (Aula 05: o UNIQUE é "indicado para chave candidata que não é PK").
- **Chaves compostas grandes viraram artificiais:** `video` (4 atributos), `comentario` (6) e `doacao` (7). As de 2 atributos ficaram compostas.
- **Integridade:** `NOT NULL`, `CHECK` para regras estáveis, **ENUM** para domínio fechado, e política de `ON DELETE`/`ON UPDATE` em toda FK.
- **Especialização disjunta de doação:** uma tabela por subclasse.

**Explicando do zero.** Pense na chamada da escola: é mais rápido achar o aluno pelo número da matrícula do que pelo nome completo. Por isso cada tabela ganhou um número de identificação. Mas o nome continua proibido de se repetir (o `UNIQUE`), para não existirem dois "kayo123". O ENUM é um menu de opções fixas: o tipo do canal só pode ser privado, público ou misto. E as regras de apagar dizem o que acontece com os "filhos": não dá para apagar um canal que tem vídeos (`RESTRICT`), mas se o canal for apagado, os níveis de membro dele vão junto (`CASCADE`).

### 3.3 Índices

**Na linguagem da aula.**
- Um índice é uma estrutura que organiza os registros para acelerar a recuperação pela **chave de pesquisa** usada na **condição de pesquisa** (Aula 02). Sem índice, a busca lê todas as páginas da tabela.
- No PostgreSQL os índices são **secundários** por padrão: a ordem física das tuplas não segue a chave (Aula 05). Todos os nossos 5 são secundários.
- **Hash** (Aula 03): calcula o bucket a partir da chave; ótimo para **exact match** (igualdade), não serve para intervalo nem ordenação.
- **B+-tree** (Aula 04): dados nas folhas, folhas encadeadas; serve igualdade, intervalo e ordenação.
- **Custo:** todo INSERT, UPDATE e DELETE também atualiza o índice (overhead de inserção, que o enunciado manda considerar).
- **Critério de escolha** (consultoria 1 e 2): consulta frequente, pesada, com predicado seletivo. Tabela pequena não leva índice. Limite de 5 índices: é um problema de **priorização**.

**Explicando do zero.** O índice é o índice remissivo no fim do livro: em vez de ler o livro inteiro atrás de "trigger", você vai direto à página. O hash funciona como os escaninhos de correio de um prédio: pelo número do apartamento você sabe na hora em qual caixinha olhar, mas não consegue pedir "do 100 ao 200". A B+-tree é como um dicionário em ordem alfabética: acha uma palavra e também "todas de A a C". Mas cada índice é mais um livro para manter atualizado: toda vez que um dado entra, o índice também precisa ser escrito. Por isso só vale criar onde a busca é frequente e devolve poucas linhas.

**Os 5 índices do projeto**

| Índice | Tipo | Para quê | Ganho medido |
|---|---|---|---|
| I1 `comentario(nro_usuario)` | hash | Trigger T5, a cada Super Chat | 2,71x |
| I2 `mv_interacoes_video(id_canal)` | B+-tree | Consultas 2 e 3 filtradas | 1,08x (consulta 2) |
| I3 `inscricao(nro_usuario)` | hash | Consulta 6 filtrada | 1,11x |
| I4 `mv_doacoes_canal(id_canal)` | B+-tree | Consulta 7 filtrada | 1,05x |
| I5 `canal(nro_streamer)` | hash | Consulta 3 filtrada | 1,08x |

### 3.4 Otimização de consultas: plano de execução e catálogo

**Na linguagem da aula.**
- O processamento de uma consulta passa por **parsing, reescrita, seleção do QEP e execução do QEP** (Aula 07).
- **QEP** (plano físico de execução) é a sequência de operadores escolhida; o PostgreSQL usa **otimização baseada em custo**: estima o custo de planos equivalentes, medido em **páginas acessadas**, e escolhe o menor (Aula 10).
- Os operadores aparecem no `EXPLAIN`: `Seq Scan` (table scan), `Index Scan`/`Bitmap Index Scan` (busca pelo índice), `Nested Loop`, `Hash Join`, `Merge Join` (Aula 11).
- A estimativa usa as **estatísticas do catálogo**: número de tuplas, de páginas, valores distintos, histograma (Aula 12). Estatística desatualizada leva a plano ruim ("garbage in, garbage out"); por isso o arquivo termina com `ANALYZE`.
- **Seletividade:** se o predicado devolve uma fração grande da tabela, ler tudo em sequência é mais barato que ir ao índice e pular página por página. O otimizador decide sozinho; o índice é só uma opção a mais.

**Explicando do zero.** O otimizador é o GPS do banco. Para cada pergunta ele calcula vários caminhos (ler a tabela toda, usar este ou aquele índice, juntar as tabelas de um jeito ou de outro) e escolhe o mais curto. Para calcular, ele usa um "mapa de trânsito": as estatísticas que o `ANALYZE` atualiza. Se a pergunta é "todos os canais da Twitch" e a Twitch tem 1/4 dos canais, o GPS percebe que é mais rápido passar por todos do que ficar consultando o índice a cada passo. Por isso, ter um índice não garante que ele será usado.

**O que o EXPLAIN mostrou no nosso banco** (Postgres 18, base do `3_dados.sql`)
- Usam índice: T5 (I1), consulta 2 por canal (I2), consulta 3 por streamer (I5 e I2), consulta 6 por usuário (I3), consulta 7 por canal (I4).
- Não usam, e está certo: as top-k sem filtro (8 a 12) e a consulta 4 filtrada por plataforma (predicado pouco seletivo). A consulta 11 lê tudo com `Seq Scan` + `Hash Join`, sem o I4.
- Dentro das functions, com o filtro `(p IS NULL OR coluna = p)`, o plano usa o índice mesmo na 7ª chamada seguida (conferido com `auto_explain`).

### 3.5 Medição de desempenho

**Na linguagem da aula.** O professor pediu: matar o processo (o SGBD tem **cache**; com os dados já na memória principal, nem se usa o índice), repetir 5–10 vezes, média e desvio padrão, gráfico antes/depois. O script `medicoes/medir_indices.py` faz isso: reinicia o PostgreSQL antes de cada execução, roda cada operação 10 vezes, mede o `Execution Time` do `EXPLAIN ANALYZE`, começa sem os 5 índices e depois cria um de cada vez com `ANALYZE`. São 130 execuções (`tempos.csv`) e um gráfico (`grafico_indices.svg`).

**Explicando do zero.** É como cronometrar uma corrida. Se o corredor já sabe o caminho de cor (o cache), a segunda volta é mais rápida por memória, não porque o tênis é melhor. Então a gente "apaga a memória" antes de cada volta, corre 10 vezes e tira a média. O desvio padrão diz se as voltas foram parecidas ou se variaram muito.

**Resultado em uma frase:** só o I1 ganhou com folga (2,71x nos Super Chats, com só +0,4 ms em 100 comentários). Os outros ganharam 5% a 11%, perto do desvio, porque com até 10 mil linhas as tabelas ocupam poucas páginas e o tempo é quase todo custo fixo. Sem índice o custo cresce com o tamanho da tabela; com índice, com o tamanho do resultado. O professor disse que a diferença aparece com centenas de milhares de linhas.

### 3.6 Visões

**Na linguagem da aula.** Visão é uma representação lógica de um subconjunto dos dados de uma ou várias tabelas; serve para **facilitar consultas complexas**, dar **independência dos dados** e restringir acesso (Aula 14). As nossas são **visões complexas** (várias tabelas, agrupamento), então não aceitam DML. O enunciado pede visões "para otimizar o desempenho de buscas", até 5, cada uma justificada.
- **Virtual:** guarda só a consulta; executa a cada uso; sempre atual.
- **Materializada:** guarda o resultado em disco, como uma tabela; leitura rápida, pode ter índice; só muda com `REFRESH`.
- **Critério do grupo:** cálculo caro e que tolera alguns minutos de atraso → materializada; cálculo barato ou que precisa estar sempre atual → virtual.

**Explicando do zero.** A visão virtual é uma pergunta salva no celular: toda vez que você toca, ela pergunta de novo e a resposta está sempre fresquinha. A materializada é um resumo impresso e colado na parede: ler é instantâneo, mas ele só muda quando alguém imprime de novo (o REFRESH). Vale imprimir o resumo quando calcular dá muito trabalho e ninguém liga se ele está alguns minutos velho, como um ranking.

| Visão | Tipo | Usada em | Dono no roteiro |
|---|---|---|---|
| V1 `vw_canal_info` | virtual | 3, 4 | João |
| V2 `mv_interacoes_video` | materializada | 2, 3 | Gabriel |
| V3 `mv_doacoes_canal` | materializada | 4, 7, 10, 11 | Davi |
| V4 `vw_membros_canal` | virtual | 9, 11 | Kayo |
| V5 `vw_faturamento_canal` | virtual | 11 | Lucas |

### 3.7 Triggers

**Na linguagem da aula.** Trigger é uma ação executada automaticamente quando ocorre um **evento** (INSERT, UPDATE, DELETE). Ao criar, define-se o **evento**, o **timing** (BEFORE ou AFTER) e o **nível** (ROW: uma vez por tupla; STATEMENT: uma vez por comando) (Aula 13). Todas as nossas são `FOR EACH ROW`, porque cada tupla muda um contador ou precisa do próprio número. BEFORE quando é preciso alterar o `NEW` ou recusar antes de gravar; AFTER quando a ação depende de a linha já ter passado nas constraints.

**Para que usamos:** (1) manter os **atributos derivados** `qtd_users` e `qtd_visualizacoes` (T1, T2) e bloquear a alteração manual deles (T1b, T2b); (2) gerar os **números sequenciais** que recomeçam por vídeo, por comentário ou por usuário e plataforma (T3, T4, T5); (3) regras que **nenhuma constraint consegue expressar**: forma de pagamento única (T6) e dono de canal ser streamer com conta na plataforma (T7).

**Explicando do zero.** Trigger é um alarme automático. Toda vez que alguém cria uma conta no YouTube, o alarme soma 1 no contador de usuários do YouTube, sem ninguém precisar lembrar. Outro alarme é o porteiro: se alguém tenta mudar esse contador na mão, ele barra. E outro dá a senha da fila: cada comentário de um vídeo recebe o próximo número, 1, 2, 3, como a senha do açougue.

### 3.8 Functions (PL/pgSQL)

**Na linguagem da aula.** PL/pgSQL é a linguagem procedural do PostgreSQL: mistura SQL com variáveis, condicionais e laços, em blocos `DECLARE / BEGIN / EXCEPTION / END` (Aula 13). Rodar a lógica dentro do banco **reduz o custo de comunicação** com a aplicação, em troca de um overhead no servidor. O professor pediu tudo como function, com os parâmetros de busca na assinatura e pelo menos uma polimórfica.
- **Consultas:** `RETURNS TABLE` + `RETURN QUERY`; filtro opcional com `DEFAULT NULL`; `k` como parâmetro nas top-k.
- **Polimorfismo:** sobrecarga nas consultas 5 e 12 (número ou nome).
- **Inserções:** validam antes e gravam tudo numa transação.

**Explicando do zero.** Uma function é uma receita com ingredientes variáveis. Em vez de reescrever a pergunta "top 10 canais que mais faturam" toda vez, você chama `consulta11_top_k_faturamento(10)`; quer o top 3, troca o número. Polimorfismo é a mesma receita aceitar ingredientes diferentes: você pode pedir os patrocínios da empresa pelo número dela ou pelo nome, e o banco entende qual versão usar.

### 3.9 Transações e concorrência

**Na linguagem da aula.** Transação é uma unidade lógica de processamento com as propriedades **ACID** (Aula 15). **Atomicidade** é o "tudo ou nada"; **isolamento** é cada transação funcionar como se estivesse sozinha, papel do controle de concorrência. Um problema clássico é a **atualização perdida**: duas transações leem o mesmo valor e uma sobrescreve a outra.
- Cada chamada de function é atômica: `inserir_streamer` grava usuário e passaporte juntos, ou nenhum.
- Nas triggers T3, T4 e T5, o `FOR UPDATE` trava a linha antes de ler o `MAX`. Sem isso, dois comentários simultâneos leriam o mesmo número.
- No `4_chamadas.sql`, as inserções de teste rodam em `BEGIN ... ROLLBACK`.

**Explicando do zero.** Transação é como um Pix: ou o dinheiro sai de uma conta e entra na outra, ou nada acontece. Nunca fica pela metade. O `FOR UPDATE` é a chave do banheiro: quem pega a chave usa, o próximo espera. Sem a chave, duas pessoas entrariam ao mesmo tempo e pegariam a mesma senha da fila.

### 3.10 Perguntas sobre o `1_ddl.sql` (todos)

**1. Por que a PK é numérica e não o `nick`?**
A PK vira um índice B+-tree. Inteiro ocupa menos espaço e é mais rápido de comparar que texto, então cabem mais chaves em cada nó e a árvore fica mais baixa (menos leituras de disco). As FKs que apontam para ela também ficam menores.

**2. Ao trocar a PK por uma artificial, o que vocês não podiam perder?**
A unicidade da chave original. Por isso o `nick` (e cada chave natural) virou `UNIQUE NOT NULL`. Sem isso, a troca permitiria dois usuários com o mesmo nick.

**3. Por que `GENERATED ALWAYS AS IDENTITY`?**
O banco gera o número sozinho e recusa valor informado na mão, o que evita conflito de ids (com `BY DEFAULT`, um INSERT manual poderia usar um número que a sequência ainda vai gerar).

**4. Por que `video` não usa (canal, título, data) como PK?**
Seriam 4 atributos repetidos em todas as tabelas que apontam para vídeo. Com a chave artificial, essas FKs têm 1 atributo. A chave natural continua como `UNIQUE (id_canal, titulo, dataH)`.

**5. E comentário e doação?**
A chave do modelo relacional tinha 6 atributos no comentário e 7 na doação. Viraram `id_comentario` e `id_doacao`; o sequencial ficou em `UNIQUE (id_video, seq)` e `UNIQUE (id_comentario, seq_doacao)`.

**6. Por que algumas PKs continuaram compostas?**
Têm só 2 atributos numéricos, como `plataforma_usuario (nro_plataforma, nro_usuario)` e `inscricao (id_canal, nro_usuario)`. O professor aceitou chave composta pequena e pouco frequente.

**7. Por que `pais.ddi` não virou chave artificial?**
O DDI já é número, curto e estável. Trocar não ganharia nada.

**8. Por que o tamanho do tipo muda de tabela para tabela?**
Pela cardinalidade esperada: `SMALLINT` em moeda e DDI (poucas centenas), `INTEGER` em empresa, plataforma e canal, `BIGINT` em usuário, vídeo, comentário e doação, que crescem sem parar.

**9. Por que ENUM em tipo de canal, status e bandeira?**
O domínio é fechado e quase nunca muda. O ENUM ocupa 4 bytes, recusa valor fora da lista e documenta os valores no próprio tipo.

**10. Por que o nível de membro tem `CHECK (nivel BETWEEN 1 AND 5)` no banco?**
É regra de negócio estável; o próprio professor usou esse exemplo para dizer que regra estável vai no banco.

**11. Por que não validam o formato da data no banco?**
Formato é validação de front-end, como o professor orientou. Colocar no banco só deixaria a inserção mais pesada.

**12. Por que `NUMERIC` e não `FLOAT` para dinheiro?**
`FLOAT` arredonda em binário (0,1 + 0,2 não dá exatamente 0,3). Dinheiro precisa de precisão exata.

**13. Como vocês escolheram entre `RESTRICT` e `CASCADE`?**
`RESTRICT` onde apagar o pai faria sumir dado importante: doação (registro financeiro), canal com vídeos, país com usuários, empresa com patrocínio vigente. `CASCADE` onde o filho não existe sem o pai: níveis do canal, participações, contas na plataforma, subclasses da doação, passaporte.

**14. E o `ON UPDATE`?**
`RESTRICT` em todas: as PKs são identity ou DDI e não mudam.

**15. Como modelaram as 4 formas de pagamento?**
Uma tabela por subclasse (`bitcoin`, `paypal`, `cartao_credito`, `mecanismo_plat`), cada uma só com os seus atributos e com a PK de `doacao` como PK e FK. A regra de "uma forma só" é a trigger T6.

**16. Em que moeda está o valor da doação?**
Na moeda do país de residência de quem doou. A conversão para dólar usa `conversao.fator_conver` e acontece na `mv_doacoes_canal`. O professor aceitou converter na consulta ou guardar numa moeda de referência, desde que justificado.

**17. Por que não existe tabela `streamer`?**
O professor disse para não criar tabela fora do modelo. Streamer é o usuário que tem passaporte em `streamer_pais`.

**18. Por que `gif` é texto e não o arquivo?**
Guardar o arquivo (`BYTEA`) incha a tabela e os backups. O arquivo fica num storage e o banco guarda o caminho.

### 3.11 Núcleo comum (perguntas que qualquer um pode receber)

**1. Como vocês escolheram os índices?**
Pela carga: operação frequente, pesada e com predicado seletivo. A medição só conferiu. Não indexamos tabela pequena, coluna que já é PK ou UNIQUE, nem consulta sem filtro.

**2. Hash ou B+-tree, qual a diferença?**
Hash só serve igualdade; B+-tree serve igualdade, intervalo e ordenação. Nas tabelas-base, as buscas indexadas são de igualdade (hash); nas visões materializadas, B+-tree.

**3. Qual índice deu ganho claro?**
Só o I1 (2,71x nos Super Chats). Os outros ganharam pouco porque as tabelas têm até 10 mil linhas.

**4. Virtual × materializada?**
Caro e tolera atraso → materializada (`mv_interacoes_video` e `mv_doacoes_canal`). Barato ou precisa estar atual → virtual (as outras 3).

**5. Por que trigger e não DCL/DDL para bloquear os atributos derivados?**
REVOKE não barra o dono da tabela; coluna gerada não lê outra tabela.

**6. Por que a consulta 11 é mensal e a 12 tem 3 agrupamentos?**
Não se soma dia com mês; membros já é mensal. A 12 analisa streamer, canal e streamer + canal, como o professor pediu.

**7. Onde está o polimorfismo?**
Consultas 5 e 12: mesma function por número (`INTEGER`) ou por nome (`VARCHAR`).

**8. Como a doação em moeda local vira dólar?**
Na `mv_doacoes_canal`, com `conversao.fator_conver` do país de quem doou.

---

## 4. Partes individuais

Cada parte tem: o que é cada item e por que foi feito assim, perguntas com resposta curta, e "Onde ele pode apertar" (o que o professor pode achar ao rodar o código).

### 4.1 Kayo — Super Chat e membros

**Itens:** I1 `comentario(nro_usuario)` · V4 `vw_membros_canal` · T4 `trg_doacao_seq` · T5 `trg_mecanismo_plat_seq` · consulta 9 · `inserir_usuario`, `inserir_streamer`, `inserir_doacao_base`, `inserir_doacao_plataforma`.

**Como os itens se ligam:** cada Super Chat entra por `inserir_doacao_plataforma`, que chama `inserir_doacao_base` (a T4 numera a doação dentro do comentário) e grava em `mecanismo_plat` (a T5 numera o Super Chat do usuário na plataforma). A T5 procura os comentários do usuário, e é isso que o I1 acelera. A V4 e a consulta 9 tratam da outra receita "direta" do canal: os membros.

**Perguntas e respostas**

**1. Para que serve o I1 e por que ele é o mais importante?**
A T5 procura as doações anteriores do usuário filtrando `comentario.nro_usuario`. Sem índice, ela lê os 9.800 comentários a cada Super Chat, que é a escrita mais frequente numa live. Com o índice, inserir 100 Super Chats ficou 2,71 vezes mais rápido (40,5 → 15,0 ms).

**2. Por que hash no I1?**
A busca é só por igualdade (`nro_usuario = valor`), que é o caso ideal do hash: ele calcula o bucket direto. Não há busca por intervalo nem ordenação nessa coluna.

**3. Qual o custo do I1?**
Todo comentário novo também grava no índice. Medimos: inserir 100 comentários foi de 4,05 para 4,45 ms (+0,4 ms), bem menos que os 25 ms economizados em 100 Super Chats.

**4. O que é o sequencial do Super Chat (T5)?**
Premissa nossa: o 5º Super Chat que um usuário faz no YouTube recebe 5. O enunciado diz que depende do usuário, do comentário e da plataforma; o comentário já determina quem comentou e em que plataforma. O professor respondeu que "depende da chave que vocês criaram".

**5. Como a T5 acha o usuário e a plataforma?**
Pelo caminho `doacao → comentario → video → canal`. Depois calcula `MAX(seq_plataforma) + 1` entre as doações por plataforma desse usuário naquela plataforma.

**6. Por que a T5 trava a linha do usuário com `FOR UPDATE`?**
Para dois Super Chats simultâneos do mesmo usuário não lerem o mesmo `MAX` e ganharem o mesmo número. O segundo espera o primeiro terminar.

**7. O que a T4 faz?**
Gera `seq_doacao`, o número da doação dentro do comentário (1, 2, 3...). Trava a linha do comentário pelo mesmo motivo, e o `MAX` usa o índice do `UNIQUE (id_comentario, seq_doacao)`.

**8. Por que BEFORE nas duas?**
O número precisa estar no `NEW` antes de a linha ser gravada.

**9. Por que a V4 é virtual?**
Junta só `inscricao` e `nivel_canal` pela chave `(id_canal, nivel)`, que é a PK de `nivel_canal` e já tem índice, então é barata. E membros entram e saem todo dia: a visão precisa estar sempre atual.

**10. O que a consulta 9 responde?**
Os k canais que mais recebem de membros por mês, com a quantidade de membros. Lê a V4, ordena pelo total e corta em k. `qtd_membros` mostra se o total vem de muitos membros baratos ou de poucos caros.

**11. A consulta 9 usa índice?**
Não precisa: ela soma todas as inscrições e ordena; não há predicado seletivo.

**12. Por que `inserir_streamer` chama `inserir_usuario`?**
Streamer é um usuário com passaporte. A function reaproveita a validação do usuário e grava os dois na mesma transação: se o passaporte falhar, o usuário também é desfeito.

**13. Por que `inserir_doacao_base` não deve ser chamada sozinha?**
Ela grava só a superclasse. Uma doação sem forma de pagamento ficaria incompleta; por isso as 4 functions de forma chamam a base e gravam a subclasse junto.

**14. Por que `inserir_doacao_plataforma` grava `seq_plataforma = 0`?**
Só para satisfazer o `NOT NULL`; a T5 (BEFORE INSERT) troca pelo número certo.

**Onde ele pode apertar**

**"A T5 não é cara?"**
Ela junta 5 tabelas a cada Super Chat. Com o I1, a parte dos comentários vai pelo índice. No EXPLAIN atual a tabela `doacao` ainda é lida inteira na junção (5.600 linhas, barato neste volume); com mais dados, o planejador passaria a usar o índice do `UNIQUE (id_comentario, seq_doacao)`.

**"Se apagarem a última doação, o número se repete?"**
Sim, o próximo reaproveita o número (LIMITAÇÃO escrita no código, mesma da T3).

**"A trava faz diferença no trabalho?"**
Na carga só uma sessão insere, então ela nunca espera. Ela existe para o caso real de vários usuários ao mesmo tempo.

### 4.2 Gabriel — Comentários e interações

**Itens:** I2 `mv_interacoes_video(id_canal)` · V2 `mv_interacoes_video` · T2/T2b (visualizações do canal) · T3 `trg_comentario_seq` · consultas 2 e 3 · padrões das consultas (linhas 602–620) · `inserir_video`, `inserir_comentario`.

**Como os itens se ligam:** `inserir_video` grava o vídeo e a T2 soma as visualizações dele no canal. `inserir_comentario` grava o comentário e a T3 dá o número dele dentro do vídeo. A V2 conta os comentários de cada vídeo; as consultas 2 e 3 leem a V2; o I2 acelera essas consultas quando filtradas.

**Perguntas e respostas**

**1. Por que a V2 é materializada?**
Ela conta comentários online, offline e totais de cada vídeo agrupando `comentario`, a maior tabela do banco. Sem a visão, cada chamada das consultas 2 e 3 refaria esse agrupamento. Um ranking de interações pode ficar alguns minutos atrasado.

**2. Por que a V2 usa LEFT JOIN?**
Para vídeo sem comentário entrar com 0. Sem isso, a média de interações por vídeo da consulta 3 sairia maior do que é.

**3. Um comentário novo aparece na consulta 2?**
Só depois do próximo `REFRESH`. É o preço da materializada, aceito porque o ranking tolera atraso.

**4. Para que serve o I2?**
A consulta 2 filtrada por canal procura "os vídeos do canal X" na V2. Sem índice, lê a visão inteira (uma linha por vídeo, 9.500) para achar os poucos daquele canal. Na consulta 3 filtrada por streamer, o I2 acha os vídeos de cada canal do streamer.

**5. Dá para criar índice em visão?**
Só na materializada, porque ela está gravada em disco como uma tabela. O índice é reconstruído junto a cada REFRESH.

**6. Por que B+-tree e não hash no I2?**
A busca é por igualdade, então hash também serviria (a medição empatou). Escolhemos B+-tree porque o `id_canal` da visão também é usado em junção, e a B+-tree entrega os dados ordenados, o que permite merge join.

**7. O que a consulta 2 responde e por que o `WHERE qtd_total > 0`?**
Os vídeos com mais comentários (online, offline e total). Vídeo sem comentário iria para o fim da lista com zero e não responde a pergunta.

**8. O que a consulta 3 responde?**
Os canais com mais interações (comentários online + offline de todos os vídeos) e a média por vídeo, contando vídeos sem comentário. A coluna `qtd_videos` mostra o divisor.

**9. Como funciona o filtro opcional?**
Parâmetro com `DEFAULT NULL` e a condição `(p IS NULL OR coluna = p)`. Sem parâmetro lista tudo; com parâmetro filtra. Uma consulta só para os dois casos.

**10. E o índice continua sendo usado com esse `OR`?**
Sim. O PL/pgSQL monta o plano com o valor real do parâmetro, então a condição vira `coluna = 1839` e o índice entra. Conferido com `auto_explain`, inclusive na 7ª chamada seguida.

**11. Para que o `#variable_conflict use_column`?**
Os nomes das colunas de saída coincidem com colunas das tabelas (ex.: `id_canal`). A diretiva diz ao PL/pgSQL que, dentro do SQL, o nome é a coluna da tabela.

**12. O que a T2 faz?**
Mantém `canal.qtd_visualizacoes` igual à soma de `video.visu_total`. A cada INSERT, DELETE ou UPDATE de vídeo, tira o valor antigo e soma o novo, sem recalcular a soma inteira.

**13. E se um vídeo mudar de canal?**
A T2 tira o `visu_total` do canal antigo e soma no canal novo.

**14. Por que a T2b existe e como ela não bloqueia a T2?**
Ela bloqueia o UPDATE manual de `qtd_visualizacoes`. Usa `pg_trigger_depth()`: o UPDATE do usuário roda na profundidade 1 e é barrado; o da T2 roda na profundidade 2 e passa.

**15. Por que o `seq` do comentário é trigger e não `SEQUENCE`?**
A `SEQUENCE` é global; o enunciado pede um número que recomeça em cada vídeo. A T3 calcula `MAX(seq) + 1` do vídeo, com o índice do `UNIQUE (id_video, seq)` (o EXPLAIN mostra `Index Only Scan Backward`).

**16. E dois comentários simultâneos no mesmo vídeo?**
O `FOR UPDATE` trava a linha do vídeo; o segundo espera e pega o número seguinte. Sem a trava, os dois leriam o mesmo `MAX` e o segundo cairia no `UNIQUE`.

**17. Por que a T3 proíbe mudar `seq` ou `id_video` num UPDATE?**
O `UNIQUE` não barra um buraco na contagem (trocar o 3 por 7) nem um comentário mudar de vídeo levando o número antigo.

**18. Por que `inserir_comentario` passa `seq = 0`?**
Só para o `NOT NULL`; a T3 troca pelo número certo antes de gravar.

**Onde ele pode apertar**

**"Na consulta 3, o I2 ajuda?"**
Na medição, o I2 sozinho deu 0,99x na consulta 3; quem ajudou foi o I5 (1,08x, do João). No plano, os dois são usados juntos: o I5 acha os canais do streamer, o I2 acha os vídeos de cada canal.

**"Se apagarem o último comentário, o número se repete?"**
Sim (LIMITAÇÃO escrita no código).

**"Por que materializar se a consulta já é rápida?"**
Com 9.800 comentários tudo é rápido. A decisão é pelo custo que cresce com a tabela de comentários, a que mais cresce no sistema.

### 4.3 Lucas — Plataforma, patrocínio e faturamento

**Itens:** I3 `inscricao(nro_usuario)` · V5 `vw_faturamento_canal` · T1/T1b (`qtd_users`) · consultas 6, 8 e 11 · `valida_k` · `inserir_conta_plataforma`.

**Como os itens se ligam:** `inserir_conta_plataforma` cria a conta e a T1 soma 1 em `qtd_users`. As consultas 6, 8 e 11 tratam do dinheiro de membros e patrocínio; a 11 junta as três receitas pela V5. O I3 acelera a consulta 6 filtrada por usuário.

**Perguntas e respostas**

**1. Por que guardar `qtd_users` se dá para contar?**
O enunciado traz o atributo no modelo e o professor disse que a coluna é obrigatória. Ler o total é muito mais frequente que criar conta; guardando, a leitura é imediata e só a escrita paga um UPDATE de uma linha.

**2. Como a T1 mantém o valor?**
É AFTER INSERT, DELETE e UPDATE da plataforma em `plataforma_usuario`: soma 1, tira 1, ou tira de uma plataforma e soma na outra quando a conta muda de plataforma.

**3. Por que AFTER?**
O contador só deve contar contas que já passaram em todas as constraints.

**4. Como bloquearam a alteração manual (T1b)?**
Trigger BEFORE UPDATE em `plataforma`: se o valor mudar, levanta erro. No INSERT, força 0.

**5. Por que trigger e não REVOKE (DCL) ou coluna gerada (DDL)?**
O professor disse que dois dos três jeitos dão problema. O REVOKE não impede o dono da tabela de alterar. A coluna gerada só lê a própria linha, e o valor depende de outra tabela.

**6. Se a T1 faz UPDATE em `plataforma`, por que a T1b não a bloqueia?**
`pg_trigger_depth()`: o UPDATE do usuário roda na profundidade 1 e é barrado; o da T1 roda na profundidade 2 e passa.

**7. Para que serve o I3?**
A consulta 6 filtrada por usuário procura as inscrições dele. A PK de `inscricao` é `(id_canal, nro_usuario)` e começa por `id_canal`, então a B+-tree da PK não serve para buscar só pelo usuário.

**8. Por que hash no I3?**
A busca é só por igualdade (`nro_usuario = valor`). Medido: 2,90 → 2,62 ms (1,11x).

**9. O que a consulta 6 responde?**
De quantos canais cada usuário é membro e quanto paga por mês (a soma do valor do nível de cada inscrição).

**10. O que a consulta 8 responde?**
Os k canais que mais recebem patrocínio, com o total e a quantidade de patrocinadores (mostra se vem de uma empresa ou de várias). O patrocínio já é guardado em dólar.

**11. Para que a `valida_k`?**
`LIMIT NULL` não limita (devolveria tudo), `k = 0` devolveria lista vazia sem aviso e `k` negativo daria erro confuso. Ela barra os três com mensagem clara.

**12. Por que a consulta 11 é mensal?**
Não dá para somar períodos diferentes ("não tem como somar dia com mês e com ano", disse o professor). O mês é a periodicidade natural da mensalidade de membro. Dia seria fino demais; ano exigiria anualizar mensalidades que mudam.

**13. Como o patrocínio e as doações viram mensais?**
O patrocínio vigente é tratado como valor mensal (o sistema guarda só o contrato atual, sem período). As doações entram pela média mensal da `mv_doacoes_canal`: total em dólar dividido pelo número de meses entre a primeira e a última doação, contando os dois.

**14. Por que a V5 é virtual?**
Ela só soma resultados já agregados: patrocínio (tabela pequena), V4 (barata) e V3 (já materializada). Materializar duplicaria dados e criaria mais um REFRESH.

**15. Por que as três receitas aparecem separadas na saída?**
Para mostrar de onde vem o dinheiro e conferir que o total é a soma delas.

**16. A consulta 11 usa índice?**
Não: ela lê todos os canais, junta as três receitas e ordena; o EXPLAIN mostra `Seq Scan` + `Hash Join`. Sem predicado seletivo, ler tudo é o mais barato.

**Onde ele pode apertar**

**"Patrocínio é mensal mesmo?"**
É premissa nossa, escrita no código: o enunciado não dá o período do patrocínio e o sistema não guarda histórico.

**"A média mensal de doação não é aproximação?"**
É. Doação não tem periodicidade; convertemos para o mês pela média do período em que o canal recebeu doações.

**"Por que o I3 ganhou tão pouco?"**
Com 8.000 inscrições a tabela ocupa poucas páginas. O índice evita ler a tabela inteira; o ganho cresce com o volume.

### 4.4 Davi — Doações

**Itens:** I4 `mv_doacoes_canal(id_canal)` · V3 `mv_doacoes_canal` e `atualizar_visoes_materializadas()` · T6 (forma de pagamento única) · consultas 4, 7 e 10 · `inserir_doacao_bitcoin`, `inserir_doacao_paypal`, `inserir_doacao_cartao`.

**Como os itens se ligam:** as functions gravam a doação com a forma de pagamento; a T6 garante uma forma só. A V3 junta e converte todas as doações para dólar; as consultas 4, 7 e 10 leem a V3; o I4 acelera a consulta 7 filtrada.

**Perguntas e respostas**

**1. Por que a V3 é materializada?**
É o cálculo mais caro do trabalho: junta 6 tabelas (doação, comentário e vídeo para chegar ao canal; usuário, país e conversão para chegar à moeda) e converte cada doação para dólar. Quatro consultas (4, 7, 10 e 11) usam o mesmo resultado, então vale calcular uma vez.

**2. Onde acontece a conversão de moeda e por que lá?**
Na V3, uma vez. A doação fica gravada na moeda de quem doou (o valor original não se perde) e as consultas leem o total já em dólar.

**3. Doação recusada entra?**
Não: só `recebido` e `lido`, porque a recusada não gerou dinheiro.

**4. Como a V3 é atualizada?**
Pela `atualizar_visoes_materializadas()`, que faz `REFRESH` das duas materializadas no fim da carga ou por um agendador.

**5. Por que não atualizar por trigger a cada doação?**
O `REFRESH` recalcula a visão inteira; a cada doação, custaria mais do que não ter a visão.

**6. Para que serve o I4?**
A consulta 7 filtrada por canal ("quanto o canal X recebeu") acha a linha do canal direto na V3, em vez de ler a visão inteira. É a consulta que a página do canal chamaria a cada acesso.

**7. O I4 ajuda a consulta 11?**
Não. A 11 junta a visão inteira com `canal`, sem filtro, e o otimizador escolhe `Seq Scan` + `Hash Join`, mais barato quando se lê tudo. O comentário do código diz isso.

**8. Por que B+-tree e não hash no I4?**
A busca da consulta 7 é por igualdade, então hash também serviria (a medição empatou). B+-tree é o padrão e entrega o `id_canal` ordenado, o que permite merge join se o volume crescer.

**9. O que a consulta 4 responde?**
Os canais pelo valor médio das doações por comentário, com a quantidade e o total em dólar. O divisor é o número de comentários que trouxeram doação: JOIN normal, como o professor pediu.

**10. A consulta 4 filtrada por plataforma usa índice?**
Não, e está certo: uma plataforma tem cerca de 1/4 dos canais. Com predicado pouco seletivo, ler a tabela inteira é mais barato (o EXPLAIN mostra `Seq Scan` em `canal`).

**11. O que as consultas 7 e 10 respondem?**
A 7: os canais que já receberam doação e a soma, com filtro opcional de canal. A 10: os k canais que mais receberam. As duas leem a V3; `qtd_doacoes` mostra se são poucas doações grandes ou muitas pequenas.

**12. Como garantem que a doação não é bitcoin e paypal ao mesmo tempo?**
Com a T6: antes de inserir numa subtabela, ela verifica se o `id_doacao` já está nas outras três e, se estiver, dá erro.

**13. Por que trigger e não constraint?**
A PK de cada subtabela só impede repetir dentro dela; PK, FK e CHECK não olham outra tabela. `TG_TABLE_NAME` diz qual subtabela disparou, então uma function serve as 4 triggers.

**14. A T6 garante que toda doação tem uma forma?**
Não: garante no máximo uma. O "pelo menos uma" depende das functions `inserir_doacao_*`, que gravam doação e subclasse juntas. Um INSERT direto em `doacao` fica sem forma (LIMITAÇÃO escrita no código).

**15. Se a gravação da subclasse falhar, a doação fica gravada?**
Não. A function é uma transação: `inserir_doacao_cartao` chama a base e grava o cartão; se o cartão falhar, a doação também é desfeita.

**Onde ele pode apertar**

**"O relatório diz que o I4 serve a junção da consulta 11."**
O código já foi corrigido; o relatório precisa da mesma correção. Resposta: serve a consulta 7 filtrada; na 11 o otimizador prefere leitura sequencial.

**"A materializada fica desatualizada."**
Sim, até o próximo REFRESH. Doações para ranking toleram esse atraso.

**"Por que guardar na moeda original e não em dólar?"**
Para não perder o valor real da doação e não depender da cotação do dia da gravação. A conversão é feita uma vez na V3.

### 4.5 João — Canais, streamers e polimorfismo

**Itens:** I5 `canal(nro_streamer)` · V1 `vw_canal_info` · T7 (dono de canal) e a trigger de participante · consultas 1, 5 e 12 · `inserir_canal`.

**Como os itens se ligam:** `inserir_canal` grava o canal e a T7 confere o dono. O I5 acha os canais de um streamer. A V1 dá nome legível aos canais nas consultas. As consultas 5 e 12 são as polimórficas; a 12 depende da T7 para não perder canal.

**Perguntas e respostas**

**1. Para que serve o I5?**
A consulta 3 filtrada por streamer precisa dos canais dele. Sem índice, varre os 3.000 canais; com o I5, acha direto (1,08x medido). No plano, ele trabalha junto com o I2.

**2. Por que hash no I5?**
A busca é só por igualdade (`nro_streamer = valor`).

**3. Por que a V1 é virtual?**
Junta canal, plataforma e usuário, e cada junção acha a linha pela chave primária, que já tem índice: é barata. E um canal novo precisa aparecer na hora.

**4. Para que serve a V1?**
Quase todas as consultas mostram o canal com o nome da plataforma e o nick do dono. A V1 escreve essa junção uma vez só (é usada nas consultas 3 e 4).

**5. O que a T7 valida e por que no banco?**
Que o dono do canal é streamer (tem passaporte em `streamer_pais`) e tem conta na plataforma do canal. É regra de negócio estável, e o professor disse que regra estável vai no banco.

**6. Participante de vídeo também precisa de conta na plataforma?**
Não, só precisa ser streamer. O enunciado diz que o vídeo pode ter "mais streamers do que apenas o dono do canal"; a exigência de conta é só para o dono.

**7. O que define um streamer?**
Ter passaporte em `streamer_pais`. Não criamos tabela `streamer` porque o professor disse para não criar tabela fora do modelo.

**8. Por que `inserir_canal` valida a plataforma se a FK já barra?**
Orientação do professor: validar antes e dar mensagem clara, em vez do erro genérico de FK. A T7 faz o resto da validação.

**9. O que a consulta 1 responde?**
Os streamers com mais vídeos publicados (vídeos dos canais de que ele é dono), com o total de vídeos e a soma das visualizações; filtro opcional de plataforma.

**10. Onde está o polimorfismo e como o Postgres escolhe a versão?**
Nas consultas 5 e 12, que têm duas versões com o mesmo nome. O Postgres escolhe pelo tipo do argumento: `consulta5_patrocinios(1934)` usa a de `INTEGER`; `consulta5_patrocinios('Anderson-Riley Corp.')` usa a de `VARCHAR`.

**11. A versão por nome repete a consulta?**
Não: acha o número pelo nome, dá erro se não existir e chama a versão por número. A consulta fica escrita num lugar só.

**12. Por que function e não procedure?**
O professor pediu tudo como function. A function devolve linhas (`RETURNS TABLE`), então dá para usá-la num `SELECT`.

**13. Quais são os 3 agrupamentos da consulta 12?**
(1) Streamers com conta na plataforma. (2) Canais da plataforma. (3) Streamers que também têm canal nela, com a média de canais por streamer com canal. Tudo numa consulta só, como o professor pediu.

**14. Como a 12 junta isso sem contar errado?**
LEFT JOIN em `canal` pelo par (plataforma, dono): cada conta só encontra os próprios canais, então a junção não multiplica linhas. O LEFT mantém o streamer sem canal e a plataforma sem streamer (com zero). Nenhum canal fica de fora porque a T7 garante que o dono tem conta na plataforma.

**15. Por que `COUNT(DISTINCT ...)` na 12?**
Um streamer com 3 canais aparece em 3 linhas da junção; o DISTINCT conta a pessoa uma vez.

**16. Em que ordem a 12 classifica?**
Streamers, depois canais (o "E" do enunciado), e streamers com canal como desempate.

**17. A consulta 12 usa índice?**
Não: ela conta todas as plataformas, então lê as tabelas inteiras (`Seq Scan` + `Hash Join`). Índice só ajuda com predicado seletivo.

**Onde ele pode apertar**

**"Se o passaporte do dono for apagado depois?"**
A T7 não pega: ela só valida ao inserir ou atualizar o canal (LIMITAÇÃO escrita no código).

**"A consulta 12 é uma consulta só?"**
Sim: uma function, um SELECT, três contagens. As duas versões são só a sobrecarga (número ou nome).

**"Explica a 12 no papel."**
Treine desenhar: plataforma → contas de streamers → canais desse streamer naquela plataforma, e de onde sai cada COUNT.

---

## 5. Como estudar e ensaiar

1. Leia a parte comum (seção 3) inteira. Ela explica o projeto todo e o porquê de cada decisão.
2. Leia no `sql/2_plpgsql.sql` os itens da sua parte, pelas linhas da tabela da seção 2, com os comentários.
3. Cubra as respostas da sua parte e responda em voz alta. A resposta escrita é a versão curta; na prova, diga com as suas palavras.
4. Leia "Onde ele pode apertar": é ali que o professor procura erro ou decisão não pensada.
5. Rode `1_ddl.sql`, `2_plpgsql.sql` e `3_dados.sql` num banco vazio e chame as functions da sua parte com `EXPLAIN ANALYZE`.
6. **Ensaio:** cada um faz 3 perguntas da própria parte a um colega e responde 3 da parte de outro. Todos treinam rodar os arquivos do zero, porque o professor roda o código na hora.
