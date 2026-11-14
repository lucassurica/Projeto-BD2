-- ---------------------------------------------------------------------
-- ÍNDICES
-- ---------------------------------------------------------------------

-- I1. comentario(nro_usuario) — HASH
-- Beneficia: inserção de doação pelo mecanismo da plataforma (Super Chat). A trigger T5 procura
-- "as doações deste usuário nesta plataforma" (WHERE c.nro_usuario = ...) para gerar o sequencial;
-- sem índice ela varre os 10.000 comentários a cada doação.
-- É a escrita mais frequente do sistema em transmissões ao vivo, por isso é o índice de maior prioridade.

CREATE INDEX idx_comentario_usuario ON comentario USING hash (nro_usuario);

-- ---------------------------------------------------------------------
-- I2. mv_interacoes_video(id_canal) — B+-tree
-- Beneficia: consulta 2 com filtro de canal ("vídeos do canal X") e consulta 3 com filtro de streamer.
-- Sem índice, filtrar um canal obriga a ler a visão inteira (10.000 vídeos) para achar os poucos do canal.
-- Ganho pequeno com 10.000 vídeos; cresce com o volume (o custo sem índice é proporcional à visão).
-- Pode-se indexar visão materializada porque ela é gravada em disco como uma tabela.
-- ---------------------------------------------------------------------

CREATE INDEX idx_mv_interacoes_canal ON mv_interacoes_video (id_canal);

-- ---------------------------------------------------------------------
-- I3. inscricao(nro_usuario) — HASH
-- Beneficia: consulta 6 com filtro de usuário ("de quantos canais sou membro e quanto pago").
-- A PK de inscricao é (id_canal, nro_usuario): começa por id_canal, então NÃO serve para buscar só pelo
-- usuário. Também acelera o CASCADE ao apagar um usuário.
-- ---------------------------------------------------------------------

CREATE INDEX idx_inscricao_usuario ON inscricao USING hash (nro_usuario);

-- ---------------------------------------------------------------------
-- I4. mv_doacoes_canal(id_canal) — B+-tree
-- Beneficia: consulta 7 com filtro de canal. Também serve a junção por id_canal da visão
-- vw_faturamento_canal (consulta 11).
-- A consulta de doações de um canal é a que a página do canal chamaria a cada acesso.
-- ---------------------------------------------------------------------

CREATE INDEX idx_mv_doacoes_canal ON mv_doacoes_canal (id_canal);

-- ---------------------------------------------------------------------
-- I5. canal(nro_streamer) — HASH
-- Beneficia: consulta 3 com filtro de streamer: acha direto os canais do streamer em vez de varrer
-- os 3.000 canais. Também acelera a checagem da FK ao apagar um usuário (canal.nro_streamer é RESTRICT).
-- ---------------------------------------------------------------------
CREATE INDEX idx_canal_streamer ON canal USING hash (nro_streamer);

-- Atualiza as estatísticas para o otimizador já considerar os índices novos.
ANALYZE;