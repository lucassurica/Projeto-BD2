-- =====================================================================
-- medicoes/medir_indices.sql — mede o ganho de cada índice candidato
-- Uso: rodar num banco já povoado (01–04 aplicados) e SEM o 05_indices.sql.
--   psql -d streaming -f medicoes/medir_indices.sql
--
-- Método (orientação da consultoria: "roda a consulta com e sem o índice, repete ~5 vezes, cuidado com cache"):
--   1. Para cada consulta, executa N vezes e tira a média do tempo (a 1ª execução aquece o cache e é descartada).
--   2. Mede todas as consultas sem índice extra (linha de base).
--   3. Cria UM índice candidato, roda ANALYZE, mede de novo todas as consultas e apaga o índice.
--   4. Compara: ganho = tempo sem índice / tempo com índice.
-- EXECUTE (SQL dinâmico) faz o otimizador planejar cada chamada com o valor literal do filtro,
--   que é o que acontece quando a aplicação chama a function com um parâmetro concreto.
-- =====================================================================

CREATE TEMP TABLE resultado_medicao (indice TEXT, consulta TEXT, media_ms NUMERIC);

-- Executa p_sql p_n vezes e devolve o tempo médio em ms.
-- Comandos de escrita (INSERT) são medidos dentro de um bloco que termina em erro proposital: o PostgreSQL
--   desfaz tudo (rollback do subbloco) e o banco volta ao estado original para a próxima medição.
CREATE OR REPLACE FUNCTION pg_temp.executar(p_sql TEXT, p_desfazer BOOLEAN) RETURNS VOID AS $$
BEGIN
    IF NOT p_desfazer THEN
        EXECUTE p_sql;
        RETURN;
    END IF;
    BEGIN
        EXECUTE p_sql;
        RAISE EXCEPTION 'desfazer';
    EXCEPTION WHEN raise_exception THEN
        NULL; -- rollback do subbloco já aconteceu
    END;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pg_temp.medir(p_sql TEXT, p_n INTEGER) RETURNS NUMERIC AS $$
DECLARE
    v_desfazer BOOLEAN := p_sql ILIKE 'SELECT inserir%';
    t0 TIMESTAMPTZ;
    i  INTEGER;
