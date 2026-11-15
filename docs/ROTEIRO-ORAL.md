# Roteiro para a prova oral de BD2

**Como será (palavras do Prof. Bedo na consultoria 2):** não há apresentação. Ele pega o código, roda, e faz perguntas a cada membro, "como se fosse uma prova oral". Procura erros, decisões que não estão claras e coisas em que o grupo não pensou. Ele também disse que todo mundo tem que responder perguntas.

**Premissa do grupo:** ele pergunta a cada um qual parte fez e foca nela. Por isso cada pessoa é dona de um tema. O núcleo comum, no fim, é um seguro caso ele fuja disso.

| Quem | Tema |
|---|---|
| **Davi** | Modelo físico (DDL) e povoamento |
| **Lucas** | Triggers |
| **João** | Functions: consultas 1 a 7, inserções e polimorfismo |
| **Gabriel** | Visões e consultas 8 a 12 |
| **Kayo** | Índices e medição de desempenho |

Arquivos: `sql/1_ddl.sql`, `sql/2_plpgsql.sql` (Seção 1 = triggers, inserções e visões; Seção 2 = consultas; Seção 3 = índices), `sql/3_dados.sql`, `sql/4_chamadas.sql`, `medicoes/`.

**Como usar este arquivo:** cada seção tem (1) o que estudar, (2) as perguntas que ele pode fazer, com uma resposta-guia tirada do nosso código, e (3) os pontos fracos. A resposta-guia serve para você conferir se entendeu. Na prova, responda com as suas palavras. Onde a resposta-guia diz "confirme", o código não deixa o motivo explícito e a pessoa responsável deve checar.

**Antes de estudar:** rode `sql/1_ddl.sql`, `2_plpgsql.sql`, `3_dados.sql` e `4_chamadas.sql`, nessa ordem, num banco vazio (pgAdmin). Estudar com o banco rodando é bem mais fácil.

---

## 1. Davi — Modelo físico (DDL) e povoamento

**Arquivos:** `sql/1_ddl.sql` inteiro, `sql/3_dados.sql` (só o cabeçalho), `dev/gerar_povoamento.py` (cabeçalho e a lista de volumes).

**Roteiro de estudo**
1. Leia o comentário "Decisões gerais" no topo do `1_ddl.sql`. Ele resume quase tudo.
2. Para cada tabela, saiba responder: qual é a PK, qual era a chave natural, onde foi parar a unicidade.
3. Para cada FK, saiba dizer se é `RESTRICT` ou `CASCADE` e por quê.
4. Leia a Consultoria 1 (design físico) e o enunciado.
5. Leia o cabeçalho de `3_dados.sql` e os volumes em `gerar_povoamento.py`.

