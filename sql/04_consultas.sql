-- =====================================================================
-- 04_consultas.sql — AS 12 CONSULTAS DO ENUNCIADO COMO FUNCTIONS PARAMETRIZADAS (PL/pgSQL)
-- Rodar depois de 03_povoamento.sql.
--
-- Por que function? (consultoria) O SELECT é "fechadinho": para pedir o top 3, o top 5 e o top 10 seria
--   preciso copiar a consulta e trocar o número. A function embrulha o SQL, recebe os parâmetros de busca
--   na assinatura (k, filtros) e pode ser chamada quantas vezes quiser.
--
-- Padrões usados em todas:
--   * RETURNS TABLE (...) + RETURN QUERY: a function devolve linhas, como um SELECT.
--   * Filtro opcional = parâmetro com DEFAULT NULL: chamar sem o parâmetro lista tudo;
--     com o parâmetro, filtra. O teste "(p IS NULL OR coluna = p)" faz isso numa consulta só.
--   * #variable_conflict use_column: os nomes das colunas de saída (ex.: nick) coincidem com colunas das
--     tabelas; a diretiva diz ao PL/pgSQL que, dentro do SQL, o nome se refere à coluna da tabela.
--   * Valores em dólar: patrocínio e níveis já estão em USD; doações são convertidas na mv_doacoes_canal.
--   * Doação "recusado" não conta como receita (só 'recebido' e 'lido').
--   * POLIMORFISMO (sobrecarga): as consultas 5 e 12 têm duas versões com o mesmo nome; o PostgreSQL escolhe
--     a versão pelo TIPO do argumento (INTEGER = número da empresa/plataforma; VARCHAR = nome).
--
-- Exemplos de chamada estão no fim do arquivo.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Consulta 1 — Streamers com mais vídeos publicados, com o total de vídeos e a soma das visualizações.
-- Filtro opcional: plataforma.
-- "Publicados" = vídeos dos canais de que o streamer é dono.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION consulta1_streamers_mais_videos(p_nro_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (nro_streamer BIGINT, nick VARCHAR, qtd_videos BIGINT, total_visualizacoes NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT ca.nro_streamer, u.nick, COUNT(v.id_video), SUM(v.visu_total)
      FROM canal ca
      JOIN video v   ON v.id_canal = ca.id_canal
      JOIN usuario u ON u.nro_usuario = ca.nro_streamer
     WHERE p_nro_plataforma IS NULL OR ca.nro_plataforma = p_nro_plataforma
     GROUP BY ca.nro_streamer, u.nick
     ORDER BY COUNT(v.id_video) DESC, SUM(v.visu_total) DESC;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- Consulta 2 — Vídeos com mais comentários: online, offline e total. Filtro opcional: canal.
-- Usa a visão materializada mv_interacoes_video (contagem já pronta).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION consulta2_videos_mais_comentados(p_id_canal INTEGER DEFAULT NULL)
RETURNS TABLE (id_video BIGINT, titulo VARCHAR, id_canal INTEGER, nome_canal VARCHAR,
               qtd_online BIGINT, qtd_offline BIGINT, qtd_total BIGINT) AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT m.id_video, v.titulo, m.id_canal, ca.nome_canal, m.qtd_online, m.qtd_offline, m.qtd_total
      FROM mv_interacoes_video m
      JOIN video v  ON v.id_video = m.id_video
      JOIN canal ca ON ca.id_canal = m.id_canal
     WHERE m.qtd_total > 0
       AND (p_id_canal IS NULL OR m.id_canal = p_id_canal)
     ORDER BY m.qtd_total DESC, m.qtd_online DESC;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- Consulta 3 — Canais pelo total de interações (comentários online + offline de todos os vídeos),
-- com a média de interações por vídeo. Filtro opcional: streamer (dono do canal).
-- A média considera todos os vídeos do canal, inclusive os sem comentário (por isso a visão usa LEFT JOIN).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION consulta3_canais_mais_interacoes(p_nro_streamer BIGINT DEFAULT NULL)
RETURNS TABLE (id_canal INTEGER, nome_canal VARCHAR, nick_streamer VARCHAR, qtd_videos BIGINT,
               total_interacoes NUMERIC, media_por_video NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT ci.id_canal, ci.nome_canal, ci.nick_streamer, COUNT(*),
           SUM(m.qtd_total), round(AVG(m.qtd_total), 2)
      FROM mv_interacoes_video m
      JOIN vw_canal_info ci ON ci.id_canal = m.id_canal
     WHERE p_nro_streamer IS NULL OR ci.nro_streamer = p_nro_streamer
     GROUP BY ci.id_canal, ci.nome_canal, ci.nick_streamer
     ORDER BY SUM(m.qtd_total) DESC;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- Consulta 4 — Canais pelo valor médio das doações recebidas por comentário, com a quantidade de doações
-- e o total recebido (USD). Filtro opcional: plataforma.
-- Média por comentário = total recebido / nº de comentários que trouxeram doação.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION consulta4_canais_media_doacao(p_nro_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (id_canal INTEGER, nome_canal VARCHAR, nome_plataforma VARCHAR, qtd_doacoes BIGINT,
               total_usd NUMERIC, media_por_comentario_usd NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT ci.id_canal, ci.nome_canal, ci.nome_plataforma, d.qtd_doacoes, d.total_usd,
           round(d.total_usd / d.qtd_comentarios_com_doacao, 2)
      FROM mv_doacoes_canal d
      JOIN vw_canal_info ci ON ci.id_canal = d.id_canal
     WHERE p_nro_plataforma IS NULL OR ci.nro_plataforma = p_nro_plataforma
     ORDER BY round(d.total_usd / d.qtd_comentarios_com_doacao, 2) DESC;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- Consulta 5 — Canais patrocinados e o valor pago por cada empresa. Filtro opcional: empresa.
-- POLIMÓRFICA: versão 1 filtra pelo número da empresa (INTEGER); versão 2, pelo nome (VARCHAR).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION consulta5_patrocinios(p_nro_empresa INTEGER DEFAULT NULL)
RETURNS TABLE (nro_empresa INTEGER, nome_empresa VARCHAR, id_canal INTEGER, nome_canal VARCHAR,
               valor_usd NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT e.nro_empresa, e.nome, ca.id_canal, ca.nome_canal, pt.valor
      FROM patrocinio pt
      JOIN empresa e ON e.nro_empresa = pt.nro_empresa
      JOIN canal ca  ON ca.id_canal = pt.id_canal
     WHERE p_nro_empresa IS NULL OR pt.nro_empresa = p_nro_empresa
     ORDER BY e.nro_empresa, pt.valor DESC;
END;
$$ LANGUAGE plpgsql;

-- Versão 2 (sobrecarga): mesmo nome, parâmetro VARCHAR. Converte o nome no número e reaproveita a versão 1.
CREATE OR REPLACE FUNCTION consulta5_patrocinios(p_nome_empresa VARCHAR)
RETURNS TABLE (nro_empresa INTEGER, nome_empresa VARCHAR, id_canal INTEGER, nome_canal VARCHAR,
               valor_usd NUMERIC) AS $$
DECLARE
    v_nro empresa.nro_empresa%TYPE;
BEGIN
    SELECT e.nro_empresa INTO v_nro FROM empresa e WHERE e.nome = p_nome_empresa;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Empresa "%" não existe', p_nome_empresa;
    END IF;
    RETURN QUERY SELECT * FROM consulta5_patrocinios(v_nro);
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- Consulta 6 — De quantos canais cada usuário é membro e quanto ele desembolsa por mês. Filtro opcional: usuário.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION consulta6_membros_por_usuario(p_nro_usuario BIGINT DEFAULT NULL)
RETURNS TABLE (nro_usuario BIGINT, nick VARCHAR, qtd_canais BIGINT, total_mensal_usd NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT u.nro_usuario, u.nick, COUNT(*), SUM(n.valor)
      FROM inscricao i
      JOIN nivel_canal n ON n.id_canal = i.id_canal AND n.nivel = i.nivel
      JOIN usuario u     ON u.nro_usuario = i.nro_usuario
     WHERE p_nro_usuario IS NULL OR i.nro_usuario = p_nro_usuario
     GROUP BY u.nro_usuario, u.nick
     ORDER BY COUNT(*) DESC, SUM(n.valor) DESC;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- Consulta 7 — Canais que já receberam doações e a soma recebida (USD). Filtro opcional: canal.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION consulta7_canais_com_doacoes(p_id_canal INTEGER DEFAULT NULL)
RETURNS TABLE (id_canal INTEGER, nome_canal VARCHAR, qtd_doacoes BIGINT, total_usd NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT d.id_canal, ca.nome_canal, d.qtd_doacoes, d.total_usd
      FROM mv_doacoes_canal d
      JOIN canal ca ON ca.id_canal = d.id_canal
     WHERE p_id_canal IS NULL OR d.id_canal = p_id_canal
     ORDER BY d.total_usd DESC;
END;
$$ LANGUAGE plpgsql;


-- Validação comum das consultas top-k: k precisa ser um inteiro positivo.
CREATE OR REPLACE FUNCTION valida_k(k INTEGER) RETURNS VOID AS $$
BEGIN
    IF k IS NULL OR k <= 0 THEN
        RAISE EXCEPTION 'k deve ser um inteiro positivo (recebido: %)', k;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- Consulta 8 — Top-k canais que mais recebem patrocínio, com os valores recebidos.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION consulta8_top_k_patrocinio(k INTEGER)
RETURNS TABLE (id_canal INTEGER, nome_canal VARCHAR, qtd_patrocinadores BIGINT, total_patrocinio_usd NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    PERFORM valida_k(k);
    RETURN QUERY
    SELECT ca.id_canal, ca.nome_canal, COUNT(*), SUM(pt.valor)
      FROM patrocinio pt
      JOIN canal ca ON ca.id_canal = pt.id_canal
     GROUP BY ca.id_canal, ca.nome_canal
     ORDER BY SUM(pt.valor) DESC
     LIMIT k;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- Consulta 9 — Top-k canais que mais recebem aportes de membros (valor mensal), com os valores.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION consulta9_top_k_membros(k INTEGER)
RETURNS TABLE (id_canal INTEGER, nome_canal VARCHAR, qtd_membros BIGINT, total_mensal_usd NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    PERFORM valida_k(k);
    RETURN QUERY
    SELECT m.id_canal, ca.nome_canal, m.qtd_membros, m.total_mensal_usd
      FROM vw_membros_canal m
      JOIN canal ca ON ca.id_canal = m.id_canal
     ORDER BY m.total_mensal_usd DESC
     LIMIT k;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- Consulta 10 — Top-k canais que mais receberam doações, considerando todos os vídeos.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION consulta10_top_k_doacoes(k INTEGER)
RETURNS TABLE (id_canal INTEGER, nome_canal VARCHAR, qtd_doacoes BIGINT, total_usd NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    PERFORM valida_k(k);
    RETURN QUERY
    SELECT d.id_canal, ca.nome_canal, d.qtd_doacoes, d.total_usd
      FROM mv_doacoes_canal d
      JOIN canal ca ON ca.id_canal = d.id_canal
     ORDER BY d.total_usd DESC
     LIMIT k;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- Consulta 11 — Top-k canais que mais faturam POR MÊS, somando patrocínio, membros e doações.
-- Granularidade mensal (consultoria 2: não se soma dia com mês e com ano): membros já é mensalidade,
--   o patrocínio vigente é tratado como valor mensal e as doações entram pela média mensal do canal
--   (mv_doacoes_canal.media_mensal_usd). A justificativa completa está na vw_faturamento_canal (02).
-- Mostra cada parcela separada, para se ver de onde vem o dinheiro.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION consulta11_top_k_faturamento(k INTEGER)
RETURNS TABLE (id_canal INTEGER, nome_canal VARCHAR, receita_patrocinio NUMERIC, receita_membros NUMERIC,
               receita_doacoes NUMERIC, receita_total NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    PERFORM valida_k(k);
    RETURN QUERY
    SELECT f.id_canal, ca.nome_canal, f.receita_patrocinio, f.receita_membros, f.receita_doacoes, f.receita_total
      FROM vw_faturamento_canal f
      JOIN canal ca ON ca.id_canal = f.id_canal
     ORDER BY f.receita_total DESC
     LIMIT k;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- Consulta 12 (DESAFIO) — Top-k plataformas pela quantidade de streamers E de canais.
-- Consultoria 2: a análise considera três agrupamentos, numa consulta só:
--   1. STREAMER: streamers (usuários com passaporte em streamer_pais) que têm conta na plataforma;
--   2. CANAL: canais da plataforma;
--   3. STREAMER + CANAL juntos: streamers que, além da conta, são donos de pelo menos um canal nela
--      (e, a partir daí, a média de canais por streamer com canal).
-- Como a consulta junta as três contagens:
--   * parte de plataforma_usuario (as contas) filtrada por streamer_pais -> agrupamento 1;
--   * LEFT JOIN em canal pelo PAR (plataforma, dono): cada conta encontra só os próprios canais naquela
--     plataforma, então a junção não multiplica linhas (é no máximo 1 linha por canal) -> agrupamentos 2 e 3.
--     O LEFT mantém o streamer que tem conta mas não tem canal (ele conta em 1, mas não em 2 nem 3).
--     Nenhum canal fica de fora: a trigger T7 garante que o dono de todo canal tem conta na plataforma.
--   * LEFT JOIN em plataforma -> streamer: plataformas sem nenhum streamer aparecem com zero.
-- Ordem: streamers, depois canais (o "E" do enunciado), e por fim streamers com canal como desempate.
-- Filtro opcional: plataforma.
-- POLIMÓRFICA: versão 1 filtra pelo número da plataforma (INTEGER); versão 2, pelo nome (VARCHAR).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION consulta12_top_k_plataformas(k INTEGER, p_nro_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (nro_plataforma INTEGER, nome VARCHAR, qtd_streamers BIGINT, qtd_canais BIGINT,
               qtd_streamers_com_canal BIGINT, media_canais_por_streamer NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    PERFORM valida_k(k);
    RETURN QUERY
    SELECT p.nro_plataforma,
           p.nome,
           COUNT(DISTINCT s.nro_usuario)  AS qtd_streamers,            -- agrupamento 1: streamer
           COUNT(ca.id_canal)             AS qtd_canais,               -- agrupamento 2: canal
           COUNT(DISTINCT ca.nro_streamer) AS qtd_streamers_com_canal, -- agrupamento 3: streamer + canal
           ROUND(COUNT(ca.id_canal)::NUMERIC / NULLIF(COUNT(DISTINCT ca.nro_streamer), 0), 2)
      FROM plataforma p
      LEFT JOIN (SELECT pu.nro_plataforma, pu.nro_usuario
                   FROM plataforma_usuario pu
                  WHERE EXISTS (SELECT 1 FROM streamer_pais sp WHERE sp.nro_streamer = pu.nro_usuario)) s
             ON s.nro_plataforma = p.nro_plataforma
      LEFT JOIN canal ca
             ON ca.nro_plataforma = s.nro_plataforma AND ca.nro_streamer = s.nro_usuario
     WHERE p_nro_plataforma IS NULL OR p.nro_plataforma = p_nro_plataforma
     GROUP BY p.nro_plataforma, p.nome
     ORDER BY COUNT(DISTINCT s.nro_usuario) DESC, COUNT(ca.id_canal) DESC, COUNT(DISTINCT ca.nro_streamer) DESC
     LIMIT k;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION consulta12_top_k_plataformas(k INTEGER, p_nome_plataforma VARCHAR)
RETURNS TABLE (nro_plataforma INTEGER, nome VARCHAR, qtd_streamers BIGINT, qtd_canais BIGINT,
               qtd_streamers_com_canal BIGINT, media_canais_por_streamer NUMERIC) AS $$
DECLARE
    v_nro plataforma.nro_plataforma%TYPE;
BEGIN
    SELECT p.nro_plataforma INTO v_nro FROM plataforma p WHERE p.nome = p_nome_plataforma;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Plataforma "%" não existe', p_nome_plataforma;
    END IF;
    RETURN QUERY SELECT * FROM consulta12_top_k_plataformas(k, v_nro);
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
-- EXEMPLOS DE CHAMADA (descomente para rodar no psql)
-- =====================================================================
-- SELECT * FROM consulta1_streamers_mais_videos() LIMIT 10;          -- todas as plataformas
-- SELECT * FROM consulta1_streamers_mais_videos(1) LIMIT 10;         -- só a plataforma 1 (YouTube)
-- SELECT * FROM consulta2_videos_mais_comentados() LIMIT 10;
-- SELECT * FROM consulta2_videos_mais_comentados(1);                 -- só o canal 1
-- SELECT * FROM consulta3_canais_mais_interacoes() LIMIT 10;
-- SELECT * FROM consulta3_canais_mais_interacoes(5);                 -- só os canais do streamer 5
-- SELECT * FROM consulta4_canais_media_doacao() LIMIT 10;
-- SELECT * FROM consulta4_canais_media_doacao(2) LIMIT 10;           -- só a Twitch
-- SELECT * FROM consulta5_patrocinios() LIMIT 10;
-- SELECT * FROM consulta5_patrocinios(10);                           -- versão INTEGER
-- SELECT * FROM consulta5_patrocinios('Empresa 10 S.A.');            -- versão VARCHAR (sobrecarga)
-- SELECT * FROM consulta6_membros_por_usuario() LIMIT 10;
-- SELECT * FROM consulta6_membros_por_usuario(42);
-- SELECT * FROM consulta7_canais_com_doacoes() LIMIT 10;
-- SELECT * FROM consulta7_canais_com_doacoes(1);
-- SELECT * FROM consulta8_top_k_patrocinio(5);
-- SELECT * FROM consulta9_top_k_membros(5);
-- SELECT * FROM consulta10_top_k_doacoes(5);
-- SELECT * FROM consulta11_top_k_faturamento(5);
-- SELECT * FROM consulta12_top_k_plataformas(5);
-- SELECT * FROM consulta12_top_k_plataformas(5, 2);                  -- versão INTEGER
-- SELECT * FROM consulta12_top_k_plataformas(5, 'Twitch');           -- versão VARCHAR (sobrecarga)
