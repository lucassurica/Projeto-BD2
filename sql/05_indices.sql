-- =====================================================================
-- 05_indices.sql — OS 5 ÍNDICES DE APOIO
-- Rodar por último (depois do povoamento e das consultas).
--
-- Como escolhemos (orientação da consultoria: priorizar e MEDIR, não tentativa e erro):
--   1. Listamos as consultas com PREDICADO seletivo (filtro por canal, usuário, streamer...) e as escritas
--      frequentes. Consulta sem predicado (os top-k) lê a tabela inteira; índice não ajuda.
--   2. Descartamos as colunas que JÁ têm índice por causa de uma PK ou UNIQUE. O PostgreSQL cria um
--      índice B+-tree para cada PK/UNIQUE, e ele serve para buscas pela 1ª coluna da chave:
--        * canal.nro_plataforma  -> já coberto por UNIQUE (nro_plataforma, nome_canal)  [consultas 1, 4, 12]
--        * patrocinio.nro_empresa -> já coberto pela PK (nro_empresa, id_canal)         [consulta 5]
--        * comentario.id_video    -> já coberto por UNIQUE (id_video, seq)              [trigger T3, refresh]
--        * doacao.id_comentario   -> já coberto por UNIQUE (id_comentario, seq_doacao)  [trigger T4, refresh]
--   3. Medimos cada candidato com e sem o índice (medicoes/medir_indices.sql; resultados em
--      medicoes/resultados.md) e ficamos com os 5 de maior ganho em consultas relevantes.
--   4. Overhead de inserção: todo índice deixa INSERT/UPDATE mais caros (o índice também precisa ser
--      atualizado). Nos 5 escolhidos o custo extra de inserir 100 comentários ficou dentro do ruído da medição.
--      Nos índices das visões materializadas o custo aparece no REFRESH, que reconstrói o índice.
--
-- Hash ou B+-tree? (Aulas 03 e 04)
--   Hash: só responde igualdade (=), em ~1 acesso. B+-tree: responde igualdade, intervalo (<, >, BETWEEN)
--   e ordenação. Medimos os dois para cada finalista, em duas rodadas: EMPATARAM (a vantagem trocava de
--   lado de uma rodada para outra). Critério de desempate:
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
-- Medido: inserir 100 Super Chats caiu de ~17 ms para ~4 ms (3,4x a 4,1x nas duas rodadas).
-- É a escrita mais frequente do sistema em transmissões ao vivo, por isso é o índice de maior prioridade.
-- Bônus: também acelera a checagem da FK ao apagar um usuário (comentario.nro_usuario é RESTRICT).
-- ---------------------------------------------------------------------
CREATE INDEX idx_comentario_usuario ON comentario USING hash (nro_usuario);


-- ---------------------------------------------------------------------
-- I2. mv_interacoes_video(id_canal) — B+-tree
-- Beneficia: consulta 2 com filtro de canal (5,3x) e consulta 3 com filtro de streamer (1,9x a 2,0x).
-- Sem índice, filtrar um canal obriga a ler a visão inteira (10.000 vídeos) para achar os poucos do canal.
-- Pode-se indexar visão materializada porque ela é gravada em disco como uma tabela.
-- ---------------------------------------------------------------------
CREATE INDEX idx_mv_interacoes_canal ON mv_interacoes_video (id_canal);


-- ---------------------------------------------------------------------
-- I3. inscricao(nro_usuario) — HASH
-- Beneficia: consulta 6 com filtro de usuário ("de quantos canais sou membro e quanto pago") — 3,9x.
-- A PK de inscricao é (id_canal, nro_usuario): começa por id_canal, então NÃO serve para buscar só pelo
--   usuário. Também acelera o CASCADE ao apagar um usuário.
-- ---------------------------------------------------------------------
CREATE INDEX idx_inscricao_usuario ON inscricao USING hash (nro_usuario);


-- ---------------------------------------------------------------------
-- I4. mv_doacoes_canal(id_canal) — B+-tree
-- Beneficia: consulta 7 com filtro de canal (2,2x). Também serve a junção por id_canal da visão
--   vw_faturamento_canal (consulta 11).
-- Ganho absoluto pequeno (a visão tem ~1.200 linhas), mas a consulta de doações de um canal é a que a
--   página do canal chamaria a cada acesso.
-- ---------------------------------------------------------------------
CREATE INDEX idx_mv_doacoes_canal ON mv_doacoes_canal (id_canal);


-- ---------------------------------------------------------------------
-- I5. canal(nro_streamer) — HASH
-- Beneficia: consulta 3 com filtro de streamer (~1,35x; o menor ganho dos cinco): acha direto os canais do streamer em vez de varrer
--   os 3.000 canais. Também acelera a checagem da FK ao apagar um usuário (canal.nro_streamer é RESTRICT).
-- ---------------------------------------------------------------------
CREATE INDEX idx_canal_streamer ON canal USING hash (nro_streamer);


-- Atualiza as estatísticas para o otimizador já considerar os índices novos.
ANALYZE;