**Perguntas possíveis**
1. **Por que as chaves primárias são numéricas e não strings?** A PK vira um índice B+-tree. Inteiro é mais barato de comparar e a chave fica menor, então cabem mais entradas por nó e a árvore fica mais baixa. A antiga chave natural (`nick`, `nome`) virou `UNIQUE NOT NULL`, para não perder a unicidade.
2. **O que é `GENERATED ALWAYS AS IDENTITY` e por que não `SERIAL`?** O banco gera o valor e rejeita inserção manual, o que evita conflito de ids. (Confirme a diferença para `SERIAL` antes da prova.)
3. **Como vocês trataram chaves compostas?** As que passavam de 2 atributos viraram chave artificial: `video` (4 atributos viram 1), `comentario` (6) e `doacao` (7). As de 2 atributos ficaram compostas, por exemplo `plataforma_usuario` e `patrocinio`.
4. **Por que `pais.ddi` não tem chave artificial?** O DDI já é numérico, estável e curto (`SMALLINT`).
5. **Por que ENUM em `tipo_canal`, `status_doacao` e `bandeira_cartao`?** O domínio é fechado e quase não muda. O ENUM ocupa 4 bytes, rejeita valor fora da lista e documenta o domínio.
6. **Como escolheram `ON DELETE`?** `RESTRICT` onde apagar o pai destruiria dado importante: doação (registro financeiro), canal com vídeos, país com usuários. `CASCADE` onde o filho não existe sem o pai: `nivel_canal`, `participa`, subclasses de doação. `ON UPDATE RESTRICT` em todas, porque as PKs são identity e não mudam.
7. **Como modelaram a especialização de doação?** Uma tabela por subclasse (`bitcoin`, `paypal`, `cartao_credito`, `mecanismo_plat`), com a PK da superclasse como PK e FK. A disjunção é garantida por trigger (T6, tema do Lucas).
8. **Por que o nível de membro tem `CHECK (nivel BETWEEN 1 AND 5)` no banco?** É regra de negócio estável. O professor disse que regra estável vai no banco e regra mutável vai no back-end.
9. **Por que a data não é validada no banco?** O formato é validação de front-end (orientação do professor).
10. **Em que moeda está o valor da doação?** Na moeda do país de residência de quem doou. As consultas convertem para dólar com `conversao.fator_conver`. O professor aceitou as duas formas (converter na consulta ou guardar numa moeda de referência), desde que justificada.
11. **Por que `NUMERIC` e não `FLOAT` para dinheiro?** Precisão exata.
12. **Por que `gif` é `VARCHAR` e não `BYTEA`?** O arquivo fica num storage e o banco guarda só a referência. Guardar o arquivo incha a tabela e os backups.
13. **Como foi o povoamento e por que a distribuição importa?** Gerado com Faker, semente 2026. O valor dos dados não importa, a distribuição sim: cauda longa (poucos canais com muito público e doação), porque distribuição uniforme distorce a seletividade dos índices.
14. **Por que só até 10 mil linhas?** O enunciado limita cada tabela a 1.000–10.000 tuplas. O professor disse na consultoria 2 que 10 mil é pouco para ver desempenho e que "algumas centenas de milhares" seria razoável. **O grupo ainda não decidiu como tratar isso: combinem a resposta antes.**
15. **O que é fictício nos dados?** A cauda de países, moedas e plataformas (só o núcleo é real) e a densidade de doações, porque as 4 formas de pagamento precisam de pelo menos 1.000 linhas cada.

**Pontos fracos para ensaiar:** a pergunta 14 (volume), e dizer com clareza que `qtd_users` e `qtd_visualizacoes` são os únicos atributos derivados guardados.

---

## 2. Lucas — Triggers

**Arquivos:** `sql/2_plpgsql.sql`, Parte 1 da Seção 1 (T1, T1b, T2, T2b, T3, T4, T5, T6, T7 e a de participante).

**Roteiro de estudo**
1. Slides da Aula 13 (PL/pgSQL e triggers).
2. Para cada trigger, escreva em uma linha: tabela, momento (BEFORE/AFTER), eventos, o que faz.
3. Estude `pg_trigger_depth()` na T1b e na T2b.
4. Estude o motivo do `FOR UPDATE` na T3, T4 e T5.
5. Rode as inserções de `4_chamadas.sql` e tente provocar o erro de cada trigger.