BEGIN
    PERFORM pg_temp.executar(p_sql, v_desfazer); -- aquecimento (descartado)
    t0 := clock_timestamp();
    FOR i IN 1..p_n LOOP
        PERFORM pg_temp.executar(p_sql, v_desfazer);
    END LOOP;
    RETURN round((extract(epoch FROM clock_timestamp() - t0) * 1000 / p_n)::NUMERIC, 3);
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    v_streamer BIGINT := (SELECT nro_streamer FROM canal WHERE id_canal = 19);
    -- Consultas medidas: as que têm PREDICADO (filtro). Sem predicado, índice não ajuda (consultoria).
    v_consultas TEXT[][] := ARRAY[
        ['Q1 filtro plataforma',  'SELECT * FROM consulta1_streamers_mais_videos(2)'],
        ['Q2 filtro canal',       'SELECT * FROM consulta2_videos_mais_comentados(19)'],
        ['Q3 filtro streamer',    'SELECT * FROM consulta3_canais_mais_interacoes(' || v_streamer || ')'],
        ['Q4 filtro plataforma',  'SELECT * FROM consulta4_canais_media_doacao(2)'],
        ['Q5 filtro empresa',     'SELECT * FROM consulta5_patrocinios(10)'],
        ['Q6 filtro usuario',     'SELECT * FROM consulta6_membros_por_usuario(792)'],
        ['Q7 filtro canal',       'SELECT * FROM consulta7_canais_com_doacoes(19)'],
        ['Q12 filtro plataforma', 'SELECT * FROM consulta12_top_k_plataformas(5, 2)'],
        ['Refresh das MVs',       'SELECT atualizar_visoes_materializadas()'],
        -- Escritas: medem o OVERHEAD de inserção que o enunciado manda considerar (desfeitas após medir).
        ['Inserir 100 comentarios',  'SELECT inserir_comentario(v.id_video, 1, ''teste'', now()::timestamp, true) FROM (SELECT id_video FROM video ORDER BY id_video LIMIT 100) v'],
        ['Inserir 100 Super Chats',  'SELECT inserir_doacao_plataforma(c.id_comentario, 5, ''recebido'') FROM (SELECT id_comentario FROM comentario ORDER BY id_comentario LIMIT 100) c']
    ];
    -- Índices candidatos (nome, comando). Os já cobertos por PK/UNIQUE ficaram de fora (ver relatório).
    -- A 1ª rodada "(aquecimento)" só esquenta o cache e é descartada; a linha de base é "(nenhum)".
    -- Os finalistas aparecem nas duas estruturas vistas em aula (hash e B+-tree) para comparar.
    v_indices TEXT[][] := ARRAY[
        ['(aquecimento)',                    ''],
        ['(nenhum)',                         ''],
        ['canal(nro_streamer) btree',        'CREATE INDEX idx_cand ON canal (nro_streamer)'],
        ['inscricao(nro_usuario) btree',     'CREATE INDEX idx_cand ON inscricao (nro_usuario)'],
        ['comentario(nro_usuario) hash',     'CREATE INDEX idx_cand ON comentario USING hash (nro_usuario)'],
        ['mv_interacoes_video(id_canal) hash', 'CREATE INDEX idx_cand ON mv_interacoes_video USING hash (id_canal)'],
        ['mv_doacoes_canal(id_canal) hash',  'CREATE INDEX idx_cand ON mv_doacoes_canal USING hash (id_canal)'],
        ['video(id_canal)',                  'CREATE INDEX idx_cand ON video (id_canal)'],
        ['canal(nro_streamer) hash',         'CREATE INDEX idx_cand ON canal USING hash (nro_streamer)'],
        ['canal(nro_plataforma)',            'CREATE INDEX idx_cand ON canal (nro_plataforma)'],
        ['inscricao(nro_usuario) hash',      'CREATE INDEX idx_cand ON inscricao USING hash (nro_usuario)'],
        ['mv_interacoes_video(id_canal)',    'CREATE INDEX idx_cand ON mv_interacoes_video (id_canal)'],
        ['mv_doacoes_canal(id_canal)',       'CREATE INDEX idx_cand ON mv_doacoes_canal (id_canal)'],
        ['comentario(nro_usuario)',          'CREATE INDEX idx_cand ON comentario (nro_usuario)'],
        ['doacao parcial status recebido',   'CREATE INDEX idx_cand ON doacao (id_comentario) WHERE status IN (''recebido'', ''lido'')']
    ];
    i INTEGER;
    j INTEGER;
BEGIN
    FOR i IN 1..array_length(v_indices, 1) LOOP
        IF v_indices[i][2] <> '' THEN
            EXECUTE v_indices[i][2];
            ANALYZE;
        END IF;
        FOR j IN 1..array_length(v_consultas, 1) LOOP
            INSERT INTO resultado_medicao
            VALUES (v_indices[i][1], v_consultas[j][1],
                    pg_temp.medir(v_consultas[j][2],
                                  CASE WHEN v_consultas[j][1] LIKE 'Refresh%' OR v_consultas[j][1] LIKE 'Inserir%' THEN 20 ELSE 300 END));
        END LOOP;
        IF v_indices[i][2] <> '' THEN
            DROP INDEX idx_cand;
        END IF;
    END LOOP;
END $$;

-- Tabela de ganhos: para cada índice, só as consultas em que ele mudou o tempo em mais de 25%
--   (variações menores ficam dentro do ruído de medição observado entre rodadas).
SELECT r.indice, r.consulta, b.media_ms AS sem_indice_ms, r.media_ms AS com_indice_ms,
       round(b.media_ms / NULLIF(r.media_ms, 0), 2) AS ganho_x
  FROM resultado_medicao r
  JOIN resultado_medicao b ON b.consulta = r.consulta AND b.indice = '(nenhum)'
 WHERE r.indice NOT IN ('(nenhum)', '(aquecimento)')
   AND abs(b.media_ms - r.media_ms) > 0.25 * b.media_ms
 ORDER BY r.indice, ganho_x DESC;

-- Linha de base completa.
SELECT consulta, media_ms AS sem_indice_ms FROM resultado_medicao WHERE indice = '(nenhum)' ORDER BY media_ms DESC;
