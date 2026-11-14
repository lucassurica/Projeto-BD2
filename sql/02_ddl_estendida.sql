-- 02_ddl_estendida.sql — DDL ESTENDIDA
-- Rodar depois de 01_ddl.sql.
--
-- Parte 1 — Triggers (T1 a T7)
-- Parte 2 — Functions de inserção
-- Parte 3 — Visões (V1 a V5)
--
-- Sintaxe: seguimos a da Aula 13 . No PostgreSQL 11+ "EXECUTE PROCEDURE" é sinônimo de "EXECUTE FUNCTION"; os dois funcionam.

-- Convenções: p_ = parâmetro, v_ = variável local.
--   PREMISSA = interpretação nossa do enunciado; LIMITAÇÃO = o que o código não cobre.


-- #####################################################################
-- PARTE 1 — TRIGGERS (T1 a T7)
-- #####################################################################


-- T1. plataforma.qtd_users — derivado: nº de contas em plataforma_usuario
-- AFTER: o contador só deve refletir contas que já passaram nas constraints.
-- Descartado: COUNT(*) a cada leitura. O enunciado pede o atributo, e ler o total é muito
--   mais frequente do que criar contas.
CREATE OR REPLACE FUNCTION fn_atualiza_qtd_users() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE plataforma SET qtd_users = qtd_users + 1 WHERE nro_plataforma = NEW.nro_plataforma;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE plataforma SET qtd_users = qtd_users - 1 WHERE nro_plataforma = OLD.nro_plataforma;
    ELSIF TG_OP = 'UPDATE' AND NEW.nro_plataforma <> OLD.nro_plataforma THEN
        -- A conta mudou de plataforma: sai de uma e entra na outra.
        UPDATE plataforma SET qtd_users = qtd_users - 1 WHERE nro_plataforma = OLD.nro_plataforma;
        UPDATE plataforma SET qtd_users = qtd_users + 1 WHERE nro_plataforma = NEW.nro_plataforma;
    END IF;
    RETURN NULL; -- em trigger AFTER o retorno é ignorado
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_plataforma_usuario_qtd
AFTER INSERT OR DELETE OR UPDATE OF nro_plataforma ON plataforma_usuario
FOR EACH ROW EXECUTE PROCEDURE fn_atualiza_qtd_users();


-- Proteção: Só a T1 altera qtd_users.
-- T1b. Proteção de plataforma.qtd_users: só a T1 pode alterá-lo.
-- Trigger BEFORE, e não REVOKE nem coluna gerada 
-- pg_trigger_depth() = 1 é UPDATE direto do usuário; = 2 é o UPDATE feito de dentro da T1.
CREATE OR REPLACE FUNCTION fn_protege_qtd_users() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.qtd_users := 0; -- toda plataforma nasce sem contas
    ELSIF NEW.qtd_users IS DISTINCT FROM OLD.qtd_users AND pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION 'qtd_users é derivado de plataforma_usuario e não pode ser alterado diretamente';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_plataforma_protege_qtd
BEFORE INSERT OR UPDATE ON plataforma
FOR EACH ROW EXECUTE PROCEDURE fn_protege_qtd_users();


-- T2. canal.qtd_visualizacoes — derivado: soma de video.visu_total do canal
-- Soma o delta (tira o valor antigo, põe o novo) em vez de recalcular a soma inteira.
CREATE OR REPLACE FUNCTION fn_atualiza_qtd_visualizacoes() RETURNS trigger AS $$
BEGIN
    -- Tira do canal de origem; se o UPDATE trocou o vídeo de canal, é aqui que o antigo perde.
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        UPDATE canal SET qtd_visualizacoes = qtd_visualizacoes - OLD.visu_total WHERE id_canal = OLD.id_canal;
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        UPDATE canal SET qtd_visualizacoes = qtd_visualizacoes + NEW.visu_total WHERE id_canal = NEW.id_canal;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_video_qtd_visualizacoes
AFTER INSERT OR DELETE OR UPDATE OF visu_total, id_canal ON video
FOR EACH ROW EXECUTE PROCEDURE fn_atualiza_qtd_visualizacoes();