**Perguntas possíveis**
1. **Por que existem `qtd_users` e `qtd_visualizacoes` armazenados, se podem ser calculados?** O enunciado pede os atributos, e ler o total é muito mais frequente do que criar contas ou vídeos. A trigger mantém o valor igual ao real.
2. **Por que trigger para bloquear a alteração manual, e não DCL ou DDL?** O professor disse que há três caminhos (DCL, trigger, DDL) e que dois dão problema. No nosso caso: DCL (`REVOKE`) também barraria a própria trigger que atualiza o valor, e coluna gerada (DDL) só enxerga a própria linha, não consegue contar linhas de outra tabela. (Confirme com o comentário da T1b e com a linha do relatório. **Essa regra veio da consultoria 2, não do enunciado: cite isso.**)
3. **Como a T1b sabe se o UPDATE é do usuário ou da T1?** Com `pg_trigger_depth()`: 1 é UPDATE direto do usuário, 2 é o UPDATE feito de dentro da T1.
4. **Por que T1 é AFTER e T1b é BEFORE?** A T1 só deve contar contas que já passaram nas constraints, então roda depois. A T1b precisa poder rejeitar (ou zerar no INSERT) antes de gravar.
5. **O que a T1 faz num UPDATE que muda a conta de plataforma?** Tira 1 da plataforma antiga e soma 1 na nova.
6. **A T2 recalcula a soma de todos os vídeos?** Não. Soma o delta: subtrai o `visu_total` antigo e soma o novo. Trata também DELETE e a troca de canal.
7. **Por que `comentario.seq` é trigger e não `SEQUENCE`?** `SEQUENCE` é global e a contagem aqui recomeça em cada vídeo.
8. **Para que serve o `FOR UPDATE` na T3?** Serializa inserts concorrentes no mesmo vídeo. Sem ele, dois comentários simultâneos leriam o mesmo `MAX(seq)` e o segundo seria recusado pelo `UNIQUE (id_video, seq)`.
9. **Por que a T3 bloqueia mudar `seq` ou `id_video` no UPDATE?** O `UNIQUE` barra número repetido, mas não barra buraco na contagem nem comentário mudar de vídeo levando o número antigo.
10. **O que a T5 conta e por que ela precisa do índice I1?** O número do Super Chat por (usuário, plataforma). Para achar o usuário e a plataforma ela segue `doacao → comentario → video → canal`, e o `MAX` percorre os comentários do usuário. Sem índice em `comentario(nro_usuario)` a trigger varre a tabela inteira (liga com o tema do Kayo).
11. **Como a T6 garante que a doação tem uma forma de pagamento só?** A PK de cada subtabela impede repetir na mesma; a T6 impede estar em duas. `TG_TABLE_NAME` diz qual tabela disparou. Nenhuma constraint declarativa faz isso.
12. **A T6 garante pelo menos uma forma?** Não, só no máximo uma. Se alguém inserir direto em `doacao`, fica sem forma. Por isso as inserções passam pelas functions `inserir_doacao_*`.
13. **O que a T7 valida?** O dono do canal precisa ser streamer (ter passaporte em `streamer_pais`) e ter conta na plataforma do canal. Participante de vídeo precisa só ser streamer.
14. **Quais as limitações das triggers?** T3 e T4 reaproveitam o número se o último for apagado. T7 valida só ao inserir ou atualizar o canal, não se o passaporte ou a conta forem apagados depois. T6 garante no máximo uma forma.

**Pontos fracos para ensaiar:** a pergunta 2 (a frase do relatório) e a 14. O professor gosta de ouvir a limitação dita pelo próprio grupo.

---

## 3. João — Functions: consultas 1 a 7, inserções e polimorfismo

**Arquivos:** `sql/2_plpgsql.sql`, Parte 2 da Seção 1 (`inserir_*`) e Consultas 1 a 7 da Seção 2; `sql/4_chamadas.sql`.

**Roteiro de estudo**
1. Slides da Aula 13 (functions) e da Aula 15 (transações).
2. Para cada consulta 1–7, escreva a pergunta de negócio em uma frase e diga de onde vêm os números.
3. Estude o padrão comum descrito no cabeçalho da Seção 2 (`RETURNS TABLE`, `DEFAULT NULL`, `#variable_conflict`).
4. Rode as chamadas da Parte 1 e da Parte 2 de `4_chamadas.sql`.
5. Entenda a sobrecarga da consulta 5.

