-- =====================================================================
-- dev/verificacoes.sql — testes automáticos do banco (usados por dev/testar.sh)
-- Cada verificação levanta EXCEPTION se falhar; o psql para no primeiro erro (ON_ERROR_STOP).
-- Não faz parte da entrega ao professor; serve ao grupo para conferir que nada quebrou.
-- =====================================================================

-- 1. Volume: toda tabela entre 1.000 e 10.000 tuplas (item mandatório 1).
DO $$
DECLARE
    t TEXT;
    n BIGINT;
BEGIN
    FOR t IN SELECT table_name FROM information_schema.tables
              WHERE table_schema = 'public' AND table_type = 'BASE TABLE' LOOP
        EXECUTE format('SELECT count(*) FROM %I', t) INTO n;
        IF n < 1000 OR n > 10000 THEN
            RAISE EXCEPTION 'Tabela % tem % tuplas (fora de 1.000–10.000)', t, n;
        END IF;
    END LOOP;
    IF (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE') <> 20 THEN
        RAISE EXCEPTION 'Esperadas 20 tabelas';
    END IF;
END $$;

-- 2. Atributos derivados batem com o valor real (triggers T1 e T2).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM plataforma p
                WHERE qtd_users <> (SELECT count(*) FROM plataforma_usuario pu WHERE pu.nro_plataforma = p.nro_plataforma)) THEN
        RAISE EXCEPTION 'plataforma.qtd_users diverge da contagem real';
    END IF;
    IF EXISTS (SELECT 1 FROM canal c
                WHERE qtd_visualizacoes <> (SELECT COALESCE(SUM(visu_total), 0) FROM video v WHERE v.id_canal = c.id_canal)) THEN
        RAISE EXCEPTION 'canal.qtd_visualizacoes diverge da soma real';
    END IF;
END $$;

-- 3. Sequenciais sem buracos: em cada vídeo, seq vai de 1 até o nº de comentários (trigger T3);
--    em cada comentário, seq_doacao vai de 1 até o nº de doações (trigger T4).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM comentario GROUP BY id_video HAVING MAX(seq) <> COUNT(*) OR MIN(seq) <> 1) THEN
        RAISE EXCEPTION 'comentario.seq com buraco ou fora de 1..n';
    END IF;
    IF EXISTS (SELECT 1 FROM doacao GROUP BY id_comentario HAVING MAX(seq_doacao) <> COUNT(*) OR MIN(seq_doacao) <> 1) THEN
        RAISE EXCEPTION 'doacao.seq_doacao com buraco ou fora de 1..n';
    END IF;
END $$;

-- 4. Especialização: toda doação tem exatamente UMA forma de pagamento.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM doacao d
         WHERE (SELECT count(*) FROM bitcoin b WHERE b.id_doacao = d.id_doacao)
             + (SELECT count(*) FROM paypal p WHERE p.id_doacao = d.id_doacao)
             + (SELECT count(*) FROM cartao_credito c WHERE c.id_doacao = d.id_doacao)
             + (SELECT count(*) FROM mecanismo_plat m WHERE m.id_doacao = d.id_doacao) <> 1) THEN
        RAISE EXCEPTION 'Existe doação sem forma de pagamento ou com mais de uma';
    END IF;
END $$;

-- 5. As triggers BARRAM o que devem barrar. Cada teste espera um erro; se o comando passar, falha.
DO $$
DECLARE
    v_nao_streamer BIGINT := (SELECT u.nro_usuario FROM usuario u
                               WHERE NOT EXISTS (SELECT 1 FROM streamer_pais s WHERE s.nro_streamer = u.nro_usuario) LIMIT 1);
    v_bitcoin BIGINT := (SELECT id_doacao FROM bitcoin LIMIT 1);