-- Proteção de canal.qtd_visualizacoes: mesma ideia da T1.
-- T2b. Proteção de canal.qtd_visualizacoes: mesma ideia da T1b.
CREATE OR REPLACE FUNCTION fn_protege_qtd_visualizacoes() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.qtd_visualizacoes := 0; -- todo canal nasce sem vídeos
    ELSIF NEW.qtd_visualizacoes IS DISTINCT FROM OLD.qtd_visualizacoes AND pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION 'qtd_visualizacoes é derivado de video.visu_total e não pode ser alterado diretamente';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_canal_protege_qtd
BEFORE INSERT OR UPDATE ON canal
FOR EACH ROW EXECUTE PROCEDURE fn_protege_qtd_visualizacoes();


-- T3. comentario.seq — sequencial dentro do vídeo (1, 2, 3...)
-- BEFORE: NEW.seq precisa estar preenchido antes de gravar. No UPDATE só impede mudar seq e id_video.
-- Não é SEQUENCE porque ela é global, e aqui a contagem recomeça em cada vídeo.
-- Concorrência: FOR UPDATE na linha do vídeo serializa os inserts. O MAX(seq) usa
--   o índice de UNIQUE (id_video, seq).
-- LIMITAÇÃO: se o último comentário for apagado, o próximo reaproveita o número.
CREATE OR REPLACE FUNCTION fn_comentario_seq() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.seq <> OLD.seq OR NEW.id_video <> OLD.id_video THEN
            RAISE EXCEPTION 'O vídeo e o sequencial de um comentário não podem ser alterados';
        END IF;
        RETURN NEW;
    END IF;

    -- Trava o vídeo para serializar os inserts; o resultado do SELECT é descartado.
    PERFORM 1 FROM video WHERE id_video = NEW.id_video FOR UPDATE;
    SELECT COALESCE(MAX(seq), 0) + 1 INTO NEW.seq
      FROM comentario
     WHERE id_video = NEW.id_video;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_comentario_seq
BEFORE INSERT OR UPDATE ON comentario
FOR EACH ROW EXECUTE PROCEDURE fn_comentario_seq();


-- T4. doacao.seq_doacao — sequencial dentro do comentário
-- Mesma lógica e mesma LIMITAÇÃO da T3, travando a linha do comentário.
CREATE OR REPLACE FUNCTION fn_doacao_seq() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.seq_doacao <> OLD.seq_doacao OR NEW.id_comentario <> OLD.id_comentario THEN
            RAISE EXCEPTION 'O comentário e o sequencial de uma doação não podem ser alterados';
        END IF;
        RETURN NEW;
    END IF;

    PERFORM 1 FROM comentario WHERE id_comentario = NEW.id_comentario FOR UPDATE;
    SELECT COALESCE(MAX(seq_doacao), 0) + 1 INTO NEW.seq_doacao
      FROM doacao
     WHERE id_comentario = NEW.id_comentario;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_doacao_seq
BEFORE INSERT OR UPDATE ON doacao
FOR EACH ROW EXECUTE PROCEDURE fn_doacao_seq();


-- T5. mecanismo_plat.seq_plataforma — sequencial por (usuário, plataforma)
-- Ex.: o 5º Super Chat que o usuário fez no YouTube recebe 5.
-- PREMISSA: contagem corrente por (usuário, plataforma), somando os comentários do usuário na plataforma.
-- Usuário e plataforma são descobertos pelo caminho doacao -> comentario -> video -> canal.
-- Trava a linha do usuário para que dois Super Chats simultâneos não recebam o mesmo número.
-- O MAX percorre os comentários do usuário: é o motivo do índice I1 .
CREATE OR REPLACE FUNCTION fn_mecanismo_plat_seq() RETURNS trigger AS $$
DECLARE
    v_usuario    usuario.nro_usuario%TYPE;
    v_plataforma plataforma.nro_plataforma%TYPE;
BEGIN
    SELECT c.nro_usuario, ca.nro_plataforma INTO v_usuario, v_plataforma
      FROM doacao d
      JOIN comentario c ON c.id_comentario = d.id_comentario
      JOIN video v      ON v.id_video = c.id_video
      JOIN canal ca     ON ca.id_canal = v.id_canal
     WHERE d.id_doacao = NEW.id_doacao;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Doação % não existe', NEW.id_doacao;
    END IF;

    PERFORM 1 FROM usuario WHERE nro_usuario = v_usuario FOR UPDATE;

    SELECT COALESCE(MAX(m.seq_plataforma), 0) + 1 INTO NEW.seq_plataforma
      FROM mecanismo_plat m
      JOIN doacao d     ON d.id_doacao = m.id_doacao
      JOIN comentario c ON c.id_comentario = d.id_comentario
      JOIN video v      ON v.id_video = c.id_video
      JOIN canal ca     ON ca.id_canal = v.id_canal
     WHERE c.nro_usuario = v_usuario
       AND ca.nro_plataforma = v_plataforma;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_mecanismo_plat_seq