**Perguntas possíveis**
1. **Por que function e não procedure?** O professor pediu function para tudo. Uma function pode devolver linhas (`RETURNS TABLE`) e usar na consulta.
2. **Como funciona o filtro opcional?** Parâmetro com `DEFAULT NULL` e o teste `(p IS NULL OR coluna = p)`. Sem parâmetro lista tudo, com parâmetro filtra, numa consulta só.
3. **O que é a diretiva `#variable_conflict use_column`?** Os nomes das colunas de saída coincidem com colunas das tabelas. A diretiva diz que, dentro do SQL, o nome se refere à coluna.
4. **Onde está o polimorfismo?** A consulta 5 (e a 12, do Gabriel) tem duas versões com o mesmo nome. O PostgreSQL escolhe pelo tipo do argumento: `INTEGER` filtra pelo número da empresa, `VARCHAR` pelo nome.
5. **Como a versão `VARCHAR` da consulta 5 funciona?** Procura o número da empresa pelo nome, dá erro se não existir e chama a versão `INTEGER`.
6. **Consulta 1: o que é "publicado"?** Vídeos dos canais de que o streamer é dono.
7. **Consulta 2: por que `WHERE qtd_total > 0`?** Vídeo sem comentário iria para o fim com zero e não responde "quais têm mais comentários". Ela usa a visão materializada `mv_interacoes_video`.
8. **Consulta 3: a média por vídeo conta vídeos sem comentário?** Sim, por isso a visão usa `LEFT JOIN`. `qtd_videos` é o divisor e aparece na saída.
9. **Consulta 4: como é a média?** Total em dólar / número de comentários que trouxeram doação. Não é dividido por todos os comentários. O professor confirmou: JOIN normal e média só sobre comentário com doação.
10. **Por que doações recusadas não entram?** Não geraram dinheiro: só `recebido` e `lido`.
11. **Consulta 6:** quantos canais cada usuário é membro e quanto paga por mês (soma do `nivel_canal.valor` das inscrições).
12. **Por que as `inserir_*` validam antes de inserir?** Orientação do professor: garantir que o pai existe e dar uma mensagem clara, por exemplo checar a plataforma antes de inserir o streamer.
13. **`inserir_streamer` e `inserir_doacao_*` são atômicas?** Sim. Uma function roda numa única transação: ou entram usuário e passaporte (ou doação e subclasse) juntos, ou nenhum.
14. **Por que as inserções passam `seq = 0`?** É só para satisfazer o `NOT NULL`; a trigger BEFORE INSERT sobrescreve (T3, T4, T5).
15. **Para que o `BEGIN ... ROLLBACK` no `4_chamadas.sql`?** Mostra o efeito de cada inserção e desfaz tudo, então o banco não muda.

**Pontos fracos para ensaiar:** saber o que é transação (Aula 15), porque o professor disse que gostaria de ver transações, e diferenciar bem a atomicidade da function da transação do `4_chamadas.sql`.

---

## 4. Gabriel — Visões e consultas 8 a 12

**Arquivos:** `sql/2_plpgsql.sql`, Parte 3 da Seção 1 (V1 a V5, `atualizar_visoes_materializadas`) e Consultas 8 a 12 (`valida_k`).

**Roteiro de estudo**
1. Slides da Aula 14 (visões).
2. Faça uma tabelinha das 5 visões: nome, virtual ou materializada, quais consultas usam, justificativa.
3. Entenda por que a consulta 11 é mensal e a 12 tem 3 agrupamentos (leia o comentário de cada uma).
4. Rode `SELECT * FROM consulta11_top_k_faturamento(5);` e confira as três parcelas.
5. Rode `REFRESH` e veja a diferença.

**Perguntas possíveis**
1. **Qual a diferença entre visão virtual e materializada?** A virtual é uma consulta salva e roda toda vez. A materializada guarda o resultado em disco e só muda com `REFRESH`.
2. **Quais são as 5 visões e por que cada uma é virtual ou materializada?**
   - V1 `vw_canal_info` (virtual): junção barata por PK, e canal novo tem que aparecer na hora.
   - V2 `mv_interacoes_video` (materializada): agrega `comentario`, a maior tabela; ranking tolera alguns minutos de atraso.
   - V3 `mv_doacoes_canal` (materializada): junta 6 tabelas para converter para dólar, e o mesmo resultado serve 4 consultas (4, 7, 10 e 11).
   - V4 `vw_membros_canal` (virtual): junta só 2 tabelas, e os membros mudam todo dia.
   - V5 `vw_faturamento_canal` (virtual): só combina resultados já agregados; materializar duplicaria dados e criaria outro refresh.
