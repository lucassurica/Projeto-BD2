-- =====================================================================
-- 02_ddl_estendida.sql — DDL ESTENDIDA
-- Triggers de consistência, functions de inserção e visões (virtuais e materializadas).
-- Rodar depois de 01_ddl.sql.
--
-- Sintaxe: seguimos a da Aula 13 (CREATE OR REPLACE FUNCTION ... $$ LANGUAGE plpgsql e
--   CREATE TRIGGER ... EXECUTE PROCEDURE). No PostgreSQL 11+ "EXECUTE PROCEDURE" é sinônimo de
--   "EXECUTE FUNCTION"; os dois funcionam.
-- =====================================================================


-- #####################################################################
-- PARTE 1 — TRIGGERS
-- Cada trigger é descrita pelos 3 conceitos da aula: EVENTO (INSERT/UPDATE/DELETE),
--   TIMING (BEFORE/AFTER) e NÍVEL (ROW/STATEMENT).
-- #####################################################################


-- ---------------------------------------------------------------------
-- T1. plataforma.qtd_users — atributo derivado (= nº de contas em plataforma_usuario)
-- Evento: INSERT, DELETE e UPDATE de nro_plataforma em plataforma_usuario.
-- Timing: AFTER — só atualiza o contador depois que a conta foi de fato gravada (se o INSERT falhar, nada muda).
-- Nível: ROW — cada conta criada/removida soma/subtrai 1.
-- Alternativa considerada: recalcular COUNT(*) a cada leitura (sem coluna). Descartada porque o enunciado
--   pede o atributo e a leitura do total é muito mais frequente que a criação de contas.
-- ---------------------------------------------------------------------
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


-- Proteção: ninguém altera qtd_users "na mão"; só a trigger acima.
-- Evento: INSERT e UPDATE em plataforma. Timing: BEFORE (corrige/bloqueia antes de gravar). Nível: ROW.
-- pg_trigger_depth() = 1 quando o UPDATE veio direto do usuário; = 2 quando veio de dentro da trigger T1.
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


-- ---------------------------------------------------------------------
-- T2. canal.qtd_visualizacoes — atributo derivado (= soma de video.visu_total do canal)
-- Evento: INSERT, DELETE e UPDATE de visu_total/id_canal em video. Timing: AFTER. Nível: ROW.
-- Soma a diferença (delta) em vez de recalcular a soma inteira: custo constante por vídeo.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_atualiza_qtd_visualizacoes() RETURNS trigger AS $$
BEGIN
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


-- Proteção de canal.qtd_visualizacoes (mesma ideia da proteção de qtd_users).
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


-- ---------------------------------------------------------------------
-- T3. comentario.seq — sequencial do comentário dentro do vídeo (1, 2, 3...)
-- Evento: INSERT. Timing: BEFORE — precisamos preencher NEW.seq antes de gravar. Nível: ROW.
-- Por que não uma SEQUENCE? Uma SEQUENCE é global; aqui a contagem recomeça em cada vídeo.
-- Concorrência: SELECT ... FOR UPDATE trava a linha do vídeo até o fim da transação; dois comentários
--   simultâneos no mesmo vídeo esperam um pelo outro e não recebem o mesmo seq (Aula 15 — Transações).
-- O MAX(seq) usa o índice da constraint UNIQUE (id_video, seq), então é barato.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_comentario_seq() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.seq <> OLD.seq OR NEW.id_video <> OLD.id_video THEN
            RAISE EXCEPTION 'O vídeo e o sequencial de um comentário não podem ser alterados';
        END IF;
        RETURN NEW;
    END IF;

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


-- ---------------------------------------------------------------------
-- T4. doacao.seq_doacao — sequencial da doação dentro do comentário
-- Mesma lógica de T3, travando a linha do comentário.
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- T5. mecanismo_plat.seq_plataforma — sequencial por (usuário, plataforma)
-- Ex.: o 5º Super Chat que o usuário fez no YouTube recebe 5.
-- Evento: INSERT. Timing: BEFORE. Nível: ROW.
-- Usuário e plataforma são descobertos pelo caminho doacao -> comentario -> video -> canal.
-- Trava a linha do usuário para dois Super Chats simultâneos não pegarem o mesmo número.
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- T6. Especialização DISJUNTA de doacao ("d" no modelo ER)
-- Uma doação é de UMA só forma: bitcoin OU paypal OU cartão OU mecanismo da plataforma.
-- A PK de cada subtabela já impede repetir a doação na mesma subtabela; esta trigger impede
--   que ela apareça em duas subtabelas diferentes, o que nenhuma constraint declarativa consegue.
-- Evento: INSERT e UPDATE de id_doacao nas 4 subtabelas. Timing: BEFORE (bloqueia antes de gravar). Nível: ROW.
-- Uma só função serve as 4 tabelas: a variável automática TG_TABLE_NAME diz qual delas disparou.
-- ---------------------------------------------------------------------
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