BEFORE INSERT ON mecanismo_plat
FOR EACH ROW EXECUTE PROCEDURE fn_mecanismo_plat_seq();


-- T6. Especialização DISJUNTA de doacao: uma única forma de pagamento
-- A PK de cada subtabela impede repetir na mesma; esta trigger impede estar em duas
--   subtabelas, o que nenhuma constraint declarativa consegue. TG_TABLE_NAME diz qual disparou.
-- LIMITAÇÃO: garante no MÁXIMO uma forma. Pelo menos uma depende das functions
--   inserir_doacao_*; um INSERT direto em doacao pode deixá-la sem forma.
CREATE OR REPLACE FUNCTION fn_doacao_forma_unica() RETURNS trigger AS $$
BEGIN
    IF (TG_TABLE_NAME <> 'bitcoin'        AND EXISTS (SELECT 1 FROM bitcoin        WHERE id_doacao = NEW.id_doacao))
    OR (TG_TABLE_NAME <> 'paypal'         AND EXISTS (SELECT 1 FROM paypal         WHERE id_doacao = NEW.id_doacao))
    OR (TG_TABLE_NAME <> 'cartao_credito' AND EXISTS (SELECT 1 FROM cartao_credito WHERE id_doacao = NEW.id_doacao))
    OR (TG_TABLE_NAME <> 'mecanismo_plat' AND EXISTS (SELECT 1 FROM mecanismo_plat WHERE id_doacao = NEW.id_doacao))
    THEN
        RAISE EXCEPTION 'A doação % já tem outra forma de pagamento (a especialização é disjunta)', NEW.id_doacao;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Um trigger por subtabela, todos com a mesma function.
CREATE TRIGGER trg_bitcoin_forma_unica BEFORE INSERT OR UPDATE OF id_doacao ON bitcoin
FOR EACH ROW EXECUTE PROCEDURE fn_doacao_forma_unica();
CREATE TRIGGER trg_paypal_forma_unica BEFORE INSERT OR UPDATE OF id_doacao ON paypal
FOR EACH ROW EXECUTE PROCEDURE fn_doacao_forma_unica();
CREATE TRIGGER trg_cartao_forma_unica BEFORE INSERT OR UPDATE OF id_doacao ON cartao_credito
FOR EACH ROW EXECUTE PROCEDURE fn_doacao_forma_unica();
CREATE TRIGGER trg_mecanismo_forma_unica BEFORE INSERT OR UPDATE OF id_doacao ON mecanismo_plat
FOR EACH ROW EXECUTE PROCEDURE fn_doacao_forma_unica();


-- T7. Dono de canal precisa ser STREAMER e ter conta na plataforma do canal
-- Requisito: "um ou mais canais estão associados a cada streamer em diferentes plataformas".
-- Streamer = usuário com passaporte em streamer_pais. Regra de negócio estável: fica no banco.
-- LIMITAÇÃO: valida só ao inserir ou atualizar o canal. Apagar depois o passaporte ou a conta
--   de quem já é dono não é verificado.
CREATE OR REPLACE FUNCTION fn_valida_dono_canal() RETURNS trigger AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM streamer_pais WHERE nro_streamer = NEW.nro_streamer) THEN
        RAISE EXCEPTION 'Usuário % não é streamer (não tem passaporte cadastrado)', NEW.nro_streamer;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM plataforma_usuario
                    WHERE nro_usuario = NEW.nro_streamer AND nro_plataforma = NEW.nro_plataforma) THEN
        RAISE EXCEPTION 'Streamer % não tem conta na plataforma %', NEW.nro_streamer, NEW.nro_plataforma;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_canal_valida_dono
BEFORE INSERT OR UPDATE OF nro_streamer, nro_plataforma ON canal
FOR EACH ROW EXECUTE PROCEDURE fn_valida_dono_canal();

