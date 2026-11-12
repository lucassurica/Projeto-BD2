-- =====================================================================
-- 05_indices.sql — OS 5 ÍNDICES DE APOIO
-- Rodar por último (depois do povoamento e das consultas).
--
-- Como escolhemos (consultorias 1 e 2): o índice é escolhido pela CARGA DE TRABALHO, não pelo tempo.
--   O tempo medido vem depois, só para CONFERIR que a decisão estava certa.
--   1. Partimos das operações FREQUENTES e PESADAS do sistema:
--        * a inserção de Super Chat (doação pelo mecanismo da plataforma), que acontece o tempo todo em
--          transmissão ao vivo e cuja trigger T5 procura as doações anteriores do usuário;
--        * as consultas que uma página do sistema chamaria a cada acesso, sempre com um filtro:
--          "vídeos do canal X" (2), "canais do streamer X" (3), "de que canais sou membro" (6),
--          "doações do canal X" (7).
--   2. Ficamos só com predicados SELETIVOS (igualdade que devolve poucas linhas de uma tabela grande).
--      Consulta sem predicado (os top-k) lê a tabela inteira; índice não ajuda. Tabelas pequenas
--      (pais, conversao, plataforma, empresa) também ficam sem índice extra: ler a tabela toda já é barato.
--   3. Descartamos as colunas que JÁ têm índice por causa de uma PK ou UNIQUE. O PostgreSQL cria um
--      índice B+-tree para cada PK/UNIQUE, e ele serve para buscas pela 1ª coluna da chave:
--        * canal.nro_plataforma  -> já coberto por UNIQUE (nro_plataforma, nome_canal)  [consultas 1, 4, 12]
--        * patrocinio.nro_empresa -> já coberto pela PK (nro_empresa, id_canal)         [consulta 5]
--        * comentario.id_video    -> já coberto por UNIQUE (id_video, seq)              [trigger T3, refresh]
--        * doacao.id_comentario   -> já coberto por UNIQUE (id_comentario, seq_doacao)  [trigger T4, refresh]
--   4. Conferimos com medição (medicoes/medir_indices.py; resultados e gráfico em medicoes/): cada
--      operação rodou 10 vezes sem e 10 vezes com o índice, reiniciando o PostgreSQL antes de cada
--      execução (cache frio), e comparamos média e desvio padrão.
--   5. Overhead de inserção: todo índice deixa INSERT/UPDATE mais caros (o índice também precisa ser
--      atualizado). Medimos esse custo na inserção de comentários com o I1 (ver medicoes/resultados.md).
--      Nos índices das visões materializadas o custo aparece no REFRESH, que reconstrói o índice.
--
-- Hash ou B+-tree? (Aulas 03 e 04)
--   Hash: só responde igualdade (=), em ~1 acesso. B+-tree: responde igualdade, intervalo (<, >, BETWEEN)
--   e ordenação. Numa medição anterior, com os dois tipos, eles EMPATARAM em todas as buscas por igualdade
--   (a vantagem trocava de lado de uma rodada para outra). Então a escolha é conceitual:
--   * HASH nas colunas de tabelas-base que só aparecem em igualdade ("os comentários do usuário X"):
--     nunca há busca por intervalo de nro_usuario/nro_streamer, então a ordem da B+-tree não seria usada.
--   * B+-tree nas visões materializadas: id_canal também é a coluna de JUNÇÃO com canal e entre as visões
--     (vw_faturamento_canal); a B+-tree entrega as linhas já ordenadas, o que permite ao otimizador um
--     merge join; o hash não oferece ordem.
-- =====================================================================


-- ---------------------------------------------------------------------
-- I1. comentario(nro_usuario) — HASH
-- Beneficia: inserção de doação pelo mecanismo da plataforma (Super Chat). A trigger T5 procura
--   "as doações deste usuário nesta plataforma" (WHERE c.nro_usuario = ...) para gerar o sequencial;
--   sem índice ela varre os 10.000 comentários a cada doação.
-- É a escrita mais frequente do sistema em transmissões ao vivo, por isso é o índice de maior prioridade.
-- Conferido (cache frio, 10 execuções): inserir 100 Super Chats foi de 28,9 ± 1,7 ms para 12,3 ± 0,4 ms (2,35x).
-- Overhead: inserir 100 comentários foi de 3,88 ± 0,12 ms para 4,38 ± 1,26 ms (dentro do ruído).
-- Bônus: também acelera a checagem da FK ao apagar um usuário (comentario.nro_usuario é RESTRICT).
-- ---------------------------------------------------------------------
CREATE INDEX idx_comentario_usuario ON comentario USING hash (nro_usuario);


-- ---------------------------------------------------------------------
-- I2. mv_interacoes_video(id_canal) — B+-tree
-- Beneficia: consulta 2 com filtro de canal ("vídeos do canal X") e consulta 3 com filtro de streamer.
-- Sem índice, filtrar um canal obriga a ler a visão inteira (10.000 vídeos) para achar os poucos do canal.
-- Conferido: consulta 2 de 2,51 para 2,21 ms (1,13x); consulta 3 de 3,32 para 3,19 ms (1,04x).
--   Ganho pequeno com 10.000 vídeos; cresce com o volume (o custo sem índice é proporcional à visão).
-- Pode-se indexar visão materializada porque ela é gravada em disco como uma tabela.
-- ---------------------------------------------------------------------
CREATE INDEX idx_mv_interacoes_canal ON mv_interacoes_video (id_canal);


-- ---------------------------------------------------------------------
-- I3. inscricao(nro_usuario) — HASH
-- Beneficia: consulta 6 com filtro de usuário ("de quantos canais sou membro e quanto pago").
-- Conferido: de 2,44 para 2,25 ms (1,09x); ganho pequeno com 10.000 inscrições.
-- A PK de inscricao é (id_canal, nro_usuario): começa por id_canal, então NÃO serve para buscar só pelo
--   usuário. Também acelera o CASCADE ao apagar um usuário.
-- ---------------------------------------------------------------------
CREATE INDEX idx_inscricao_usuario ON inscricao USING hash (nro_usuario);


-- ---------------------------------------------------------------------
-- I4. mv_doacoes_canal(id_canal) — B+-tree
-- Beneficia: consulta 7 com filtro de canal. Também serve a junção por id_canal da visão
--   vw_faturamento_canal (consulta 11).
-- A consulta de doações de um canal é a que a página do canal chamaria a cada acesso.
-- Conferido: de 1,94 para 1,89 ms (1,03x), dentro do ruído: a visão tem só ~1.200 linhas hoje.
-- ---------------------------------------------------------------------
CREATE INDEX idx_mv_doacoes_canal ON mv_doacoes_canal (id_canal);


-- ---------------------------------------------------------------------
-- I5. canal(nro_streamer) — HASH
-- Beneficia: consulta 3 com filtro de streamer: acha direto os canais do streamer em vez de varrer
--   os 3.000 canais. Também acelera a checagem da FK ao apagar um usuário (canal.nro_streamer é RESTRICT).
-- Conferido: de 3,32 para 2,89 ms (1,15x).
-- ---------------------------------------------------------------------
CREATE INDEX idx_canal_streamer ON canal USING hash (nro_streamer);


-- Atualiza as estatísticas para o otimizador já considerar os índices novos.
ANALYZE;
