-- =====================================================================
-- 03_povoamento.sql — POVOAMENTO (dados artificiais)
-- Rodar depois de 01_ddl.sql e 02_ddl_estendida.sql, num banco vazio.
--
-- Metas do enunciado e da consultoria:
--   * entre 1.000 e 10.000 tuplas em CADA uma das 20 tabelas;
--   * o valor do dado não importa, mas a DISTRIBUIÇÃO importa: no mundo real poucos canais e vídeos
--     concentram muita audiência, comentários e dinheiro, e a maioria tem pouco (cauda longa).
--     Distribuição uniforme distorceria a seletividade dos predicados e, portanto, a escolha dos índices;
--   * inserir pelas functions de inserção do 02 (validam e disparam as triggers).
--
-- Como a concentração é gerada: pop_concentrado(n, e) = 1 + floor(n * random()^e).
--   Com e = 1 a escolha é uniforme. Com e = 3, cerca de 46% dos sorteios caem nos primeiros 10% dos itens
--   (porque 0,1^(1/3) ≈ 0,46). Quanto maior o expoente, mais concentrado.
--
-- setseed: fixa a semente do random(); rodar de novo gera exatamente os mesmos dados (reprodutível).
--
-- TRANSAÇÃO: a carga inteira roda entre BEGIN e COMMIT. Se qualquer passo falhar, o banco volta ao
--   estado vazio, sem dados pela metade (atomicidade — Aula 15).
-- =====================================================================

BEGIN;

SELECT setseed(0.2026);

-- Função auxiliar só da carga (é removida no final).
CREATE FUNCTION pop_concentrado(n INTEGER, expoente NUMERIC) RETURNS INTEGER AS $$
BEGIN
    RETURN 1 + floor(n * power(random(), expoente))::INTEGER;
END;
$$ LANGUAGE plpgsql VOLATILE;


-- ---------------------------------------------------------------------
-- 1. CONVERSAO — 1.000 moedas (5 reais + 995 fictícias com códigos de 3 letras)
-- ---------------------------------------------------------------------
INSERT INTO conversao (moeda, nome, fator_conver) VALUES
    ('USD', 'Dólar americano', 1.000000),
    ('BRL', 'Real',            0.180000),
    ('EUR', 'Euro',            1.080000),
    ('GBP', 'Libra esterlina', 1.270000),
    ('JPY', 'Iene',            0.006700);

INSERT INTO conversao (moeda, nome, fator_conver)
SELECT codigo, 'Moeda ' || codigo, round(exp(random() * 6 - 4)::NUMERIC, 6)  -- fatores entre ~0,018 e ~7,4
  FROM (SELECT chr(65 + (i / 676) % 26) || chr(65 + (i / 26) % 26) || chr(65 + i % 26) AS codigo
          FROM generate_series(0, 17575) i) s
 WHERE codigo NOT IN ('USD', 'BRL', 'EUR', 'GBP', 'JPY')
 ORDER BY random()
 LIMIT 995;


-- ---------------------------------------------------------------------
-- 2. PAIS — 1.000 países (7 reais + 993 fictícios)
-- Os DDIs reais são baixos; como a escolha de país nas próximas etapas favorece os primeiros DDIs,
--   EUA (1) e Brasil (55) acabam concentrando usuários, como na vida real.
-- ---------------------------------------------------------------------
INSERT INTO pais (ddi, nome, moeda_id)
SELECT r.ddi, r.nome, c.id
  FROM (VALUES (1, 'Estados Unidos', 'USD'), (55, 'Brasil', 'BRL'), (44, 'Reino Unido', 'GBP'),
               (81, 'Japão', 'JPY'), (49, 'Alemanha', 'EUR'), (33, 'França', 'EUR'),
               (351, 'Portugal', 'EUR')) AS r(ddi, nome, moeda)
  JOIN conversao c ON c.moeda = r.moeda;

INSERT INTO pais (ddi, nome, moeda_id)
SELECT d, 'País ' || d, m.ids[1 + floor(random() * array_length(m.ids, 1))::INTEGER]
  FROM generate_series(2, 2000) d,
       (SELECT array_agg(id) AS ids FROM conversao) m
 WHERE d NOT IN (1, 55, 44, 81, 49, 33, 351)
 LIMIT 993;