-- Participante de vídeo: basta ser streamer.
-- O enunciado diz que o vídeo "pode ter a participação de mais streamers do que apenas o
--   dono do canal". A exigência de conta na plataforma vale só para o dono.
CREATE OR REPLACE FUNCTION fn_valida_participante() RETURNS trigger AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM streamer_pais WHERE nro_streamer = NEW.nro_streamer) THEN
        RAISE EXCEPTION 'Usuário % não é streamer e não pode participar de vídeo', NEW.nro_streamer;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_participa_valida_streamer
BEFORE INSERT OR UPDATE OF nro_streamer ON participa
FOR EACH ROW EXECUTE PROCEDURE fn_valida_participante();


-- #####################################################################
-- PARTE 2 — FUNCTIONS DE INSERÇÃO
-- #####################################################################

-- Usuário comum. Retorna o nro_usuario gerado.
CREATE OR REPLACE FUNCTION inserir_usuario(
    p_nick VARCHAR, p_email VARCHAR, p_data_nasc DATE, p_telefone VARCHAR,
    p_end_postal VARCHAR, p_ddi_residencia SMALLINT
) RETURNS BIGINT AS $$
DECLARE
    v_id usuario.nro_usuario%TYPE;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pais WHERE ddi = p_ddi_residencia) THEN
        RAISE EXCEPTION 'País de residência com DDI % não existe', p_ddi_residencia;
    END IF;
    IF EXISTS (SELECT 1 FROM usuario WHERE nick = p_nick) THEN
        RAISE EXCEPTION 'Já existe usuário com o nick %', p_nick;
    END IF;

    INSERT INTO usuario (nick, email, data_nasc, telefone, end_postal, pais_residencia)
    VALUES (p_nick, p_email, p_data_nasc, p_telefone, p_end_postal, p_ddi_residencia)
    RETURNING nro_usuario INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;


-- Streamer = usuário + passaporte, gravados juntos (ou nenhum dos dois).
CREATE OR REPLACE FUNCTION inserir_streamer(
    p_nick VARCHAR, p_email VARCHAR, p_data_nasc DATE, p_telefone VARCHAR, p_end_postal VARCHAR,
    p_ddi_residencia SMALLINT, p_ddi_passaporte SMALLINT, p_nro_passaporte VARCHAR
) RETURNS BIGINT AS $$
DECLARE
    v_id usuario.nro_usuario%TYPE;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pais WHERE ddi = p_ddi_passaporte) THEN
        RAISE EXCEPTION 'País do passaporte com DDI % não existe', p_ddi_passaporte;
    END IF;

    v_id := inserir_usuario(p_nick, p_email, p_data_nasc, p_telefone, p_end_postal, p_ddi_residencia);

    INSERT INTO streamer_pais (nro_streamer, ddi_pais, nro_passaporte)
    VALUES (v_id, p_ddi_passaporte, p_nro_passaporte);
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;


-- Conta do usuário numa plataforma (a trigger T1 atualiza qtd_users).
CREATE OR REPLACE FUNCTION inserir_conta_plataforma(
    p_nro_usuario BIGINT, p_nro_plataforma INTEGER, p_nro_conta BIGINT
) RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE nro_usuario = p_nro_usuario) THEN
        RAISE EXCEPTION 'Usuário % não existe', p_nro_usuario;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM plataforma WHERE nro_plataforma = p_nro_plataforma) THEN
        RAISE EXCEPTION 'Plataforma % não existe', p_nro_plataforma;
    END IF;

    INSERT INTO plataforma_usuario (nro_plataforma, nro_usuario, nro_conta)
    VALUES (p_nro_plataforma, p_nro_usuario, p_nro_conta);
END;
$$ LANGUAGE plpgsql;


-- Canal. A trigger T7 confere se o dono é streamer e tem conta na plataforma.
CREATE OR REPLACE FUNCTION inserir_canal(
    p_nro_streamer BIGINT, p_nro_plataforma INTEGER, p_nome VARCHAR,
    p_tipo tipo_canal_enum, p_data_inicio DATE, p_descricao TEXT
) RETURNS INTEGER AS $$
DECLARE
    v_id canal.id_canal%TYPE;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM plataforma WHERE nro_plataforma = p_nro_plataforma) THEN
        RAISE EXCEPTION 'Plataforma % não existe', p_nro_plataforma;
    END IF;

    INSERT INTO canal (nome_canal, tipo, data_inicio, descricao, nro_streamer, nro_plataforma)
    VALUES (p_nome, p_tipo, p_data_inicio, p_descricao, p_nro_streamer, p_nro_plataforma)
    RETURNING id_canal INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;


