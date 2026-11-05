-- =====================================================================
-- 01_ddl.sql — DESIGN FÍSICO (DDL)
-- Projeto de Banco de Dados 2026/2 — Prof. Marcos Bedo — UFF
--
-- Cria os tipos ENUM e as 20 tabelas do modelo relacional do enunciado,
-- já adaptadas para o PostgreSQL (projeto físico).
--
-- Decisões gerais (valem para todo o arquivo):
-- GENERATED ALWAYS AS IDENTITY: o banco gera o valor sozinho e rejeita inserção manual, evitando conflito de ids.
-- Chaves primárias numéricas: a PK vira um índice B+-tree; comparar inteiros é mais barato que comparar strings,
--   e a chave fica menor (mais entradas por nó, árvore mais baixa). A antiga chave natural vira UNIQUE + NOT NULL,
--   para não perder a unicidade do modelo relacional.
-- Chaves compostas: colapsadas em chaves artificiais sempre que passavam de 2 atributos (ex.: video, comentario, doacao).
-- NOT NULL: para atributos que são obrigatórios, o banco rejeita inserção de NULL.
-- ON UPDATE RESTRICT em todas as FKs: as PKs referenciadas são identity (ou DDI) e não mudam; bloquear é coerente.
-- Validação de formato (data, e-mail, telefone) fica no front-end, como orientado na consultoria;
--   no banco ficam só as regras de negócio estáveis (CHECK, ENUM, UNIQUE, FK).
-- =====================================================================


-- ---------------------------------------------------------------------
-- TIPOS ENUM
-- ENUM em vez de VARCHAR + CHECK: o domínio é fechado e quase nunca muda; o ENUM ocupa 4 bytes,
--   rejeita valores fora da lista e deixa o domínio documentado no próprio tipo.
-- ---------------------------------------------------------------------

-- Tipo do canal: o enunciado define exatamente {privado, público, misto}.
CREATE TYPE tipo_canal_enum AS ENUM ('privado', 'publico', 'misto');

-- Status da doação: o enunciado define exatamente {recusado, recebido, lido}.
CREATE TYPE status_doacao_enum AS ENUM ('recusado', 'recebido', 'lido');

-- Bandeira do cartão: conjunto pequeno e estável. Se surgir uma bandeira nova, basta
--   ALTER TYPE bandeira_cartao_enum ADD VALUE 'nova' (não exige reescrever a tabela).
CREATE TYPE bandeira_cartao_enum AS ENUM ('visa', 'mastercard', 'amex', 'elo', 'hipercard', 'diners');


-- ---------------------------------------------------------------------
-- EMPRESA
-- ---------------------------------------------------------------------
CREATE TABLE empresa(
    -- INTEGER: empresas são poucas perto de usuários e comentários; 4 bytes bastam (até ~2 bilhões).
    nro_empresa INTEGER GENERATED ALWAYS AS IDENTITY,
    -- NOT NULL: toda empresa precisa de nome.
    nome VARCHAR(255) NOT NULL,
    -- NOT NULL: o modelo exige que toda empresa tenha um.
    -- Sem UNIQUE: empresas diferentes podem usar o mesmo nome fantasia, então a unicidade aqui seria uma regra de negócio indevida.
    nome_fantasia VARCHAR(255) NOT NULL,

    CONSTRAINT pk_empresa PRIMARY KEY (nro_empresa),
    -- Garante que não existam duas empresas com o mesmo nome.
    CONSTRAINT uq_empresa_nome UNIQUE (nome)
);