-- ---------------------------------------------------------------------
-- 3. EMPRESA — 1.000
-- ---------------------------------------------------------------------
INSERT INTO empresa (nome, nome_fantasia)
SELECT 'Empresa ' || i || ' S.A.', 'Marca ' || (1 + floor(random() * 700))::INTEGER  -- nomes fantasia se repetem de propósito
  FROM generate_series(1, 1000) i;


-- ---------------------------------------------------------------------
-- 4. EMPRESA_PAIS — sede de cada empresa (concentrada nos países grandes) + 2ª sede para ~metade
-- ---------------------------------------------------------------------
INSERT INTO empresa_pais (nro_empresa, ddi_pais, id_nacional)
SELECT e.nro_empresa, pa.ddis[pop_concentrado(array_length(pa.ddis, 1), 2)], 'ID' || lpad(e.nro_empresa::TEXT, 10, '0')
  FROM empresa e, (SELECT array_agg(ddi ORDER BY ddi) AS ddis FROM pais) pa;

INSERT INTO empresa_pais (nro_empresa, ddi_pais, id_nacional)
SELECT e.nro_empresa, pa.ddis[pop_concentrado(array_length(pa.ddis, 1), 2)], 'ID' || lpad(e.nro_empresa::TEXT, 10, '0')
  FROM empresa e, (SELECT array_agg(ddi ORDER BY ddi) AS ddis FROM pais) pa
 WHERE random() < 0.5
ON CONFLICT DO NOTHING; -- se sortear o mesmo país da 1ª sede, ignora


-- ---------------------------------------------------------------------
-- 5. PLATAFORMA — 1.000 (5 reais + 995 fictícias). qtd_users nasce 0 (trigger T1 conta depois).
-- ---------------------------------------------------------------------
INSERT INTO plataforma (nome, empresa_fund, empresa_respo, data_fund)
SELECT nome, f, CASE WHEN random() < 0.7 THEN f ELSE 1 + floor(random() * 1000)::INTEGER END, data_fund
  FROM (SELECT nome, data_fund, 1 + floor(random() * 1000)::INTEGER AS f
          FROM (VALUES ('YouTube', DATE '2005-02-14'), ('Twitch', DATE '2011-06-06'), ('Kick', DATE '2022-12-06'),
                       ('Facebook Gaming', DATE '2018-06-01'), ('TikTok Live', DATE '2016-09-01')) AS r(nome, data_fund)) s;

INSERT INTO plataforma (nome, empresa_fund, empresa_respo, data_fund)
SELECT 'Plataforma ' || i, f, CASE WHEN random() < 0.7 THEN f ELSE 1 + floor(random() * 1000)::INTEGER END,
       DATE '1998-01-01' + floor(random() * 9500)::INTEGER
  FROM (SELECT i, 1 + floor(random() * 1000)::INTEGER AS f FROM generate_series(1, 995) i) s;


-- ---------------------------------------------------------------------
-- 6 e 7. USUARIO (10.000) e STREAMER_PAIS (2.000)
-- 2.000 streamers por inserir_streamer (usuário + passaporte) e 8.000 usuários comuns por inserir_usuario.
-- País de residência concentrado nos primeiros DDIs.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_paises SMALLINT[];
    v_pais   SMALLINT;
    i        INTEGER;