3. **O que acontece se entrar um comentário novo?** As consultas que usam a materializada não o veem até o `REFRESH` (`atualizar_visoes_materializadas()`). É o preço da materialização.
4. **Por que a V2 usa `LEFT JOIN`?** Para vídeos sem comentário aparecerem com 0, o que importa para a média da consulta 3.
5. **Por que `valida_k`?** `LIMIT NULL` não limita (devolveria tudo), `k = 0` devolve vazio sem aviso e `k` negativo dá erro confuso.
6. **Consultas 8, 9 e 10:** top-k de patrocínio (soma de `patrocinio`), de aportes de membros (V4) e de doações (V3).
7. **Consulta 11: por que mensal?** O professor disse que não dá para somar dia com mês e com ano, e que se escolhe uma granularidade não diária. Mensal porque membros já é mensalidade, o patrocínio vigente é tratado como mensal e as doações entram pela média mensal (`media_mensal_usd`). Dia seria fino demais; ano exigiria anualizar mensalidades que mudam.
8. **Como a doação vira valor mensal?** Total em dólar dividido pelo número de meses entre a primeira e a última doação do canal (os dois meses contam; um canal com doações só num mês tem 1).
9. **Quais as premissas fracas da consulta 11?** O patrocínio é tratado como mensal porque o sistema guarda só o contrato vigente, sem histórico. A média mensal das doações é uma aproximação.
10. **Consulta 12: quais são os 3 agrupamentos?** Streamer (streamers com conta na plataforma), canal (canais da plataforma) e streamer + canal juntos (streamers que também são donos de canal ali, e a média de canais por streamer).
11. **Como a consulta 12 evita multiplicar linhas na junção?** O `LEFT JOIN` em `canal` é pelo par (plataforma, dono), então cada conta só encontra os próprios canais. O `LEFT` mantém o streamer sem canal e a plataforma sem streamer (aparece com zero).
12. **Polimorfismo na 12:** versão `INTEGER` filtra pelo número da plataforma, versão `VARCHAR` pelo nome e chama a primeira.
13. **Por que a ordem é streamers, canais e streamers com canal?** O "E" do enunciado: primeiro streamers, depois canais, e o terceiro desempata.

**Pontos fracos para ensaiar:** as perguntas 3 e 9. Sobre a 12, ele a chamou de "complexa" na consultoria: saiba desenhar no papel de onde cada contagem sai.

---

## 5. Kayo — Índices e medição

**Arquivos:** `sql/2_plpgsql.sql` Seção 3 (I1 a I5), `medicoes/medir_indices.py`, `medicoes/resultados.md`, `medicoes/tempos.csv`, `medicoes/grafico_indices.svg`.

**Roteiro de estudo**
1. Slides das Aulas 02 e 05 (índices) e 07–12 (processamento e plano de execução).
2. Para cada índice, saiba: coluna, tipo, consulta ou escrita que ele acelera, e o ganho medido.
3. Entenda o método de medição passo a passo.
4. Rode `EXPLAIN ANALYZE` de uma function com e sem o índice I1.
5. Leia a seção "Leitura" de `resultados.md`.