-- Vídeo. A trigger T2 soma visu_total em canal.qtd_visualizacoes.
CREATE OR REPLACE FUNCTION inserir_video(
    p_id_canal INTEGER, p_titulo VARCHAR, p_dataH TIMESTAMP, p_tema VARCHAR,
    p_duracao INTEGER, p_visu_simul INTEGER, p_visu_total BIGINT
) RETURNS BIGINT AS $$
DECLARE
    v_id video.id_video%TYPE;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM canal WHERE id_canal = p_id_canal) THEN
        RAISE EXCEPTION 'Canal % não existe', p_id_canal;
    END IF;

    INSERT INTO video (titulo, dataH, tema, duracao, visu_simul, visu_total, id_canal)
    VALUES (p_titulo, p_dataH, p_tema, p_duracao, p_visu_simul, p_visu_total, p_id_canal)
    RETURNING id_video INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;


-- Comentário. O seq é gerado pela trigger T3 (não é parâmetro).
CREATE OR REPLACE FUNCTION inserir_comentario(
    p_id_video BIGINT, p_nro_usuario BIGINT, p_texto TEXT, p_dataH TIMESTAMP, p_online BOOLEAN
) RETURNS BIGINT AS $$
DECLARE
    v_id comentario.id_comentario%TYPE;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM video WHERE id_video = p_id_video) THEN
        RAISE EXCEPTION 'Vídeo % não existe', p_id_video;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE nro_usuario = p_nro_usuario) THEN
        RAISE EXCEPTION 'Usuário % não existe', p_nro_usuario;
    END IF;

    -- seq recebe 0 só para satisfazer o NOT NULL na sintaxe; a trigger BEFORE INSERT sobrescreve.
    INSERT INTO comentario (id_video, seq, nro_usuario, texto, dataH, coment_on)
    VALUES (p_id_video, 0, p_nro_usuario, p_texto, p_dataH, p_online)
    RETURNING id_comentario INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;


-- Parte comum das 4 formas de doação: grava a linha em doacao e devolve o id.
-- Não é para ser chamada sozinha: uma doação sem forma de pagamento ficaria incompleta.
CREATE OR REPLACE FUNCTION inserir_doacao_base(
    p_id_comentario BIGINT, p_valor NUMERIC, p_status status_doacao_enum
) RETURNS BIGINT AS $$
DECLARE
    v_id doacao.id_doacao%TYPE;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM comentario WHERE id_comentario = p_id_comentario) THEN
        RAISE EXCEPTION 'Comentário % não existe', p_id_comentario;
    END IF;

    INSERT INTO doacao (id_comentario, seq_doacao, valor, status)
    VALUES (p_id_comentario, 0, p_valor, p_status) -- seq_doacao é gerado pela trigger T4
    RETURNING id_doacao INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- As 4 functions abaixo gravam superclasse + subclasse juntas: ou as duas linhas entram, ou nenhuma.
CREATE OR REPLACE FUNCTION inserir_doacao_bitcoin(
    p_id_comentario BIGINT, p_valor NUMERIC, p_status status_doacao_enum, p_txid CHAR(64)
) RETURNS BIGINT AS $$
DECLARE
    v_id doacao.id_doacao%TYPE;
BEGIN
    v_id := inserir_doacao_base(p_id_comentario, p_valor, p_status);
    INSERT INTO bitcoin (id_doacao, txid) VALUES (v_id, p_txid);
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION inserir_doacao_paypal(
    p_id_comentario BIGINT, p_valor NUMERIC, p_status status_doacao_enum, p_id_paypal VARCHAR
) RETURNS BIGINT AS $$
DECLARE
    v_id doacao.id_doacao%TYPE;
BEGIN
    v_id := inserir_doacao_base(p_id_comentario, p_valor, p_status);
    INSERT INTO paypal (id_doacao, id_paypal) VALUES (v_id, p_id_paypal);
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION inserir_doacao_cartao(
    p_id_comentario BIGINT, p_valor NUMERIC, p_status status_doacao_enum,
    p_nro_cartao VARCHAR, p_bandeira bandeira_cartao_enum, p_dataH TIMESTAMP
) RETURNS BIGINT AS $$
DECLARE
    v_id doacao.id_doacao%TYPE;