BEGIN
    SELECT array_agg(ddi ORDER BY ddi) INTO v_paises FROM pais;

    FOR i IN 1..2000 LOOP
        v_pais := v_paises[pop_concentrado(1000, 3)];
        PERFORM inserir_streamer(
            ('streamer_' || i)::VARCHAR,
            ('streamer' || i || '@exemplo.com')::VARCHAR,
            DATE '1975-01-01' + floor(random() * 11000)::INTEGER,
            CASE WHEN random() < 0.8 THEN ('+' || v_pais || ' 9' || lpad(i::TEXT, 8, '0'))::VARCHAR END,
            CASE WHEN random() < 0.9 THEN ('Rua dos Streamers, ' || i)::VARCHAR END,
            v_pais,
            v_pais,
            ('P' || lpad(i::TEXT, 8, '0'))::VARCHAR);
    END LOOP;

    FOR i IN 1..8000 LOOP
        v_pais := v_paises[pop_concentrado(1000, 3)];
        PERFORM inserir_usuario(
            ('usuario_' || i)::VARCHAR,
            ('usuario' || i || '@exemplo.com')::VARCHAR,
            DATE '1960-01-01' + floor(random() * 17000)::INTEGER,
            CASE WHEN random() < 0.8 THEN ('+' || v_pais || ' 8' || lpad(i::TEXT, 8, '0'))::VARCHAR END,
            CASE WHEN random() < 0.9 THEN ('Avenida Principal, ' || i)::VARCHAR END,
            v_pais);
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 8. PLATAFORMA_USUARIO — até 10.000 contas
-- Plataformas concentradas (expoente 3): YouTube e Twitch (ids 1 e 2) ficam com a maioria das contas
--   e centenas de plataformas fictícias ficam com poucas ou nenhuma.
-- Cada streamer tem até 2 contas (para ter canais em plataformas diferentes); 72% dos usuários comuns têm 1
--   (percentual escolhido para o total ficar abaixo do teto de 10.000).
-- nro_conta: (usuário * 7919 + plataforma * 104729) mod 10^9 — único dentro da plataforma porque 7919 é primo
--   e não divide 10^9, então dois usuários nunca caem no mesmo número na mesma plataforma.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_plataformas INTEGER[];
    v_plat        INTEGER;
    r             RECORD;
    k             INTEGER;
BEGIN
    SELECT array_agg(nro_plataforma ORDER BY nro_plataforma) INTO v_plataformas FROM plataforma;

    FOR r IN SELECT u.nro_usuario, (sp.nro_streamer IS NOT NULL) AS eh_streamer
               FROM usuario u
               LEFT JOIN streamer_pais sp ON sp.nro_streamer = u.nro_usuario
              ORDER BY u.nro_usuario
    LOOP
        FOR k IN 1..(CASE WHEN r.eh_streamer THEN 2 WHEN random() < 0.72 THEN 1 ELSE 0 END) LOOP
            v_plat := v_plataformas[pop_concentrado(1000, 3)];
            IF NOT EXISTS (SELECT 1 FROM plataforma_usuario
                            WHERE nro_plataforma = v_plat AND nro_usuario = r.nro_usuario) THEN
                PERFORM inserir_conta_plataforma(r.nro_usuario, v_plat, (r.nro_usuario * 7919 + v_plat * 104729) % 1000000000);
            END IF;
        END LOOP;
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 9. CANAL — 3.000, sempre de um streamer numa plataforma onde ele tem conta (trigger T7 confere)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT pu.nro_usuario, pu.nro_plataforma
               FROM plataforma_usuario pu
               JOIN streamer_pais sp ON sp.nro_streamer = pu.nro_usuario
              ORDER BY random()
              LIMIT 3000
    LOOP
        PERFORM inserir_canal(
            r.nro_usuario,
            r.nro_plataforma,
            ('Canal ' || r.nro_usuario || '-' || r.nro_plataforma)::VARCHAR,
            (CASE WHEN random() < 0.7 THEN 'publico' WHEN random() < 0.67 THEN 'misto' ELSE 'privado' END)::tipo_canal_enum,
            DATE '2010-01-01' + floor(random() * 5000)::INTEGER,
            'Canal de jogos do streamer ' || r.nro_usuario);
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 10. NIVEL_CANAL — 5 níveis para 2.000 canais = 10.000
-- O valor cresce com o nível (nível 1 ≈ US$ 2–5; nível 5 ≈ US$ 50–53).
-- ---------------------------------------------------------------------
INSERT INTO nivel_canal (id_canal, nivel, nome, valor, gif)
SELECT c.id_canal, n,
       (ARRAY['Bronze', 'Prata', 'Ouro', 'Platina', 'Diamante'])[n],
       round((n * n * 1.99 + random() * 3)::NUMERIC, 2),
       'https://cdn.exemplo.com/niveis/' || c.id_canal || '_' || n || '.gif'
  FROM (SELECT id_canal FROM canal ORDER BY id_canal LIMIT 2000) c,
       generate_series(1, 5) n;


