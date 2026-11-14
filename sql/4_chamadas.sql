-- =====================================================================
-- 4_chamadas.sql — CHAMADAS DE TESTE DAS CONSULTAS E FUNCTIONS
-- Rodar depois de 1_ddl.sql, 2_plpgsql.sql e 3_dados.sql.
--
-- Parte 1 — As 12 consultas (2_plpgsql.sql, Seção 2), com e sem filtro, e as versões polimórficas.
-- Parte 2 — Functions de inserção (2_plpgsql.sql, Seção 1), dentro de BEGIN ... ROLLBACK:
--           mostra o efeito de cada uma e desfaz tudo no fim, então o banco não muda.
--
-- Os números usados como filtro existem na base gerada pelo 3_dados.sql (semente 2026):
--   plataforma 2 = Twitch; canal 1839 = "BearPixel ao vivo" (o canal com mais vídeos entre os que
--   receberam doação); streamer 231 = BearPixel, dono do canal 1839; usuário 811 = o membro com mais
--   inscrições; empresa 1934 = "Anderson-Riley Corp.", a que mais patrocina.
-- Nas chamadas sem filtro, o LIMIT 10 só evita encher a tela: a function devolve todas as linhas.
-- =====================================================================


-- #####################################################################
-- PARTE 1 — CONSULTAS
-- #####################################################################

-- Consulta 1: streamers com mais vídeos e o total de visualizações, por plataforma.
SELECT * FROM consulta1_streamers_mais_videos() LIMIT 10;   -- todas as plataformas
SELECT * FROM consulta1_streamers_mais_videos(2) LIMIT 10;  -- só Twitch

-- Consulta 2: vídeos com mais comentários (online, offline e total).
SELECT * FROM consulta2_videos_mais_comentados() LIMIT 10;  -- todos os canais
SELECT * FROM consulta2_videos_mais_comentados(1839);        -- só o canal 1839

-- Consulta 3: canais com mais interações por vídeo.
SELECT * FROM consulta3_canais_mais_interacoes() LIMIT 10;  -- todos os streamers
SELECT * FROM consulta3_canais_mais_interacoes(231);         -- só os canais do streamer 231

-- Consulta 4: média de doação (USD) por comentário que trouxe doação, por canal.
SELECT * FROM consulta4_canais_media_doacao() LIMIT 10;     -- todas as plataformas
SELECT * FROM consulta4_canais_media_doacao(2) LIMIT 10;    -- só Twitch

-- Consulta 5: patrocínios por empresa. Polimórfica: aceita o número (INTEGER) ou o nome (VARCHAR).
SELECT * FROM consulta5_patrocinios() LIMIT 10;                       -- todas as empresas
SELECT * FROM consulta5_patrocinios(1934) LIMIT 10;                   -- pelo número
SELECT * FROM consulta5_patrocinios('Anderson-Riley Corp.') LIMIT 10; -- pelo nome: mesmo resultado

-- Consulta 6: em quantos canais cada usuário é membro e quanto paga por mês (USD).
SELECT * FROM consulta6_membros_por_usuario() LIMIT 10;     -- todos os usuários
SELECT * FROM consulta6_membros_por_usuario(811);            -- só o usuário 811

-- Consulta 7: canais que receberam doação, com quantidade e total (USD).
SELECT * FROM consulta7_canais_com_doacoes() LIMIT 10;      -- todos os canais
SELECT * FROM consulta7_canais_com_doacoes(1839);            -- só o canal 1839

-- Consulta 8: top k canais por valor de patrocínio (USD).
SELECT * FROM consulta8_top_k_patrocinio(5);

-- Consulta 9: top k canais por valor mensal de membros (USD).
SELECT * FROM consulta9_top_k_membros(5);

-- Consulta 10: top k canais por valor de doações (USD).
SELECT * FROM consulta10_top_k_doacoes(5);

-- Consulta 11: top k canais por faturamento mensal (patrocínio + membros + doações, em USD).
SELECT * FROM consulta11_top_k_faturamento(5);