BEGIN
    v_id := inserir_doacao_base(p_id_comentario, p_valor, p_status);
    INSERT INTO cartao_credito (id_doacao, nro_cartao, bandeira, dataH)
    VALUES (v_id, p_nro_cartao, p_bandeira, p_dataH);
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION inserir_doacao_plataforma(
    p_id_comentario BIGINT, p_valor NUMERIC, p_status status_doacao_enum
) RETURNS BIGINT AS $$
DECLARE
    v_id doacao.id_doacao%TYPE;
BEGIN
    v_id := inserir_doacao_base(p_id_comentario, p_valor, p_status);
    INSERT INTO mecanismo_plat (id_doacao, seq_plataforma) VALUES (v_id, 0); -- seq gerado pela trigger T5
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;


-- #####################################################################
-- PARTE 3 — VISÕES (5 no total, limite do enunciado)
-- #####################################################################

-- V1 (VIRTUAL) vw_canal_info — canal com o nick do dono e o nome da plataforma.
-- Usada para exibir os resultados das consultas com nomes legíveis.
-- Virtual porque é só uma junção de 3 tabelas por chave primária (barata) e não pode ficar desatualizada
--   (um canal novo precisa aparecer na hora).
CREATE OR REPLACE VIEW vw_canal_info AS
SELECT ca.id_canal,
       ca.nome_canal,
       ca.tipo,
       ca.qtd_visualizacoes,
       ca.nro_plataforma,
       p.nome  AS nome_plataforma,
       ca.nro_streamer,
       u.nick  AS nick_streamer
  FROM canal ca
  JOIN plataforma p ON p.nro_plataforma = ca.nro_plataforma
  JOIN usuario u    ON u.nro_usuario = ca.nro_streamer;


-- V2 (MATERIALIZADA) mv_interacoes_video — comentários online, offline e total de cada vídeo.
-- Usada nas consultas 2 e 3. Agrega a tabela comentario, a maior do banco.
-- Materializada porque: a agregação sobre comentario é a parte mais cara dessas consultas, e métricas de
--   interação para ranking toleram alguns minutos de atraso.
-- LEFT JOIN: vídeos sem comentário aparecem com 0 (importa para a média de interações por vídeo da consulta 3).
CREATE MATERIALIZED VIEW mv_interacoes_video AS
SELECT v.id_video,
       v.id_canal,
       COUNT(c.id_comentario) FILTER (WHERE c.coment_on)     AS qtd_online,
       COUNT(c.id_comentario) FILTER (WHERE NOT c.coment_on) AS qtd_offline,
       COUNT(c.id_comentario)                                AS qtd_total
  FROM video v
  LEFT JOIN comentario c ON c.id_video = v.id_video
 GROUP BY v.id_video, v.id_canal
WITH NO DATA; -- os dados entram no REFRESH ao final do povoamento (03)


-- V3 (MATERIALIZADA) mv_doacoes_canal — doações recebidas por canal, já convertidas para dólar.
-- Usada nas consultas 4, 7, 10 e 11. É a consulta mais cara do trabalho: junta 6 tabelas
--   (doacao, comentario, video, usuario, pais, conversao) para converter cada doação para USD.
-- Materializada porque o mesmo resultado serve 4 consultas e o cálculo é pesado.
-- Só entram doações com status 'recebido' ou 'lido': a doação 'recusado' não gerou dinheiro.
-- media_mensal_usd ( consulta 11): a doação não tem periodicidade, então a convertemos para a
--   granularidade MENSAL dividindo o total pelo nº de meses do período em que o canal recebeu doações
--   (do mês da primeira ao mês da última; a data da doação é a do comentário que a trouxe).
--   Um canal que recebeu doações só num mês tem período de 1 mês.
CREATE MATERIALIZED VIEW mv_doacoes_canal AS
SELECT t.id_canal, t.qtd_doacoes, t.qtd_comentarios_com_doacao, t.total_usd, t.meses_com_doacao,
       (t.total_usd / t.meses_com_doacao)::NUMERIC(16, 2) AS media_mensal_usd
  FROM (SELECT v.id_canal,
               COUNT(*)                                       AS qtd_doacoes,
               COUNT(DISTINCT d.id_comentario)                AS qtd_comentarios_com_doacao,
               SUM(d.valor * cv.fator_conver)::NUMERIC(16, 2) AS total_usd,
               -- nº do mês (ano*12 + mês) da última doação menos o da primeira, +1 para contar os dois
               --   (ex.: de janeiro a março = 3 meses).
               (EXTRACT(YEAR FROM MAX(c.dataH)) * 12 + EXTRACT(MONTH FROM MAX(c.dataH))
                - EXTRACT(YEAR FROM MIN(c.dataH)) * 12 - EXTRACT(MONTH FROM MIN(c.dataH)) + 1)::INTEGER
                                                              AS meses_com_doacao
          FROM doacao d
          JOIN comentario c ON c.id_comentario = d.id_comentario
          JOIN video v      ON v.id_video = c.id_video
          JOIN usuario u    ON u.nro_usuario = c.nro_usuario
          JOIN pais pa      ON pa.ddi = u.pais_residencia
          JOIN conversao cv ON cv.id = pa.moeda_id
         WHERE d.status IN ('recebido', 'lido')
         GROUP BY v.id_canal) t