CREATE TRIGGER trg_bitcoin_forma_unica BEFORE INSERT OR UPDATE OF id_doacao ON bitcoin
FOR EACH ROW EXECUTE PROCEDURE fn_doacao_forma_unica();
CREATE TRIGGER trg_paypal_forma_unica BEFORE INSERT OR UPDATE OF id_doacao ON paypal
FOR EACH ROW EXECUTE PROCEDURE fn_doacao_forma_unica();
CREATE TRIGGER trg_cartao_forma_unica BEFORE INSERT OR UPDATE OF id_doacao ON cartao_credito
FOR EACH ROW EXECUTE PROCEDURE fn_doacao_forma_unica();
CREATE TRIGGER trg_mecanismo_forma_unica BEFORE INSERT OR UPDATE OF id_doacao ON mecanismo_plat
FOR EACH ROW EXECUTE PROCEDURE fn_doacao_forma_unica();


-- ---------------------------------------------------------------------
-- T7. Dono de canal e participante de vídeo precisam ser STREAMERS
-- Requisito: "um ou mais canais estão associados a cada streamer em diferentes plataformas".
-- Streamer = usuário com passaporte em streamer_pais. Além disso, o dono precisa ter conta
--   (plataforma_usuario) na plataforma do canal.
-- É uma regra de negócio estável, por isso fica no banco (orientação da consultoria).
-- Evento: INSERT e UPDATE das colunas envolvidas. Timing: BEFORE. Nível: ROW.
-- ---------------------------------------------------------------------
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
-- Orientação da consultoria: inserir por meio de functions que validam antes ("garantir que existe
--   a plataforma, para depois inserir o streamer").
-- Ganhos: (1) mensagens de erro claras em vez do erro genérico de FK; (2) inserções que envolvem
--   várias tabelas viram uma operação só; (3) ATOMICIDADE: uma function roda inteira dentro da
--   transação de quem a chamou — se qualquer passo falhar, tudo o que ela fez é desfeito (rollback).
-- Tabelas simples de domínio (pais, conversao, empresa...) são inseridas com INSERT direto no 03.
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
--
-- Critério de escolha entre VIRTUAL e MATERIALIZADA:
--   VIRTUAL: é só uma consulta guardada; roda de novo a cada uso (Aula 14). Sempre atual, não ocupa disco.
--     Boa quando a consulta por trás é barata (poucas tabelas, tabelas pequenas) ou quando o dado
--     precisa estar sempre atualizado.
--   MATERIALIZADA: o resultado é gravado em disco e só muda no REFRESH. Leitura muito barata, mas o
--     dado pode ficar desatualizado entre um refresh e outro. Boa quando a consulta é cara (junções e
--     agregações sobre as tabelas grandes) e é lida muito mais vezes do que os dados mudam.
-- Política de atualização das materializadas: REFRESH periódico (ex.: a cada hora ou de madrugada, via
--   agendador) e ao final da carga, pela function atualizar_visoes_materializadas().
--   Não usamos trigger de REFRESH: a cada comentário inserido o banco recalcularia tudo, anulando o ganho.
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
CREATE MATERIALIZED VIEW mv_doacoes_canal AS
SELECT v.id_canal,
       COUNT(*)                                   AS qtd_doacoes,
       COUNT(DISTINCT d.id_comentario)            AS qtd_comentarios_com_doacao,
       SUM(d.valor * cv.fator_conver)::NUMERIC(16, 2) AS total_usd
  FROM doacao d
  JOIN comentario c ON c.id_comentario = d.id_comentario
  JOIN video v      ON v.id_video = c.id_video
  JOIN usuario u    ON u.nro_usuario = c.nro_usuario
  JOIN pais pa      ON pa.ddi = u.pais_residencia
  JOIN conversao cv ON cv.id = pa.moeda_id
 WHERE d.status IN ('recebido', 'lido')
 GROUP BY v.id_canal
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


-- V5 (VIRTUAL) vw_faturamento_canal — as três fontes de receita de cada canal lado a lado.
-- Usada na consulta 11 (e reaproveita V3 e V4).
-- Virtual porque só combina resultados já agregados (patrocinio é pequena, V4 é barata, V3 já é materializada).
-- Materializar de novo duplicaria dados e criaria mais um REFRESH para manter.
CREATE OR REPLACE VIEW vw_faturamento_canal AS
SELECT ca.id_canal,
       COALESCE(pt.total_patrocinio, 0) AS receita_patrocinio,
       COALESCE(m.total_mensal_usd, 0)  AS receita_membros,
       COALESCE(d.total_usd, 0)         AS receita_doacoes,
       COALESCE(pt.total_patrocinio, 0) + COALESCE(m.total_mensal_usd, 0) + COALESCE(d.total_usd, 0) AS receita_total
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