-- Consulta 12 (extra): top k plataformas por streamer, canal e streamer+canal.
-- Polimórfica no filtro opcional: número (INTEGER) ou nome (VARCHAR) da plataforma.
SELECT * FROM consulta12_top_k_plataformas(5);            -- todas as plataformas
SELECT * FROM consulta12_top_k_plataformas(5, 2);         -- só Twitch, pelo número
SELECT * FROM consulta12_top_k_plataformas(5, 'Twitch');  -- só Twitch, pelo nome: mesmo resultado

-- #####################################################################
-- PARTE 2 — FUNCTIONS DE INSERÇÃO (tudo é desfeito no ROLLBACK do fim)
-- #####################################################################

BEGIN;

-- Streamer novo: grava usuario + streamer_pais juntos (inserir_streamer chama inserir_usuario).
SELECT inserir_streamer('streamer_teste', 'streamer_teste@exemplo.com', '2000-05-10', '+55 21 99999-0000',
                        'Rua da Passagem, 10 - Niterói', 55::SMALLINT, 55::SMALLINT, 'TS0000001') AS nro_streamer;

-- Conta na Twitch: a trigger T1 soma 1 em plataforma.qtd_users.
SELECT qtd_users AS qtd_users_antes FROM plataforma WHERE nro_plataforma = 2;
SELECT inserir_conta_plataforma((SELECT nro_usuario FROM usuario WHERE nick = 'streamer_teste'), 2, 999000001);
SELECT qtd_users AS qtd_users_depois FROM plataforma WHERE nro_plataforma = 2;

-- Canal: a trigger T7 confere se o dono é streamer e tem conta na plataforma.
SELECT inserir_canal((SELECT nro_usuario FROM usuario WHERE nick = 'streamer_teste'), 2,
                     'Canal de Teste', 'publico', CURRENT_DATE, 'Canal criado pelo 4_chamadas.sql') AS id_canal;

-- Vídeo: a trigger T2 soma visu_total em canal.qtd_visualizacoes.
SELECT inserir_video((SELECT id_canal FROM canal WHERE nome_canal = 'Canal de Teste'),
                     'Primeira live', '2026-11-14 20:00', 'Teste', 3600, 150, 1200) AS id_video;
SELECT nome_canal, qtd_visualizacoes FROM canal WHERE nome_canal = 'Canal de Teste';  -- 1200

-- Dois comentários no mesmo vídeo: a trigger T3 numera seq = 1 e 2 dentro do vídeo.
SELECT inserir_comentario((SELECT id_video FROM video WHERE titulo = 'Primeira live'),
                          811, 'Primeiro!', '2026-11-14 20:05', TRUE) AS id_comentario;
SELECT inserir_comentario((SELECT id_video FROM video WHERE titulo = 'Primeira live'),
                          811, 'Mandei um Super Chat', '2026-11-14 20:10', TRUE) AS id_comentario;
SELECT seq, texto FROM comentario
 WHERE id_video = (SELECT id_video FROM video WHERE titulo = 'Primeira live') ORDER BY seq;

-- Doações: cada function grava doacao + a forma de pagamento juntas.
SELECT inserir_doacao_plataforma((SELECT id_comentario FROM comentario WHERE texto = 'Mandei um Super Chat'),
                                 25.00, 'recebido') AS id_doacao_superchat;   -- seq_plataforma pela trigger T5
SELECT inserir_doacao_paypal((SELECT id_comentario FROM comentario WHERE texto = 'Primeiro!'),
                             10.00, 'lido', 'PAYPAL-TESTE-0001') AS id_doacao_paypal;

-- As visões materializadas só veem os dados novos depois do REFRESH.
SELECT atualizar_visoes_materializadas();
SELECT * FROM consulta7_canais_com_doacoes((SELECT id_canal FROM canal WHERE nome_canal = 'Canal de Teste'));

ROLLBACK;  -- desfaz a Parte 2 inteira, inclusive o REFRESH (no PostgreSQL ele também é transacional)