**Perguntas possíveis**
1. **Como escolheram os 5 índices?** Pela carga de trabalho: consultas frequentes, pesadas e com predicado seletivo. A medição só confere a escolha, não a motivou (palavras do professor).
2. **Quais são?** I1 `comentario(nro_usuario)` hash; I2 `mv_interacoes_video(id_canal)` B+-tree; I3 `inscricao(nro_usuario)` hash; I4 `mv_doacoes_canal(id_canal)` B+-tree; I5 `canal(nro_streamer)` hash.
3. **Por que I1 é o mais importante?** A trigger T5 procura os comentários do usuário a cada Super Chat. É a escrita mais frequente em transmissão ao vivo. Medido: inserir 100 Super Chats foi de 40,5 ± 1,40 ms para 15,0 ± 1,17 ms (2,71x).
4. **E o custo do índice nas escritas?** Inserir 100 comentários foi de 4,05 para 4,45 ms (0,91x). É pouco perto dos 25 ms que o I1 economiza.
5. **Por que `inscricao(nro_usuario)` precisa de índice se já tem PK?** A PK é `(id_canal, nro_usuario)` e começa por `id_canal`, então não serve para buscar só pelo usuário.
6. **Por que não indexar `comentario(id_video)`?** O `UNIQUE (id_video, seq)` já cria índice que começa por `id_video`.
7. **Por que não indexam `pais` e outras tabelas pequenas?** O professor disse para não indexar tabela pequena: a leitura inteira é barata e o índice só custa escrita.
8. **Por que hash e não B+-tree em alguns?** Os predicados são só de igualdade (`= valor`). O hash serve só para igualdade; a B+-tree também serve para faixa e ordenação. Nas medições hash e B+-tree empataram, e o desempate foi conceitual. (Confirme a justificativa de I2 e I4 serem B+-tree: o comentário cita o filtro por canal e a junção da V5.)
9. **Pode indexar visão materializada?** Sim, porque ela é gravada em disco como uma tabela. Visão virtual não.
10. **Como mediram?** Script `medir_indices.py`: reinicia o PostgreSQL antes de cada execução (cache do banco frio), roda 10 vezes cada operação, calcula média e desvio padrão, usa o `Execution Time` do `EXPLAIN ANALYZE`, mede a linha de base sem os 5 índices e depois cada índice sozinho com `ANALYZE`. Total: 130 execuções, em `tempos.csv`, com gráfico antes/depois.
11. **Por que reiniciar o Postgres?** Para matar o cache e cada execução começar do zero. Sem isso o segundo run seria mais rápido por cache, não por índice.
12. **Por que só o I1 ganhou claro?** Com até 10 mil linhas, as tabelas ocupam poucas páginas e quase todo o tempo é custo fixo (carregar catálogo e compilar a function). Os outros ganharam 1,03x a 1,11x, perto do desvio padrão. O professor disse que o efeito aparece com algumas centenas de milhares de linhas.
13. **Então os outros índices são inúteis?** Com este volume o ganho é pequeno, mas sem índice o custo cresce com o tamanho da tabela e com índice cresce com o tamanho do resultado. A decisão foi pela carga, e a medição não a contradiz.
14. **Qual a limitação da medição?** O cache de arquivos do sistema operacional não é esvaziado (exige senha de administrador); só o cache do PostgreSQL.
15. **Um índice serve a mais de uma consulta?** Sim: I5 e I2 servem a consulta 3 com filtro por streamer; I4 serve a consulta 7 e a junção da V5 na consulta 11. Na medição, o I2 sozinho não mudou a consulta 3 (0,99x) e o I5 ajudou (1,08x).

**Pontos fracos para ensaiar:** as perguntas 12 e 13. Decidam como vão tratar o volume (ver Davi, pergunta 14), porque a resposta do Kayo depende dela. Se o grupo repovoar com mais linhas, refaça a medição e atualize os números acima.

---

## Núcleo comum (todos respondem, caso a pergunta fuja do tema)

1. Por que PK numérica e chave artificial com `UNIQUE`?
2. Por que trigger e não DCL/DDL nas colunas derivadas?
3. Visão virtual ou materializada: qual a diferença e qual usamos onde?
4. Por que a consulta 11 é mensal e a 12 tem três agrupamentos?
5. Quais os 5 índices e qual deles teve ganho claro?
6. Onde está o polimorfismo?
7. Como a doação em moeda local vira dólar?
8. O que o grupo decidiu sobre o volume de dados (ainda em aberto)?

## Ensaio

Cada um faz 3 perguntas de outro tema ao colega, em voz alta. Todos treinam rodar os 4 arquivos do zero em qualquer máquina, porque o professor roda o código na hora.