BEGIN
    BEGIN
        UPDATE plataforma SET qtd_users = 999999 WHERE nro_plataforma = 1;
        RAISE EXCEPTION 'FALHA: alterar qtd_users na mão deveria ser bloqueado';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF;
    END;

    BEGIN
        UPDATE canal SET qtd_visualizacoes = 1 WHERE id_canal = 1;
        RAISE EXCEPTION 'FALHA: alterar qtd_visualizacoes na mão deveria ser bloqueado';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF;
    END;

    BEGIN
        PERFORM inserir_canal(v_nao_streamer, 1, 'canal invalido', 'publico', current_date, 'x');
        RAISE EXCEPTION 'FALHA: usuário que não é streamer não pode ter canal';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF;
    END;

    BEGIN
        INSERT INTO paypal (id_doacao, id_paypal) VALUES (v_bitcoin, 'DUPLICADA-TESTE');
        RAISE EXCEPTION 'FALHA: doação em bitcoin não pode virar também paypal';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF;
    END;

    BEGIN
        PERFORM inserir_usuario('novo_teste', 'novo@teste.com', DATE '2000-01-01', NULL, NULL, 9999::SMALLINT);
        RAISE EXCEPTION 'FALHA: usuário com país inexistente deveria ser recusado';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF;
    END;

    BEGIN
        INSERT INTO nivel_canal (id_canal, nivel, nome, valor, gif) VALUES (2999, 6, 'Sexto', 1, 'x.gif');
        RAISE EXCEPTION 'FALHA: nível 6 deveria violar o CHECK 1..5';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

-- 6. Inserção ponta a ponta numa transação desfeita no fim: as triggers numeram e atualizam tudo.
BEGIN;
DO $$
DECLARE
    v_streamer BIGINT;
    v_canal    INTEGER;
    v_video    BIGINT;
    v_c1       BIGINT;
    v_c2       BIGINT;
    v_d        BIGINT;
BEGIN
    v_streamer := inserir_streamer('teste_streamer', 'teste@stream.com', DATE '1999-09-09', NULL, NULL, 55::SMALLINT, 55::SMALLINT, 'TESTE123');
    PERFORM inserir_conta_plataforma(v_streamer, 2, 424242);
    v_canal := inserir_canal(v_streamer, 2, 'Canal de Teste', 'misto', current_date, 'teste');
    v_video := inserir_video(v_canal, 'Video teste', now()::TIMESTAMP, 'Teste', 100, 10, 500);
    v_c1 := inserir_comentario(v_video, v_streamer, 'primeiro', now()::TIMESTAMP, true);
    v_c2 := inserir_comentario(v_video, v_streamer, 'segundo', now()::TIMESTAMP, false);
    PERFORM inserir_doacao_plataforma(v_c1, 10, 'recebido');
    v_d := inserir_doacao_plataforma(v_c1, 20, 'lido');

    IF (SELECT seq FROM comentario WHERE id_comentario = v_c2) <> 2 THEN RAISE EXCEPTION 'seq do 2º comentário deveria ser 2'; END IF;
    IF (SELECT seq_doacao FROM doacao WHERE id_doacao = v_d) <> 2 THEN RAISE EXCEPTION 'seq_doacao deveria ser 2'; END IF;
    IF (SELECT seq_plataforma FROM mecanismo_plat WHERE id_doacao = v_d) <> 2 THEN RAISE EXCEPTION 'seq_plataforma deveria ser 2'; END IF;
    IF (SELECT qtd_visualizacoes FROM canal WHERE id_canal = v_canal) <> 500 THEN RAISE EXCEPTION 'qtd_visualizacoes deveria ser 500'; END IF;
END $$;
ROLLBACK;