WITH NO DATA;


-- V4 (VIRTUAL) vw_membros_canal — quantos membros e quanto cada canal recebe por mês de membros.
-- Usada nas consultas 9 e 11.
-- Virtual porque junta só 2 tabelas (inscricao e nivel_canal) pela chave (id_canal, nivel), que é a PK
--   de nivel_canal; o custo é baixo e o valor de membros muda todo dia (entradas e saídas).
CREATE OR REPLACE VIEW vw_membros_canal AS
SELECT i.id_canal,
       COUNT(*)     AS qtd_membros,
       SUM(n.valor) AS total_mensal_usd
  FROM inscricao i
  JOIN nivel_canal n ON n.id_canal = i.id_canal AND n.nivel = i.nivel
 GROUP BY i.id_canal;


-- V5 (VIRTUAL) vw_faturamento_canal — o faturamento MENSAL de cada canal, com as três fontes lado a lado.
-- Usada na consulta 11 (e reaproveita V3 e V4).
-- Granularidade: não dá para somar valores de períodos diferentes (por exemplo, dia com mês e com ano).
--   Escolhemos o MÊS, porque é a periodicidade natural de duas das três fontes:
--     * membros: o valor do nível já é uma mensalidade (V4);
--     * patrocínio: guardamos só o contrato vigente (sem histórico), e o tratamos como valor mensal;
--     * doações: não têm periodicidade; usamos a média mensal calculada na V3 (media_mensal_usd).
--   Dia seria fino demais (quase todo dia o canal não recebe doação) e ano exigiria anualizar as
--   mensalidades, que mudam com as entradas e saídas de membros.
-- Virtual porque só combina resultados já agregados (patrocinio é pequena, V4 é barata, V3 já é materializada).
-- Materializar de novo duplicaria dados e criaria mais um REFRESH para manter.
CREATE OR REPLACE VIEW vw_faturamento_canal AS
SELECT ca.id_canal,
       COALESCE(pt.total_patrocinio, 0) AS receita_patrocinio,
       COALESCE(m.total_mensal_usd, 0)  AS receita_membros,
       COALESCE(d.media_mensal_usd, 0)  AS receita_doacoes,
       COALESCE(pt.total_patrocinio, 0) + COALESCE(m.total_mensal_usd, 0) + COALESCE(d.media_mensal_usd, 0)
                                        AS receita_total
  FROM canal ca
  LEFT JOIN (SELECT id_canal, SUM(valor) AS total_patrocinio FROM patrocinio GROUP BY id_canal) pt
         ON pt.id_canal = ca.id_canal
  LEFT JOIN vw_membros_canal m ON m.id_canal = ca.id_canal
  LEFT JOIN mv_doacoes_canal d ON d.id_canal = ca.id_canal;


-- Atualiza as duas visões materializadas. Chamada ao fim do povoamento e, em produção, por um agendador.
CREATE OR REPLACE FUNCTION atualizar_visoes_materializadas() RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_interacoes_video;
    REFRESH MATERIALIZED VIEW mv_doacoes_canal;
END;
$$ LANGUAGE plpgsql;