-- ---------------------------------------------------------------------
-- 11. INSCRICAO — 10.000 membros vigentes
-- Canal concentrado (poucos canais com muitos membros); nível concentrado no 1 (o mais barato é o mais comum).
-- DISTINCT ON descarta sorteios repetidos do mesmo par (canal, usuário).
-- ---------------------------------------------------------------------
INSERT INTO inscricao (id_canal, nro_usuario, nivel)
SELECT DISTINCT ON (id_canal, nro_usuario) id_canal, nro_usuario, nivel
  FROM (SELECT ca.ids[pop_concentrado(array_length(ca.ids, 1), 3)] AS id_canal,
               us.ids[1 + floor(random() * array_length(us.ids, 1))::INTEGER] AS nro_usuario,
               pop_concentrado(5, 2)::SMALLINT AS nivel
          FROM generate_series(1, 14000),
               (SELECT array_agg(DISTINCT id_canal ORDER BY id_canal) AS ids FROM nivel_canal) ca,
               (SELECT array_agg(nro_usuario) AS ids FROM usuario) us) s
 LIMIT 10000;


-- ---------------------------------------------------------------------
-- 12. PATROCINIO — 1.500 patrocínios vigentes, concentrados nos canais grandes
-- Valor em USD com cauda longa (de ~US$ 150 a ~US$ 22.000).
-- ---------------------------------------------------------------------
INSERT INTO patrocinio (nro_empresa, id_canal, valor)
SELECT DISTINCT ON (nro_empresa, id_canal) nro_empresa, id_canal, valor
  FROM (SELECT 1 + floor(random() * 1000)::INTEGER AS nro_empresa,
               ca.ids[pop_concentrado(array_length(ca.ids, 1), 2)] AS id_canal,
               round(exp(random() * 5 + 5)::NUMERIC, 2) AS valor
          FROM generate_series(1, 2000),
               (SELECT array_agg(id_canal ORDER BY id_canal) AS ids FROM canal) ca) s
 LIMIT 1500;


-- ---------------------------------------------------------------------
-- 13. VIDEO — 10.000, concentrados nos canais grandes (expoente 3)
-- visu_total com cauda longa: a maioria tem poucas centenas de visualizações, poucos passam de 100 mil.
-- A trigger T2 soma visu_total em canal.qtd_visualizacoes.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_canais INTEGER[];
    v_temas  VARCHAR[] := ARRAY['Minecraft', 'Fortnite', 'League of Legends', 'Valorant', 'Counter-Strike 2',
                                'GTA V', 'EA FC', 'Just Chatting', 'Speedrun', 'Retrô'];
    v_total  BIGINT;
    i        INTEGER;
BEGIN
    SELECT array_agg(id_canal ORDER BY id_canal) INTO v_canais FROM canal;

    FOR i IN 1..10000 LOOP
        v_total := floor(exp(random() * 12))::BIGINT;  -- de 1 a ~160 mil
        PERFORM inserir_video(
            v_canais[pop_concentrado(array_length(v_canais, 1), 3)],
            ('Vídeo ' || i)::VARCHAR,
            (TIMESTAMP '2020-01-01' + random() * INTERVAL '2100 days')::TIMESTAMP,
            v_temas[pop_concentrado(10, 2)],
            60 + floor(random() * 14340)::INTEGER,
            floor(v_total * random() * 0.3)::INTEGER,
            v_total);
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 14. PARTICIPA — 3.000 participações de streamers convidados (o dono do canal não entra como convidado)
-- ---------------------------------------------------------------------
INSERT INTO participa (id_video, nro_streamer)
SELECT DISTINCT ON (s.id_video, s.nro_streamer) s.id_video, s.nro_streamer
  FROM (SELECT vi.ids[pop_concentrado(array_length(vi.ids, 1), 2)] AS id_video,
               st.ids[1 + floor(random() * array_length(st.ids, 1))::INTEGER] AS nro_streamer
          FROM generate_series(1, 3500),
               (SELECT array_agg(id_video ORDER BY visu_total DESC) AS ids FROM video) vi,
               (SELECT array_agg(nro_streamer) AS ids FROM streamer_pais) st) s
  JOIN video v  ON v.id_video = s.id_video
  JOIN canal ca ON ca.id_canal = v.id_canal
 WHERE ca.nro_streamer <> s.nro_streamer
 LIMIT 3000;