-- 7. As 12 consultas rodam e devolvem linhas (inclusive as versões polimórficas).
DO $$
BEGIN
    IF (SELECT count(*) FROM consulta1_streamers_mais_videos()) = 0 THEN RAISE EXCEPTION 'Q1 vazia'; END IF;
    IF (SELECT count(*) FROM consulta1_streamers_mais_videos(1)) = 0 THEN RAISE EXCEPTION 'Q1 filtrada vazia'; END IF;
    IF (SELECT count(*) FROM consulta2_videos_mais_comentados()) = 0 THEN RAISE EXCEPTION 'Q2 vazia'; END IF;
    IF (SELECT count(*) FROM consulta3_canais_mais_interacoes()) = 0 THEN RAISE EXCEPTION 'Q3 vazia'; END IF;
    IF (SELECT count(*) FROM consulta4_canais_media_doacao()) = 0 THEN RAISE EXCEPTION 'Q4 vazia'; END IF;
    IF (SELECT count(*) FROM consulta5_patrocinios()) <> (SELECT count(*) FROM patrocinio) THEN RAISE EXCEPTION 'Q5 incompleta'; END IF;
    IF (SELECT count(*) FROM consulta5_patrocinios(10)) <> (SELECT count(*) FROM consulta5_patrocinios('Empresa 10 S.A.')) THEN
        RAISE EXCEPTION 'Q5: versões INTEGER e VARCHAR divergem';
    END IF;
    IF (SELECT count(*) FROM consulta6_membros_por_usuario()) = 0 THEN RAISE EXCEPTION 'Q6 vazia'; END IF;
    IF (SELECT count(*) FROM consulta7_canais_com_doacoes()) = 0 THEN RAISE EXCEPTION 'Q7 vazia'; END IF;
    IF (SELECT count(*) FROM consulta8_top_k_patrocinio(5)) <> 5 THEN RAISE EXCEPTION 'Q8 não devolveu 5'; END IF;
    IF (SELECT count(*) FROM consulta9_top_k_membros(5)) <> 5 THEN RAISE EXCEPTION 'Q9 não devolveu 5'; END IF;
    IF (SELECT count(*) FROM consulta10_top_k_doacoes(5)) <> 5 THEN RAISE EXCEPTION 'Q10 não devolveu 5'; END IF;
    IF (SELECT count(*) FROM consulta11_top_k_faturamento(5)) <> 5 THEN RAISE EXCEPTION 'Q11 não devolveu 5'; END IF;
    IF (SELECT count(*) FROM consulta12_top_k_plataformas(5)) <> 5 THEN RAISE EXCEPTION 'Q12 não devolveu 5'; END IF;
    IF (SELECT nome FROM consulta12_top_k_plataformas(1, 'Twitch')) <> 'Twitch' THEN RAISE EXCEPTION 'Q12 VARCHAR falhou'; END IF;
    -- O total da Q11 é a soma das três parcelas.
    IF EXISTS (SELECT 1 FROM consulta11_top_k_faturamento(50)
                WHERE receita_total <> receita_patrocinio + receita_membros + receita_doacoes) THEN
        RAISE EXCEPTION 'Q11: total diferente da soma das parcelas';
    END IF;
    -- Q11 mensal: a parcela de doações é a média mensal, nunca maior que o total acumulado do canal.
    IF EXISTS (SELECT 1 FROM mv_doacoes_canal WHERE meses_com_doacao < 1 OR media_mensal_usd > total_usd) THEN
        RAISE EXCEPTION 'Q11: média mensal de doações inconsistente';
    END IF;
    -- Q12: nenhum canal se perde na junção (todo canal aparece na sua plataforma) e
    --   streamers com canal <= streamers com conta.
    IF (SELECT sum(qtd_canais) FROM consulta12_top_k_plataformas(100000)) <> (SELECT count(*) FROM canal) THEN
        RAISE EXCEPTION 'Q12: soma dos canais difere do total de canais';
    END IF;
    IF EXISTS (SELECT 1 FROM consulta12_top_k_plataformas(100000) WHERE qtd_streamers_com_canal > qtd_streamers) THEN
        RAISE EXCEPTION 'Q12: mais streamers com canal do que streamers';
    END IF;
    BEGIN
        PERFORM * FROM consulta8_top_k_patrocinio(0);
        RAISE EXCEPTION 'FALHA: k = 0 deveria ser recusado';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF;
    END;
END $$;

-- 8. Os 5 índices existem (e são só 5 além dos de PK/UNIQUE).
DO $$
BEGIN
    IF (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND indexname LIKE 'idx\_%') <> 5 THEN
        RAISE EXCEPTION 'Esperados exatamente 5 índices de apoio (idx_*)';
    END IF;
END $$;

SELECT 'verificacoes ok' AS resultado;