-- ---------------------------------------------------------------------
-- PLATAFORMA
-- ---------------------------------------------------------------------
CREATE TABLE plataforma(
    nro_plataforma INTEGER GENERATED ALWAYS AS IDENTITY,

    -- Nome da plataforma. NOT NULL + UNIQUE (abaixo): não deve haver duas plataformas com o mesmo nome.
    nome VARCHAR(100) NOT NULL,

    -- Quantidade de usuários: ATRIBUTO DERIVADO (= número de linhas em plataforma_usuario da plataforma).
    -- Mantido armazenado porque o enunciado o lista e porque evita um COUNT(*) a cada leitura.
    -- Quem mantém o valor correto é a trigger trg_plataforma_usuario_qtd (02_ddl_estendida.sql);
    --   a trigger trg_plataforma_protege_qtd impede que alguém altere o valor "na mão".
    -- BIGINT: uma plataforma real tem bilhões de contas (o YouTube passa de 2 bilhões).
    qtd_users BIGINT NOT NULL DEFAULT 0,

    -- NOT NULL: toda plataforma tem uma empresa fundadora.
    empresa_fund INTEGER NOT NULL,
    -- Pode ser a mesma da fundadora ou outra, por isso são duas colunas independentes para a mesma tabela.
    empresa_respo INTEGER NOT NULL,
    -- Data de fundação. NOT NULL: o modelo exige.
    data_fund DATE NOT NULL,

    CONSTRAINT pk_plataforma PRIMARY KEY (nro_plataforma),
    CONSTRAINT uq_plataforma_nome UNIQUE (nome),
    -- Rede de segurança: contagem negativa não existe.
    CONSTRAINT ck_plataforma_qtd_users CHECK (qtd_users >= 0),

    -- ON DELETE RESTRICT: não deixa apagar uma empresa que ainda é fundadora de alguma plataforma. É a escolha segura aqui, porque
    --   CASCADE apagaria plataformas inteiras e SET NULL é impossível (a coluna é NOT NULL).
    CONSTRAINT fk_plataforma_empresa_fund FOREIGN KEY (empresa_fund)
        REFERENCES empresa (nro_empresa) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_plataforma_empresa_respo FOREIGN KEY (empresa_respo)
        REFERENCES empresa (nro_empresa) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- CONVERSAO (moeda)
-- ---------------------------------------------------------------------
CREATE TABLE conversao(
    -- Chave artificial que substitui "moeda" (CHAR(3)) como PK, pois a PK não deve ser string.
    -- SMALLINT (2 bytes, até 32.767): existem menos de 200 moedas no mundo; sobra espaço.
    id SMALLINT GENERATED ALWAYS AS IDENTITY,

    -- Código da moeda (ex.: BRL). CHAR(3): sempre 3 letras (padrão ISO 4217), então não precisa de VARCHAR.
    -- UNIQUE: preserva a unicidade da chave original. Sem isso, a troca de PK permitiria dois "BRL", o que quebraria o modelo.
    moeda CHAR(3) NOT NULL,

    -- UNIQUE: duas moedas não devem ter o mesmo nome.
    nome VARCHAR(63) NOT NULL,

    -- Fator de conversão para dólar (USD = 1): valor_em_usd = valor_na_moeda * fator_conver.
    -- NUMERIC(18, 6) e não FLOAT: dinheiro exige precisão exata; 6 casas bastam para taxas como 0,182345.
    -- CHECK (> 0): fator zero ou negativo não faz sentido e zeraria ou inverteria todo valor convertido.
    fator_conver NUMERIC(18, 6) NOT NULL,

    CONSTRAINT pk_conversao PRIMARY KEY (id),
    CONSTRAINT uq_conversao_moeda UNIQUE (moeda),
    CONSTRAINT uq_conversao_nome UNIQUE (nome),
    CONSTRAINT ck_conversao_fator CHECK (fator_conver > 0)
);


-- ---------------------------------------------------------------------
-- PAIS
-- ---------------------------------------------------------------------
CREATE TABLE pais(
    -- O DDI já é uma chave natural NUMÉRICA e estável, por isso não precisou de chave artificial.
    -- SMALLINT: DDIs têm no máximo 4 dígitos.
    ddi SMALLINT,
    nome VARCHAR(127) NOT NULL,
    -- FK para a moeda do país.
    moeda_id SMALLINT NOT NULL,

    CONSTRAINT pk_pais PRIMARY KEY (ddi),
    -- UNIQUE: dois países não devem ter o mesmo nome.
    CONSTRAINT uq_pais_nome UNIQUE (nome),
    CONSTRAINT ck_pais_ddi CHECK (ddi > 0),

    -- ON DELETE RESTRICT: não deixa apagar uma moeda que ainda é usada por algum país.
    CONSTRAINT fk_pais_conversao FOREIGN KEY (moeda_id)
        REFERENCES conversao (id) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- USUARIO
-- Streamers e membros são usuários (especialização com sobreposição no modelo ER).
-- O streamer é o usuário que tem passaporte em streamer_pais.
-- ---------------------------------------------------------------------
CREATE TABLE usuario (
    -- Chave artificial que substitui "nick" (VARCHAR) como PK.
    -- BIGINT: é a tabela de pessoas, a de maior cardinalidade entre os cadastros (plataformas reais têm bilhões de contas).
    nro_usuario BIGINT GENERATED ALWAYS AS IDENTITY,

    -- Antiga PK natural, agora chave candidata.
    -- NOT NULL + UNIQUE: preserva a unicidade da chave original.
    nick VARCHAR(63) NOT NULL,

    -- NOT NULL + UNIQUE: uma conta por e-mail. 254 é o tamanho máximo de um e-mail válido.
    email VARCHAR(254) NOT NULL,

    -- DATE e não TIMESTAMP: a hora do nascimento não importa.
    data_nasc DATE NOT NULL,

    -- Telefone para validação em duas vias. VARCHAR e não numérico: tem "+", parênteses e zeros à esquerda,
    --   e ninguém faz conta com ele.
    -- Nulável: assumimos que é opcional.
    -- Sem UNIQUE: é comum compartilhar telefone.
    telefone VARCHAR(20),

    -- Endereço postal. Nulável: assumimos que é opcional.
    end_postal VARCHAR(255),

    -- SMALLINT: o mesmo tipo de pais.ddi.
    pais_residencia SMALLINT NOT NULL,

    CONSTRAINT pk_usuario PRIMARY KEY (nro_usuario),
    CONSTRAINT uq_usuario_nick UNIQUE (nick),
    CONSTRAINT uq_usuario_email UNIQUE (email),

    -- RESTRICT: não permite apagar um país que ainda tem usuários.
    -- CASCADE seria perigoso aqui, pois apagaria todos os usuários do país.
    CONSTRAINT fk_usuario_pais FOREIGN KEY (pais_residencia)
        REFERENCES pais (ddi) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- PLATAFORMA_USUARIO (conta do usuário em cada plataforma)
-- ---------------------------------------------------------------------
CREATE TABLE plataforma_usuario (
    nro_plataforma INTEGER NOT NULL,

    -- É o BIGINT nro_usuario: a FK guarda um inteiro de 8 bytes em vez do nick.
    nro_usuario BIGINT NOT NULL,

    -- Número da conta do usuário dentro da plataforma ("número de usuário que pode ser diferente em cada plataforma").
    -- Renomeado para não confundir com nro_usuario.
    nro_conta BIGINT NOT NULL,

    -- PK composta com 2 atributos: garante que um usuário não se vincule duas vezes à mesma plataforma.
    CONSTRAINT pk_plataforma_usuario PRIMARY KEY (nro_plataforma, nro_usuario),

    -- Dentro de uma plataforma, cada número de conta é de um só usuário.
    CONSTRAINT uq_plataforma_usuario_conta UNIQUE (nro_plataforma, nro_conta),

    -- CASCADE: o vínculo não tem sentido sem a plataforma. Se a plataforma for removida, os vínculos vão junto.
    CONSTRAINT fk_pu_plataforma FOREIGN KEY (nro_plataforma)
        REFERENCES plataforma (nro_plataforma) ON DELETE CASCADE ON UPDATE RESTRICT,

    -- CASCADE: se a conta do usuário for removida, seus vínculos também.
    CONSTRAINT fk_pu_usuario FOREIGN KEY (nro_usuario)
        REFERENCES usuario (nro_usuario) ON DELETE CASCADE ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- STREAMER_PAIS (passaporte do streamer)
-- ---------------------------------------------------------------------
CREATE TABLE streamer_pais (
    -- Substitui nick_streamer. Aponta para a PK artificial de usuario.
    nro_streamer BIGINT NOT NULL,

    -- País emissor do passaporte. SMALLINT, o mesmo tipo de pais.ddi.
    ddi_pais SMALLINT NOT NULL,

    -- VARCHAR e não numérico, pois passaportes têm letras.
    nro_passaporte VARCHAR(20) NOT NULL,

    -- PK composta com 2 atributos: um único passaporte por streamer em cada país.
    CONSTRAINT pk_streamer_pais PRIMARY KEY (nro_streamer, ddi_pais),

    -- Um número de passaporte é único dentro do país que o emitiu.
    -- O mesmo número pode existir em países diferentes, então a unicidade é do par, e não do número isolado.
    CONSTRAINT uq_streamer_pais_passaporte UNIQUE (ddi_pais, nro_passaporte),

    -- CASCADE: se o usuário for removido, seus dados de passaporte não devem permanecer no banco.
    CONSTRAINT fk_sp_usuario FOREIGN KEY (nro_streamer)
        REFERENCES usuario (nro_usuario) ON DELETE CASCADE ON UPDATE RESTRICT,

    -- RESTRICT: país é dado de domínio. Não pode ser apagado enquanto houver passaporte emitido por ele.
    CONSTRAINT fk_sp_pais FOREIGN KEY (ddi_pais)
        REFERENCES pais (ddi) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- EMPRESA_PAIS (sede da empresa e seu identificador nacional, ex.: CNPJ)
-- ---------------------------------------------------------------------
CREATE TABLE empresa_pais (
    nro_empresa INTEGER NOT NULL,
    ddi_pais SMALLINT NOT NULL,

    -- Identificador nacional da empresa (CNPJ, EIN...). VARCHAR: cada país usa um formato, com letras e pontuação.
    id_nacional VARCHAR(50) NOT NULL,

    -- PK composta com 2 atributos: uma empresa tem um só identificador nacional por país.
    CONSTRAINT pk_empresa_pais PRIMARY KEY (nro_empresa, ddi_pais),

    -- O mesmo identificador nacional não pode ser de duas empresas no mesmo país.
    -- O mesmo identificador pode existir em países diferentes.
    CONSTRAINT uq_empresa_pais_id_nacional UNIQUE (ddi_pais, id_nacional),

    -- CASCADE: se uma empresa for removida, seus identificadores nacionais também devem ser removidos.
    CONSTRAINT fk_ep_empresa FOREIGN KEY (nro_empresa)
        REFERENCES empresa (nro_empresa) ON DELETE CASCADE ON UPDATE RESTRICT,

    -- RESTRICT: não permite apagar um país que ainda possui identificadores nacionais de empresas associados.
    CONSTRAINT fk_ep_pais FOREIGN KEY (ddi_pais)
        REFERENCES pais (ddi) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- CANAL
-- ---------------------------------------------------------------------
CREATE TABLE canal (
    -- Chave artificial numérica que substitui o par (nome, nro_plataforma) como PK.
    -- INTEGER e não BIGINT: canais são ordens de grandeza menos numerosos que vídeos e comentários;
    --   4 bytes a menos em cada FK que aponta para canal (video, patrocinio, nivel_canal, inscricao).
    id_canal INTEGER GENERATED ALWAYS AS IDENTITY,

    -- NOT NULL + UNIQUE (com a plataforma) para preservar a unicidade da chave original.
    nome_canal VARCHAR(255) NOT NULL,

    -- ENUM permite apenas privado, publico ou misto.
    tipo tipo_canal_enum NOT NULL,

    data_inicio DATE NOT NULL,

    -- TEXT: descrição livre, sem tamanho máximo conhecido.
    descricao TEXT NOT NULL,

    -- Quantidade de visualizações: ATRIBUTO DERIVADO (= soma de video.visu_total dos vídeos do canal).
    -- Mantido armazenado e atualizado pela trigger trg_video_qtd_visualizacoes (02_ddl_estendida.sql);
    --   a trigger trg_canal_protege_qtd impede alteração manual.
    qtd_visualizacoes BIGINT NOT NULL DEFAULT 0,

    -- Dono do canal (um streamer).
    nro_streamer BIGINT NOT NULL,

    nro_plataforma INTEGER NOT NULL,

    CONSTRAINT pk_canal PRIMARY KEY (id_canal),

    -- Chave natural do modelo relacional: o nome é único dentro da plataforma.
    CONSTRAINT uq_canal_plataforma_nome UNIQUE (nro_plataforma, nome_canal),

    -- Impede quantidade negativa de visualizações.
    CONSTRAINT ck_canal_qtd_visualizacoes CHECK (qtd_visualizacoes >= 0),

    -- RESTRICT: impede excluir um usuário que seja dono de um canal.
    CONSTRAINT fk_canal_usuario FOREIGN KEY (nro_streamer)
        REFERENCES usuario (nro_usuario) ON DELETE RESTRICT ON UPDATE RESTRICT,

    -- RESTRICT: impede excluir uma plataforma que tenha canais.
    CONSTRAINT fk_canal_plataforma FOREIGN KEY (nro_plataforma)
        REFERENCES plataforma (nro_plataforma) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- PATROCINIO
-- ---------------------------------------------------------------------
CREATE TABLE patrocinio (
    nro_empresa INTEGER NOT NULL,
    id_canal INTEGER NOT NULL,

    -- Valor em dólares americanos (o enunciado define assim).
    -- NUMERIC(14, 2): precisão exata para dinheiro, com 2 casas decimais; nunca FLOAT/REAL.
    valor NUMERIC(14, 2) NOT NULL,

    -- PK composta com 2 atributos: cada empresa patrocina um canal no máximo uma vez
    --   (o sistema guarda só o patrocínio vigente, sem histórico).
    CONSTRAINT pk_patrocinio PRIMARY KEY (nro_empresa, id_canal),

    -- Regra de domínio: o valor é positivo.
    CONSTRAINT ck_patrocinio_valor CHECK (valor > 0),

    -- RESTRICT: o sistema não guarda histórico, só patrocínios vigentes. Mesmo assim, uma empresa não pode
    --   sumir enquanto tiver um patrocínio vigente; para encerrar o patrocínio, apaga-se a linha daqui antes.
    CONSTRAINT fk_patrocinio_empresa FOREIGN KEY (nro_empresa)
        REFERENCES empresa (nro_empresa) ON DELETE RESTRICT ON UPDATE RESTRICT,

    -- RESTRICT também: apagar um canal não deve apagar patrocínios vigentes silenciosamente.
    CONSTRAINT fk_patrocinio_canal FOREIGN KEY (id_canal)
        REFERENCES canal (id_canal) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- NIVEL_CANAL (os 5 níveis de membro de cada canal)
-- ---------------------------------------------------------------------
CREATE TABLE nivel_canal (
    -- Substitui o par (nome_canal, nro_plataforma).
    id_canal INTEGER NOT NULL,

    -- SMALLINT: só vai de 1 a 5.
    nivel SMALLINT NOT NULL,

    -- Nome do nível, definido por canal.
    nome VARCHAR(50) NOT NULL,

    -- Valor mensal do nível, em dólares americanos (assumido: o enunciado não cita moeda e os relatórios são em USD).
    valor NUMERIC(10, 2) NOT NULL,

    -- VARCHAR e não BYTEA: guardar o arquivo dentro do banco incha a tabela e os backups.
    --   O arquivo fica em um storage e o banco guarda só a referência (caminho ou URL).
    gif VARCHAR(500) NOT NULL,

    -- PK composta com 2 atributos: um canal não tem dois níveis com o mesmo número.
    CONSTRAINT pk_nivel_canal PRIMARY KEY (id_canal, nivel),

    -- Dentro de um canal, cada nível tem um nome diferente.
    CONSTRAINT uq_nivel_canal_nome UNIQUE (id_canal, nome),

    -- Regra de negócio estável (exemplo citado pelo professor): existem exatamente cinco níveis, de 1 a 5.
    CONSTRAINT ck_nivel_canal_nivel CHECK (nivel BETWEEN 1 AND 5),

    -- Regra de domínio: o valor é positivo.
    CONSTRAINT ck_nivel_canal_valor CHECK (valor > 0),

    -- CASCADE: o nível não existe sem o canal. Se o canal for removido, seus níveis vão junto.
    CONSTRAINT fk_nivel_canal_canal FOREIGN KEY (id_canal)
        REFERENCES canal (id_canal) ON DELETE CASCADE ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- INSCRICAO (membro vigente de um canal; sem histórico)
-- ---------------------------------------------------------------------
CREATE TABLE inscricao (
    id_canal INTEGER NOT NULL,
    nro_usuario BIGINT NOT NULL,
    nivel SMALLINT NOT NULL,

    -- PK composta com 2 atributos: um usuário tem só uma inscrição vigente em cada canal.
    CONSTRAINT pk_inscricao PRIMARY KEY (id_canal, nro_usuario),

    -- CASCADE: se o usuário for removido, suas inscrições também devem ser removidas.
    CONSTRAINT fk_inscricao_usuario FOREIGN KEY (nro_usuario)
        REFERENCES usuario (nro_usuario) ON DELETE CASCADE ON UPDATE RESTRICT,

    -- RESTRICT: impede excluir um nível de canal enquanto existirem inscrições nele.
    -- Esta FK também garante que o canal existe (o nível pertence ao canal).
    CONSTRAINT fk_inscricao_nivel_canal FOREIGN KEY (id_canal, nivel)
        REFERENCES nivel_canal (id_canal, nivel) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- VIDEO
-- ---------------------------------------------------------------------
CREATE TABLE video (
    -- Chave artificial numérica que substitui (nome_canal, nro_plataforma, titulo, dataH): 4 atributos viram 1.
    -- BIGINT: vídeos crescem sem parar (centenas de milhões numa plataforma real).
    id_video BIGINT GENERATED ALWAYS AS IDENTITY,

    titulo VARCHAR(255) NOT NULL,

    -- TIMESTAMP: data e hora de postagem. Faz parte do identificador natural (UNIQUE abaixo).
    dataH TIMESTAMP NOT NULL,

    tema VARCHAR(127) NOT NULL,

    -- Duração em segundos.
    duracao INTEGER NOT NULL,

    -- Pico de visualizações simultâneas. Dado medido pela plataforma, não derivado de outra tabela
    --   (não existe tabela de sessões de visualização), por isso não precisa de trigger.
    -- DEFAULT 0: o vídeo começa sem nenhuma visualização.
    visu_simul INTEGER NOT NULL DEFAULT 0,

    -- Total de visualizações. Também é dado medido. BIGINT: mesmo tipo de canal.qtd_visualizacoes.
    visu_total BIGINT NOT NULL DEFAULT 0,

    id_canal INTEGER NOT NULL,

    CONSTRAINT pk_video PRIMARY KEY (id_video),

    -- Preserva o identificador natural. Sem id_canal na chave, só poderia existir um vídeo com aquele
    --   título e horário em todo o banco.
    CONSTRAINT uq_video_canal_titulo_data UNIQUE (id_canal, titulo, dataH),

    -- Duração zero ou negativa não faz sentido.
    CONSTRAINT ck_video_duracao CHECK (duracao > 0),

    -- O pico simultâneo nunca é negativo nem maior que o total de visualizações.
    CONSTRAINT ck_video_visu CHECK (visu_simul >= 0 AND visu_total >= visu_simul),

    -- RESTRICT: não deixa apagar um canal que ainda tem vídeos, pois os vídeos têm comentários e doações
    --   associados. CASCADE apagaria esse histórico.
    CONSTRAINT fk_video_canal FOREIGN KEY (id_canal)
        REFERENCES canal (id_canal) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- PARTICIPA (streamers convidados de um vídeo)
-- ---------------------------------------------------------------------
CREATE TABLE participa (
    -- Substitui (nome_canal, nro_plataforma, titulo_video, dataH_video).
    id_video BIGINT NOT NULL,
    nro_streamer BIGINT NOT NULL,

    -- PK composta com 2 atributos numéricos: um streamer aparece uma única vez em cada vídeo.
    CONSTRAINT pk_participa PRIMARY KEY (id_video, nro_streamer),

    -- CASCADE: a participação não existe sem o vídeo.
    CONSTRAINT fk_participa_video FOREIGN KEY (id_video)
        REFERENCES video (id_video) ON DELETE CASCADE ON UPDATE RESTRICT,

    -- CASCADE: se o usuário for removido, suas participações também.
    CONSTRAINT fk_participa_usuario FOREIGN KEY (nro_streamer)
        REFERENCES usuario (nro_usuario) ON DELETE CASCADE ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- COMENTARIO
-- ---------------------------------------------------------------------
CREATE TABLE comentario (
    -- Chave artificial numérica: a chave do modelo relacional tinha 6 atributos
    --   (nome_canal, nro_plataforma, titulo_video, dataH_video, nick_usuario, seq).
    -- BIGINT: é a tabela de maior volume do modelo (vários comentários por vídeo).
    id_comentario BIGINT GENERATED ALWAYS AS IDENTITY,

    -- FK para o vídeo pela chave artificial (1 atributo em vez de 4).
    id_video BIGINT NOT NULL,

    -- Número sequencial do comentário dentro do vídeo (1, 2, 3...).
    -- Gerado pela trigger trg_comentario_seq: quem insere não informa.
    seq INTEGER NOT NULL,

    -- Usuário que fez o comentário.
    nro_usuario BIGINT NOT NULL,

    texto TEXT NOT NULL,

    dataH TIMESTAMP NOT NULL,

    -- TRUE = comentário online (durante a transmissão); FALSE = offline.
    -- BOOLEAN e não ENUM: só existem dois estados.
    coment_on BOOLEAN NOT NULL,

    CONSTRAINT pk_comentario PRIMARY KEY (id_comentario),

    -- Preserva o identificador natural: o sequencial é único dentro do vídeo.
    CONSTRAINT uq_comentario_video_seq UNIQUE (id_video, seq),

    -- O sequencial começa em 1.
    CONSTRAINT ck_comentario_seq CHECK (seq > 0),

    -- CASCADE: o comentário não existe sem o vídeo.
    -- (Na prática a FK de doacao, que é RESTRICT, impede apagar vídeo que tenha comentário com doação.)
    CONSTRAINT fk_comentario_video FOREIGN KEY (id_video)
        REFERENCES video (id_video) ON DELETE CASCADE ON UPDATE RESTRICT,

    -- RESTRICT: não apaga um usuário que tem comentários (eles alimentam as métricas de interação).
    CONSTRAINT fk_comentario_usuario FOREIGN KEY (nro_usuario)
        REFERENCES usuario (nro_usuario) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- DOACAO (superclasse da especialização disjunta: bitcoin, paypal, cartão, mecanismo da plataforma)
-- ---------------------------------------------------------------------
CREATE TABLE doacao (
    -- Chave artificial: a chave do modelo relacional tinha 7 atributos
    --   (nome_canal, nro_plataforma, titulo_video, dataH_video, nick_usuario, seq_comentario, seq_pg).
    -- Com ela, as 4 subclasses passam a ter PK de 1 atributo.
    id_doacao BIGINT GENERATED ALWAYS AS IDENTITY,

    -- Comentário que trouxe a doação. O comentário já identifica o vídeo e o usuário, por isso eles não se repetem aqui.
    id_comentario BIGINT NOT NULL,

    -- Número sequencial da doação dentro do comentário (o modelo relacional chama de seq_pg).
    -- Gerado pela trigger trg_doacao_seq.
    seq_doacao INTEGER NOT NULL,

    -- Valor na MOEDA DO PAÍS DE RESIDÊNCIA de quem doou (usuario -> pais -> conversao).
    -- As consultas convertem para dólar com conversao.fator_conver. Assim a tabela conversao tem uso real.
    -- NUMERIC(14, 2): dinheiro, precisão exata.
    valor NUMERIC(14, 2) NOT NULL,

    -- ENUM: só recusado, recebido ou lido.
    status status_doacao_enum NOT NULL,

    CONSTRAINT pk_doacao PRIMARY KEY (id_doacao),

    -- Preserva o identificador natural do modelo relacional: o sequencial é único dentro do comentário.
    CONSTRAINT uq_doacao_comentario_seq UNIQUE (id_comentario, seq_doacao),

    CONSTRAINT ck_doacao_valor CHECK (valor > 0),
    CONSTRAINT ck_doacao_seq CHECK (seq_doacao > 0),

    -- RESTRICT: doação é registro financeiro; apagar o comentário não pode apagar dinheiro recebido em silêncio.
    CONSTRAINT fk_doacao_comentario FOREIGN KEY (id_comentario)
        REFERENCES comentario (id_comentario) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- Subclasses de DOACAO
-- Mapeamento "uma tabela por subclasse": cada uma guarda só os atributos próprios e usa a PK da superclasse
--   como PK e FK. CASCADE: os dados específicos não existem sem a doação.
-- A disjunção (uma doação é de UM só tipo) é garantida pela trigger trg_*_forma_unica (02_ddl_estendida.sql).
-- ---------------------------------------------------------------------

CREATE TABLE bitcoin (
    id_doacao BIGINT NOT NULL,

    -- TxID: hash SHA-256 em hexadecimal, sempre 64 caracteres, por isso CHAR(64).
    -- UNIQUE: uma transação da blockchain não pode ser registrada como duas doações.
    txid CHAR(64) NOT NULL,

    CONSTRAINT pk_bitcoin PRIMARY KEY (id_doacao),
    CONSTRAINT uq_bitcoin_txid UNIQUE (txid),
    CONSTRAINT fk_bitcoin_doacao FOREIGN KEY (id_doacao)
        REFERENCES doacao (id_doacao) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE paypal (
    id_doacao BIGINT NOT NULL,

    -- Id do pagamento no PayPal (alfanumérico). UNIQUE: um pagamento não vira duas doações.
    id_paypal VARCHAR(30) NOT NULL,

    CONSTRAINT pk_paypal PRIMARY KEY (id_doacao),
    CONSTRAINT uq_paypal_id UNIQUE (id_paypal),
    CONSTRAINT fk_paypal_doacao FOREIGN KEY (id_doacao)
        REFERENCES doacao (id_doacao) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE cartao_credito (
    id_doacao BIGINT NOT NULL,

    -- Número do cartão. VARCHAR e não numérico: até 19 dígitos e zeros à esquerda.
    -- Sem UNIQUE: o mesmo cartão pode fazer várias doações.
    -- Observação: num sistema real se guardaria só um token ou os 4 últimos dígitos (norma PCI-DSS);
    --   aqui seguimos o enunciado, que pede o número.
    nro_cartao VARCHAR(19) NOT NULL,

    bandeira bandeira_cartao_enum NOT NULL,

    -- Data e hora da transação no cartão (o enunciado pede).
    dataH TIMESTAMP NOT NULL,

    CONSTRAINT pk_cartao_credito PRIMARY KEY (id_doacao),
    CONSTRAINT fk_cartao_doacao FOREIGN KEY (id_doacao)
        REFERENCES doacao (id_doacao) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE mecanismo_plat (
    id_doacao BIGINT NOT NULL,

    -- Número sequencial que depende do usuário e da plataforma (ex.: 5º Super Chat do usuário no YouTube).
    -- Gerado pela trigger trg_mecanismo_plat_seq. Usuário e plataforma não ficam guardados aqui porque
    --   já são alcançados pelo comentário (doacao -> comentario -> video -> canal -> plataforma); guardá-los seria redundância.
    seq_plataforma INTEGER NOT NULL,

    CONSTRAINT pk_mecanismo_plat PRIMARY KEY (id_doacao),
    CONSTRAINT ck_mecanismo_plat_seq CHECK (seq_plataforma > 0),
    CONSTRAINT fk_mecanismo_doacao FOREIGN KEY (id_doacao)
        REFERENCES doacao (id_doacao) ON DELETE CASCADE ON UPDATE RESTRICT
);