-- ---------------------------------------------------------------------
-- 15. COMENTARIO — 10.000
-- Vídeos ordenados por visu_total: os mais vistos recebem muito mais comentários (expoente 3).
-- Usuários também concentrados (expoente 1,5): poucos usuários comentam muito.
-- 60% online. A data é até 30 dias depois da postagem do vídeo. O seq vem da trigger T3.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_videos   BIGINT[];
    v_datas    TIMESTAMP[];
    v_usuarios BIGINT[];
    j          INTEGER;
    i          INTEGER;
BEGIN
    SELECT array_agg(id_video ORDER BY visu_total DESC), array_agg(dataH ORDER BY visu_total DESC)
      INTO v_videos, v_datas FROM video;
    SELECT array_agg(nro_usuario ORDER BY random()) INTO v_usuarios FROM usuario;

    FOR i IN 1..10000 LOOP
        j := pop_concentrado(array_length(v_videos, 1), 3);
        PERFORM inserir_comentario(
            v_videos[j],
            v_usuarios[pop_concentrado(array_length(v_usuarios, 1), 1.5)],
            'Comentário número ' || i,
            (v_datas[j] + random() * INTERVAL '30 days')::TIMESTAMP,
            random() < 0.6);
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 16. DOACAO + BITCOIN, PAYPAL, CARTAO_CREDITO, MECANISMO_PLAT — 5.000 doações, 1.250 de cada forma
-- (o mínimo de 1.000 tuplas por subtabela obriga a ter pelo menos 4.000 doações)
-- Comentários sorteados de modo uniforme; como os comentários já se concentram nos vídeos populares,
--   as doações também se concentram. O mesmo comentário pode receber mais de uma doação (seq 2, 3...).
-- Valor na moeda do país de quem doou; status: 65% recebido, 25% lido, 10% recusado.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_comentarios BIGINT[];
    v_datas       TIMESTAMP[];
    v_bandeiras   bandeira_cartao_enum[] := ARRAY['visa', 'mastercard', 'amex', 'elo', 'hipercard', 'diners'];
    v_status      status_doacao_enum;
    v_valor       NUMERIC;
    j             INTEGER;
    i             INTEGER;
BEGIN
    SELECT array_agg(id_comentario ORDER BY id_comentario), array_agg(dataH ORDER BY id_comentario)
      INTO v_comentarios, v_datas FROM comentario;

    FOR i IN 1..5000 LOOP
        j := 1 + floor(random() * array_length(v_comentarios, 1))::INTEGER;
        v_valor := round((exp(random() * 4) + 1)::NUMERIC, 2);
        v_status := CASE WHEN random() < 0.65 THEN 'recebido'
                         WHEN random() < 0.71 THEN 'lido'
                         ELSE 'recusado' END;

        CASE i % 4
            WHEN 0 THEN PERFORM inserir_doacao_bitcoin(v_comentarios[j], v_valor, v_status,
                                    encode(sha256(('tx' || i)::BYTEA), 'hex')::CHAR(64));
            WHEN 1 THEN PERFORM inserir_doacao_paypal(v_comentarios[j], v_valor, v_status,
                                    ('PAY-' || upper(substr(md5(i::TEXT), 1, 17)))::VARCHAR);
            WHEN 2 THEN PERFORM inserir_doacao_cartao(v_comentarios[j], v_valor, v_status,
                                    ('4' || lpad(floor(random() * 1e15)::BIGINT::TEXT, 15, '0'))::VARCHAR,
                                    v_bandeiras[1 + floor(random() * 6)::INTEGER],
                                    v_datas[j]);
            ELSE        PERFORM inserir_doacao_plataforma(v_comentarios[j], v_valor, v_status);
        END CASE;
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- Finalização
-- ---------------------------------------------------------------------
DROP FUNCTION pop_concentrado(INTEGER, NUMERIC);

-- Preenche as visões materializadas (criadas WITH NO DATA no 02).
SELECT atualizar_visoes_materializadas();

-- Atualiza as estatísticas do catálogo (Aula 12): o otimizador usa esses números para estimar a
--   seletividade dos predicados e escolher o plano. Sem ANALYZE ele estimaria às cegas.
ANALYZE;

COMMIT;
