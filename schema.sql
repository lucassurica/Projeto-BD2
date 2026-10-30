CREATE TABLE empresa(
    -- GENERATED ALWAYS AS IDENTITY: o banco gera o valor sozinho e rejeita inserção manual, evitando conflito de ids
    nro_empresa INTEGER GENERATED ALWAYS AS IDENTITY, 
    -- NOT NULL: toda empresa precisa de nome.
    nome VARCHAR(255) NOT NULL,
    -- NOT NULL: o modelo exige que toda empresa tenha um.
    -- Sem UNIQUE: empresas diferentes podem usar o mesmo nome fantasia, então a unicidade aqui seria uma regra de negócio indevida.
    nome_fantasia VARCHAR(255) NOT NULL,

    CONSTRAINT pk_empresa PRIMARY KEY(nro_empresa),
    -- Garante que não existam duas empresas com o mesmo nome.
    CONSTRAINT uq_empresa_nome UNIQUE (nome)

);

CREATE TABLE plataforma(
    -- GENERATED ALWAYS AS IDENTITY: o banco gera o valor sozinho e rejeita inserção manual, evitando conflito de ids
    nro_plataforma INTEGER GENERATED ALWAYS AS IDENTITY, 
    -- Nome da plataforma. NOT NULL + UNIQUE (abaixo): não deve haver duas plataformas com o mesmo nome.
    nome VARCHAR(100) NOT NULL,
    qtd_users BIGINT NOT NULL DEFAULT 0, --! esse atributo não deve permanecer na tabela, deve ser removido e escolher uma politica de trigger para atualizar esse atributo
    -- NOT NULL: toda plataforma tem uma empresa fundadora.
    empresa_fund INTEGER NOT NULL,
    -- Pode ser a mesma da fundadora ou outra, por isso são duas colunas independentes para a mesma tabela.
    empresa_respo INTEGER NOT NULL,
    -- Data de fundação. NOT NULL: o modelo exige.
    data_fund DATE NOT NULL,

    CONSTRAINT pk_plataforma PRIMARY KEY(nro_plataforma),
    CONSTRAINT uq_plataforma_nome UNIQUE (nome),
    CONSTRAINT ck_plataforma_qtd_users CHECK (qtd_users>=0),--! esse atributo não deve permanecer na tabela, deve ser removido e escolher uma politica de trigger para atualizar esse atributo

    -- ON DELETE RESTRICT: não deixa apagar uma empresa que ainda é fundadora de alguma plataforma. É a escolha segura aqui, porque
    --   CASCADE apagaria plataformas inteiras e SET NULL é impossível (a coluna é NOT NULL).
    -- ON UPDATE RESTRICT: como a PK é identity e nunca muda, quase não é acionado. Bloquear alterações é coerente com a PK imutável.
    CONSTRAINT fk_plataforma_empresa_fund FOREIGN KEY(empresa_fund)
        REFERENCES empresa(nro_empresa) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_plataforma_empresa_respo FOREIGN KEY(empresa_respo)
        REFERENCES empresa(nro_empresa) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE conversao(
    -- chave artificial que substitui moeda pois moeda é string
    -- usamos SMALLINT pois é suficiente para moedas
    -- GENERATED ALWAYS AS IDENTITY: o banco gera o valor sozinho e rejeita inserção manual, evitando conflito de ids
    id SMALLINT GENERATED ALWAYS AS IDENTITY, 
    -- CHAR(3): tamanho fixo e sempre 3 letras, então não precisa de VARCHAR.
    -- NOT NULL: toda moeda precisa de código.
    -- UNIQUE: preserva a unicidade da chave original. Sem isso, a troca de PK permitiria dois "BRL", o que quebraria o modelo.
    moeda CHAR(3) NOT NULL UNIQUE,
    -- NOT NULL: obrigatório.
    -- UNIQUE: duas moedas não devem ter o mesmo nome
    -- VARCHAR(50): nomes de moeda são curtos, e o limite evita lixo
    nome VARCHAR(50) NOT NULL UNIQUE,
    -- Fator de conversão para dólar (USD = 1).
    -- NUMERIC(18, 6): 18 dígitos no total, 6 casas decimais suficiente para taxas como 0,182345
    -- NOT NULL: uma moeda sem fator não serve para conversão
    -- CHECK (> 0): fator zero ou negativo não faz sentido e zeraria ou inverteria todo valor convertido
    fator_conver NUMERIC(18, 6) NOT NULL CHECK (fator_conver > 0),

    PRIMARY KEY (id)
);

CREATE TABLE pais(
     -- SMALLINT: DDIs têm no máximo 3 dígitos
    ddi SMALLINT,
    -- NOT NULL: obrigatório
    -- UNIQUE: dois países não devem ter o mesmo nome
    nome VARCHAR(100) NOT NULL,
    -- NOT NULL: assume que todo país tem uma moeda no modelo
    moeda_id SMALLINT NOT NULL,

    CONSTRAINT pk_pais PRIMARY KEY (ddi),

    CONSTRAINT uq_pais_nome UNIQUE (nome),

    -- ON DELETE RESTRICT: não deixa apagar uma moeda que ainda é usada por algum país
    -- ON UPDATE RESTRICT: a PK de conversao é identity e não muda
    CONSTRAINT fk_pais_conversao FOREIGN KEY (moeda_id)
        REFERENCES conversao (id) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE usuario (

    -- Chave artificial que substitui "nick" como PK
    -- BIGINT: é a tabela com maior cardinalidade do modelo.
    nro_usuario BIGINT GENERATED ALWAYS AS IDENTITY,

    -- Antiga PK natural, agora chave candidata
    -- NOT NULL + UNIQUE: preserva a unicidade da chave original
    nick VARCHAR(50) NOT NULL,

    -- E-mail. NOT NULL + UNIQUE: uma conta por e-mail. 254 é o tamanho máximo de um e-mail válido (RFC)
    email VARCHAR(254) NOT NULL,

    -- Data de nascimento. DATE, não TIMESTAMP: a hora não importa
    -- NOT NULL: assumi que é obrigatória no cadastro
    data_nasc DATE NOT NULL,

    -- Telefone. VARCHAR e não numérico: tem "+", parênteses, zeros à
    --   esquerda, e ninguém faz conta com ele
    -- Nulável: assumimos que é opcional
    -- Sem UNIQUE: é comum compartilhar telefone 
    telefone VARCHAR(20),

    -- Endereço postal. Nulável: assumimos que é opcional
    end_postal VARCHAR(255),

    -- FK para o país de residência. SMALLINT, o mesmo tipo de pais.ddi
    -- NOT NULL: assumimos que todo usuário informa o país
    pais_residencia SMALLINT NOT NULL,

    CONSTRAINT pk_usuario PRIMARY KEY (nro_usuario),
    CONSTRAINT uq_usuario_nick UNIQUE (nick),
    CONSTRAINT uq_usuario_email UNIQUE (email),

    -- RESTRICT: não permite apagar um país que ainda tem usuários
    -- CASCADE seria perigoso aqui, pois apagaria todos os usuários do país
    CONSTRAINT fk_usuario_pais FOREIGN KEY (pais_residencia)
        REFERENCES pais (ddi) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE plataforma_usuario (

    -- FK para plataforma
    nro_plataforma INTEGER NOT NULL,

    -- FK para usuario.
    -- é o BIGINT nro_usuario, a FK passa a guardar um inteiro de 8 bytes
    nro_usuario BIGINT NOT NULL,

    -- Número da conta do usuário dentro da plataforma 
    -- decidimos renomear para não confundir com o nro usuário
    nro_conta BIGINT NOT NULL,

    -- PK composta com 2 atributos
    -- Garante que um usuário não se vincule duas vezes à mesma plataforma
    CONSTRAINT pk_plataforma_usuario PRIMARY KEY (nro_plataforma, nro_usuario),

    -- Dentro de uma plataforma, cada número de conta é de um só usuário
    CONSTRAINT uq_plataforma_usuario_conta UNIQUE (nro_plataforma, nro_conta),

    -- CASCADE: o vínculo não tem sentido sem a plataforma. Se a plataforma
    --  for removida, os vínculos vão junto
    CONSTRAINT fk_pu_plataforma FOREIGN KEY (nro_plataforma)
        REFERENCES plataforma (nro_plataforma) ON DELETE CASCADE ON UPDATE RESTRICT,

    -- CASCADE: se a conta do usuário for removida, seus vínculos também
    CONSTRAINT fk_pu_usuario FOREIGN KEY (nro_usuario)
        REFERENCES usuario (nro_usuario) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE streamer_pais (

    -- Substitui nick_streamer. Aponta para a PK artificial de usuario
    nro_streamer BIGINT NOT NULL,

    -- País emissor do passaporte SMALLINT, o mesmo tipo de pais.ddi
    ddi_pais SMALLINT NOT NULL,

    -- Número do passaporte. VARCHAR e não numérico pois passaportes têm letra
    nro_passaporte VARCHAR(20) NOT NULL,

    -- PK composta com 2 atributos 
    -- Garante um único passaporte por streamer em cada país
    CONSTRAINT pk_streamer_pais PRIMARY KEY (nro_streamer, ddi_pais),

    -- Um número de passaporte é único dentro do país que o emitiu.
    -- o mesmo número pode existir em países diferentes, então a unicidade é do par, e não do número isolado
    CONSTRAINT uq_streamer_pais_passaporte UNIQUE (ddi_pais, nro_passaporte),

    -- CASCADE: se o usuário for removido, seus dados de passaporte não devem permanecer no banco
    CONSTRAINT fk_sp_usuario FOREIGN KEY (nro_streamer)
        REFERENCES usuario (nro_usuario) ON DELETE CASCADE ON UPDATE RESTRICT,

    -- RESTRICT: país é dado de domínio. Não pode ser apagado enquanto houver passaporte emitido por ele.
    CONSTRAINT fk_sp_pais FOREIGN KEY (ddi_pais)
        REFERENCES pais (ddi) ON DELETE RESTRICT ON UPDATE RESTRICT
);


CREATE TABLE empresa_pais (

    -- FK para empresa.
    nro_empresa INTEGER NOT NULL,

    -- FK para país.
    ddi_pais SMALLINT NOT NULL,

    -- Identificador nacional da empresa 
    -- VARCHAR(50): identificadores podem conter letras e zeros à esquerda.
    -- NOT NULL: toda associação entre empresa e país deve ter um identificador.
    id_nacional VARCHAR(50) NOT NULL,

    -- PK composta com 2 atributos.
    -- Garante que uma empresa tenha apenas um identificador nacional cadastrado por país.
    CONSTRAINT pk_empresa_pais PRIMARY KEY (nro_empresa, ddi_pais),

    -- Garante que o mesmo identificador nacional não seja cadastrado para empresas diferentes dentro do mesmo país.
    -- O mesmo identificador pode existir em países diferentes.
    CONSTRAINT uq_empresa_pais_id_nacional UNIQUE (ddi_pais, id_nacional),

    -- CASCADE: se uma empresa for removida, seus identificadores nacionais também devem ser removidos.
    -- RESTRICT: impede alterar a PK da empresa enquanto referenciada.
    CONSTRAINT fk_ep_empresa FOREIGN KEY (nro_empresa)
        REFERENCES empresa (nro_empresa)
        ON DELETE CASCADE ON UPDATE RESTRICT,

    -- RESTRICT: não permite apagar um país que ainda possui identificadores nacionais de empresas associados.
    -- RESTRICT: impede alterar a PK do país enquanto referenciada.
    CONSTRAINT fk_ep_pais FOREIGN KEY (ddi_pais)
        REFERENCES pais (ddi)
        ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TYPE tipo_canal_enum AS ENUM ('privado', 'publico', 'misto');

CREATE TABLE canal (

    -- Chave artificial numérica que substitui o nome como PK
    -- BIGINT: permite uma grande quantidade de canais
    id_canal BIGINT GENERATED ALWAYS AS IDENTITY,

    -- Nome do canal
    -- NOT NULL + UNIQUE para preserva a unicidade da chave original
    nome_canal VARCHAR(255) NOT NULL,

    -- ENUM permite apenas privado, publico ou misto
    -- NOT NULL: todo canal precisa ter um tipo
    tipo tipo_canal_enum NOT NULL,

    -- Data de início do canal
    -- DATE: não é necessário armazenar a hora
    data_inicio DATE NOT NULL,

    -- Descrição do canal
    -- TEXT: permite descrições de diferentes tamanhos
    descricao TEXT NOT NULL,

    -- Quantidade de visualizações do canal
    --! Atributo derivado. Deve ser removido posteriormente,
    --! pois pode ser calculado a partir dos vídeos do canal.
    qtd_visualizacoes BIGINT NOT NULL DEFAULT 0,

    -- FK para usuario, identificando o streamer dono do canal
    -- BIGINT: mesmo tipo da PK de usuario
    nro_streamer BIGINT NOT NULL,

    -- FK para plataforma
    -- INTEGER: mesmo tipo da PK de plataforma
    nro_plataforma INTEGER NOT NULL,

    -- PK artificial numérica
    CONSTRAINT pk_canal PRIMARY KEY (id_canal),

    -- Preserva a unicidade do nome do canal
    CONSTRAINT uq_canal_plataforma_nome UNIQUE (nro_plataforma, nome_canal),

    -- Impede quantidade negativa de visualizações
    --! Remover junto com qtd_visualizacoes.
    CONSTRAINT ck_canal_qtd_visualizacoes
        CHECK (qtd_visualizacoes >= 0),

    -- RESTRICT: impede excluir um usuário que seja dono de um canal
    -- RESTRICT: impede alterar a PK do usuário enquanto referenciada
    CONSTRAINT fk_canal_usuario FOREIGN KEY (nro_streamer)
        REFERENCES usuario (nro_usuario)
        ON DELETE RESTRICT ON UPDATE RESTRICT,

    -- RESTRICT: impede excluir uma plataforma que tenha canais
    -- RESTRICT: impede alterar a PK da plataforma enquanto referenciada
    CONSTRAINT fk_canal_plataforma FOREIGN KEY (nro_plataforma)
        REFERENCES plataforma (nro_plataforma)
        ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE patrocinio (

    -- Empresa patrocinadora
    nro_empresa INTEGER NOT NULL,

    -- Substitui o par (nome_canal, nro_plataforma). Não guarda mais no nome do canal
    -- Não guardamos por causa de redundancia : o nome já existe em canal copiá-lo em patrocinio duplica o dado, e se o nome do canal mudasse, teria que atualizar nas duas tabelas
    nro_canal BIGINT NOT NULL,

    -- Valor do patrocínio.
    -- NUMERIC(14, 2): precisão exata para dinheiro, com 2 casas decimais nunca FLOAT/REAL.
    valor NUMERIC(14, 2) NOT NULL,

    -- PK composta com 2 atributos
    -- Assumimos que cada empresa patrocina um canal no máximo uma vez
    CONSTRAINT pk_patrocinio PRIMARY KEY (nro_empresa, nro_canal),

    -- Regra de domínio: o valor é positivo
    CONSTRAINT ck_patrocinio_valor CHECK (valor > 0),

    -- RESTRICT: o sistema não guarda histórico, só patrocínios vigentes. Mesmo assim, uma empresa não pode
    --   sumir enquanto tiver um patrocínio vigente; para encerrar o patrocínio, apaga-se a linha daqui antes.
    CONSTRAINT fk_patrocinio_empresa FOREIGN KEY (nro_empresa)
        REFERENCES empresa (nro_empresa) ON DELETE RESTRICT ON UPDATE RESTRICT,

    -- RESTRICT também: apagar um canal não deve apagar patrocínios vigentes silenciosamente
    CONSTRAINT fk_patrocinio_canal FOREIGN KEY (nro_canal)
        REFERENCES canal (id_canal) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE nivel_canal (

    -- Substitui o par (nome_canal, nro_plataforma).
    nro_canal BIGINT NOT NULL,

    -- Número do nível dentro do canal (1, 2, 3...)
    -- SMALLINT: um canal tem poucos níveis, e o limite de 32.767 sobra.
    nivel SMALLINT NOT NULL,

    -- Nome do nível, definido por canal.
    -- NOT NULL: todo nível tem nome. UNIQUE com nro_canal: um canal não repete nome entre seus níveis.
    nome VARCHAR(50) NOT NULL,

    -- Valor do nível.
    -- NUMERIC(10, 2): precisão exata para dinheiro Preço de um nível é bem menor que um patrocínio, então 10 dígitos bastam.
    valor NUMERIC(10, 2) NOT NULL,

    -- Imagem (GIF) do nível, guardada como caminho ou URL.
    -- VARCHAR e não BYTEA: guardar o arquivo dentro do banco incha a
    --   tabela e os backups. O arquivo fica em um storage e o banco guarda só a referência.
    -- NOT NULL: assumimos que todo nível tem um GIF.
    gif VARCHAR(500) NOT NULL,

    -- PK composta com 2 atributos 
    -- Garante que um canal não tenha dois níveis com o mesmo número.
    CONSTRAINT pk_nivel_canal PRIMARY KEY (nro_canal, nivel),

    -- Dentro de um canal, cada nível tem um nome diferente.
    CONSTRAINT uq_nivel_canal_nome UNIQUE (nro_canal, nome),

    -- Níveis de 1 a 5.
    CONSTRAINT ck_nivel_canal_nivel CHECK (nivel BETWEEN 1 AND 5),

    -- Regra de domínio: o valor é positivo.
    CONSTRAINT ck_nivel_canal_valor CHECK (valor > 0),

    -- CASCADE: o nível não existe sem o canal. Se o canal for removido, seus níveis vão junto.
    -- RESTRICT: impede alterar a PK do canal enquanto referenciada.
    CONSTRAINT fk_nivel_canal_canal FOREIGN KEY (nro_canal)
        REFERENCES canal (id_canal)
        ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE inscricao (

    -- FK para canal
    id_canal BIGINT NOT NULL,

    -- FK para usuario. BIGINT, mesmo tipo da PK de usuario.
    nro_usuario BIGINT NOT NULL,

    -- Nível de membro do usuário naquele canal.
    -- SMALLINT: suficiente para representar os cinco níveis (1 a 5).
    -- NOT NULL: toda inscrição precisa ter um nível.
    nivel SMALLINT NOT NULL,

    -- PK composta com 2 atributos numéricos.
    -- Garante que um usuário tenha apenas uma inscrição vigente em cada canal
    CONSTRAINT pk_inscricao PRIMARY KEY (id_canal, nro_usuario),

    -- CASCADE: se o usuário for removido, suas inscrições também devem ser removidas.
    -- RESTRICT: impede alterar a PK do usuário enquanto referenciada.
    CONSTRAINT fk_inscricao_usuario FOREIGN KEY (nro_usuario)
        REFERENCES usuario (nro_usuario)
        ON DELETE CASCADE ON UPDATE RESTRICT,

    -- FK composta para nivel_canal garante que o nível escolhido exista no canal informado.
    -- RESTRICT: impede excluir ou alterar um nível de canal enquanto existirem inscrições associadas a ele.
    CONSTRAINT fk_inscricao_nivel_canal FOREIGN KEY (id_canal, nivel)
        REFERENCES nivel_canal (nro_canal, nivel)
        ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE video (
    -- Chave artificial numérica que substitui (canal, titulo, data/hora) como PK
    -- BIGINT: permite uma grande quantidade de vídeos
    id_video BIGINT GENERATED ALWAYS AS IDENTITY,

    -- Título do vídeo. Junto com o canal e a data/hora, é o identificador natural (UNIQUE abaixo)
    titulo VARCHAR(255) NOT NULL,

    -- TIMESTAMP para guardar data e hora de postagem. Faz parte do identificador natural (UNIQUE abaixo)
    dataH TIMESTAMP NOT NULL,

    -- NOT NULL: todo vídeo tem um tema
    tema VARCHAR(127) NOT NULL,

    -- Duração em segundos. NOT NULL: todo vídeo tem duração
    duracao INTEGER NOT NULL,

    -- Pico de visualizações simultâneas.
    -- Dado medido pela plataforma, não derivado de outra tabela (não existe tabela de sessões de visualização),
    --   por isso não precisa de trigger.
    -- DEFAULT 0: o vídeo começa sem nenhuma visualização
    visu_simul INTEGER NOT NULL DEFAULT 0,

    -- Total de visualizações. Também é dado medido.
    -- BIGINT: mesmo tipo de canal.qtd_visualizacoes
    visu_total BIGINT NOT NULL DEFAULT 0,

    -- FK para canal. Substitui o par (nome_canal, nro_plataforma)
    -- BIGINT: mesmo tipo da PK de canal
    -- NOT NULL: todo vídeo pertence a um único canal
    nro_canal BIGINT NOT NULL,

    -- PK artificial: as tabelas filhas (participa, comentario) referenciam id_video com uma única coluna
    CONSTRAINT pk_video PRIMARY KEY (id_video),

    -- Preserva o identificador natural do enunciado (título + data/hora), agora dentro do canal.
    -- Sem nro_canal na chave, só poderia existir um vídeo com aquele título e horário em todo o banco.
    CONSTRAINT uq_video_canal_titulo_data UNIQUE (nro_canal, titulo, dataH),

    -- Duração zero ou negativa não faz sentido
    CONSTRAINT ck_video_duracao CHECK (duracao > 0),

    -- O pico simultâneo nunca é negativo nem maior que o total de visualizações
    CONSTRAINT ck_video_visu CHECK (visu_simul >= 0 AND visu_total >= visu_simul),

    -- RESTRICT: não deixa apagar um canal que ainda tem vídeos, pois os vídeos
    --   têm comentários e doações associados. CASCADE apagaria esse histórico
    -- RESTRICT: a PK de canal é identity e não muda
    CONSTRAINT fk_video_canal FOREIGN KEY (nro_canal)
        REFERENCES canal (id_canal) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE participa (

    -- FK para video. Substitui (nome_canal, nro_plataforma, titulo_video, dataH_video)
    id_video BIGINT NOT NULL,

    -- FK para usuario (o streamer participante).
    -- Registra apenas os streamers além do dono do canal
    nro_streamer BIGINT NOT NULL,

    -- PK composta com 2 atributos numéricos.
    -- Garante que um streamer apareça uma única vez em cada vídeo
    CONSTRAINT pk_participa PRIMARY KEY (id_video, nro_streamer),

    -- CASCADE: a participação não existe sem o vídeo.
    CONSTRAINT fk_participa_video FOREIGN KEY (id_video)
        REFERENCES video (id_video)
        ON DELETE CASCADE ON UPDATE RESTRICT,

    -- CASCADE: se o usuário for removido, suas participações também
    CONSTRAINT fk_participa_usuario FOREIGN KEY (nro_streamer)
        REFERENCES usuario (nro_usuario)
        ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE comentario (

    -- Chave artificial numérica.
    -- BIGINT: é a tabela de maior volume do modelo (vários comentários por vídeo)
    id_comentario BIGINT GENERATED ALWAYS AS IDENTITY,

    -- FK para video. Substitui (nro_canal, titulo_video, dataH_video).
    id_video BIGINT NOT NULL,

    -- valor deve ser gerado por uma trigger
    seq INTEGER NOT NULL,

    -- FK e NOT NULL, todo comentario precisa de um usuário autor
    nro_usuario BIGINT NOT NULL,

    -- TEXT para permitir comentários de diferentes tamanhos
    texto TEXT NOT NULL,

    -- Data e hora do comentário
    dataH TIMESTAMP NOT NULL,

    -- true/false para comentarios online/offline
    coment_on BOOLEAN NOT NULL,

    CONSTRAINT pk_comentario PRIMARY KEY (id_comentario),

    -- O sequencial é único dentro do vídeo.
    -- Se o seq for um contador por usuário em cada vídeo, use
    --   UNIQUE (id_video, nro_usuario, seq).
    CONSTRAINT uq_comentario_video_usuario_seq UNIQUE (id_video, nro_usuario, seq),

    -- O sequencial começa em 1
    CONSTRAINT ck_comentario_seq CHECK (seq > 0),

    -- CASCADE: o comentário não existe sem o vídeo.
    -- RESTRICT: a PK de video é identity e não muda.
    CONSTRAINT fk_comentario_video FOREIGN KEY (id_video)
        REFERENCES video (id_video)
        ON DELETE CASCADE ON UPDATE RESTRICT,

    -- RESTRICT: a PK de usuario é identity e não muda
    CONSTRAINT fk_comentario_usuario FOREIGN KEY (nro_usuario)
        REFERENCES usuario (nro_usuario)
        ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TYPE status_doacao_enum AS ENUM ('pendente', 'confirmado', 'recusado', 'estornado');

CREATE TABLE doacao (

    -- Substitui as seis colunas (canal, plataforma, vídeo, data, usuário, seq_comentario).
    -- BIGINT: mesmo tipo da PK de comentario.
    id_comentario BIGINT NOT NULL,

    -- Sequencial do pagamento dentro do comentário, gerado por trigger.
    seq_pg INTEGER NOT NULL,

    -- NUMERIC(14, 2): precisão exata para dinheiro.
    valor NUMERIC(14, 2) NOT NULL,

    -- ENUM: domínio fechado.
    status status_doacao_enum NOT NULL,

    -- PK composta com 2 atributos (eram 7 no modelo).
    CONSTRAINT pk_doacao PRIMARY KEY (id_comentario, seq_pg),

    CONSTRAINT ck_doacao_seq_pg CHECK (seq_pg > 0),

    -- Regra de domínio: o valor é positivo.
    CONSTRAINT ck_doacao_valor CHECK (valor > 0),

    -- RESTRICT: a tabela guarda histórico financeiro, então um comentário
    --   com doações não pode ser apagado por engano.
    CONSTRAINT fk_doacao_comentario FOREIGN KEY (id_comentario)
        REFERENCES comentario (id_comentario)
        ON DELETE RESTRICT ON UPDATE RESTRICT
);

/*
Os valores do ENUM status são suposição,
Efeito em cadeia nos deletes: comentario é apagado junto com o vídeo (CASCADE), mas doacao usa RESTRICT. Um vídeo com comentários que receberam doações não pode ser apagado, e o mesmo vale para o canal. É coerente com proteger o histórico financeiro.
Se cada comentário tiver no máximo uma doação, o seq_pg é desnecessário e a PK seria só id_comentario. Como o modelo traz seq_pg, assumimos vários.
Moeda do valor: o modelo não diz.
*/

CREATE TABLE bitcoin (

    -- Substituimos as seis primeiras colunas (canal, plataforma, vídeo, data, usuário, seq_comentario).
    -- BIGINT: mesmo tipo de doacao.id_comentario.
    id_comentario BIGINT NOT NULL,

    -- Corresponde ao seq_doacao do modelo, que referencia doacao.seq_pg.
    -- Usamos o mesmo nome da outra ponta da FK para não confundir.
    seq_pg INTEGER NOT NULL,

    -- Identificador da transação na blockchain: 64 caracteres hexadecimais.
    -- CHAR(64): tamanho fixo. Texto e não numérico, porque é um hash.
    -- NOT NULL: sem TxID não há como comprovar o pagamento.
    txid CHAR(64) NOT NULL,

    -- A PK é a própria chave da doação: no máximo um detalhe bitcoin por doação.
    CONSTRAINT pk_bitcoin PRIMARY KEY (id_comentario, seq_pg),

    -- Uma transação paga uma única doação.
    -- Se uma mesma transação puder pagar várias doações, remova esta constraint.
    CONSTRAINT uq_bitcoin_txid UNIQUE (txid),

    -- Formato válido: 64 dígitos hexadecimais em minúsculas.
    -- Normalize para minúsculas antes de inserir, senão o mesmo TxID
    --   poderia ser cadastrado duas vezes com caixa diferente.
    CONSTRAINT ck_bitcoin_txid CHECK (txid ~ '^[0-9a-f]{64}$'),

    -- CASCADE: o detalhe bitcoin não existe sem a doação.
    -- RESTRICT: a PK de doacao não muda.
    CONSTRAINT fk_bitcoin_doacao FOREIGN KEY (id_comentario, seq_pg)
        REFERENCES doacao (id_comentario, seq_pg)
        ON DELETE CASCADE ON UPDATE RESTRICT
);
/*
PK igual à FK: é o padrão de tabela de especialização. A chave da bitcoin é a chave da doacao, o que impede duas linhas para a mesma doação. Não precisa de chave artificial, porque nenhuma outra tabela referencia bitcoin (por enquanto).
CASCADE aqui e RESTRICT em doacao: a doação guarda o histórico financeiro e é protegida contra remoção acidental. O detalhe bitcoin é parte dela e acompanha o pai se ela for removida de forma explícita.
UNIQUE (txid) é uma suposição: 
Nada impede que uma doação apareça em duas tabelas de especialização (por exemplo, bitcoin e outra forma de pagamento) ao mesmo tempo. Se existirem outras formas de pagamento no modelo, garantir exclusividade exige uma coluna de tipo em doacao ou uma trigger.
*/

CREATE TABLE paypal (

    -- Substituimos as seis primeiras colunas (canal, plataforma, vídeo, data, usuário, seq_comentario).
    -- BIGINT: mesmo tipo de doacao.id_comentario.
    id_comentario BIGINT NOT NULL,

    -- Corresponde ao seq_doacao do modelo, que referencia doacao.seq_pg.
    seq_pg INTEGER NOT NULL,

    -- Identificador da transação no PayPal.
    -- VARCHAR e não numérico: é alfanumérico.
    -- 50 dá folga para o formato usado pelo PayPal.
    -- NOT NULL: sem o identificador não há como comprovar o pagamento.
    id_paypal VARCHAR(50) NOT NULL,

    -- A PK é a própria chave da doação: no máximo um detalhe PayPal por doação.
    CONSTRAINT pk_paypal PRIMARY KEY (id_comentario, seq_pg),

    -- Uma transação PayPal paga uma única doação.
    CONSTRAINT uq_paypal_id UNIQUE (id_paypal),

    -- CASCADE: o detalhe PayPal não existe sem a doação.
    -- RESTRICT: a PK de doacao não muda.
    CONSTRAINT fk_paypal_doacao FOREIGN KEY (id_comentario, seq_pg)
        REFERENCES doacao (id_comentario, seq_pg)
        ON DELETE CASCADE ON UPDATE RESTRICT
);
/*
1-UNIQUE (id_paypal) é suposição, como foi o txid. Confirme com o enunciado.
2-Sem CHECK de formato: não sei o padrão exato do identificador do PayPal, então não inventei uma regra. Se o enunciado definir o tamanho ou o formato, entra um CHECK.
3-A exclusividade entre formas de pagamento agora importa: com bitcoin e paypal, nada impede que a mesma doação apareça nas duas tabelas. Se o modelo diz que cada doação 
é paga por uma única forma, a solução é uma coluna de tipo em doacao (um ENUM) e uma FK que inclua esse tipo, ou uma trigger. Se existirem mais formas de pagamento no modelo,
 me mande todas e eu aplico a solução nas três de uma vez.
*/

CREATE TYPE bandeira_cartao_enum AS ENUM ('visa', 'mastercard', 'elo', 'amex', 'hipercard');

CREATE TABLE cartao_credito (

    -- Substituimos as seis primeiras colunas (canal, plataforma, vídeo, data, usuário, seq_comentario).
    -- BIGINT: mesmo tipo de doacao.id_comentario.
    id_comentario BIGINT NOT NULL,

    -- Corresponde ao seq_doacao do modelo, que referencia doacao.seq_pg.
    seq_pg INTEGER NOT NULL,

    -- Número do cartão 
    -- VARCHAR e não numérico: tem zeros à esquerda e ninguém faz conta com ele.
    -- Sem UNIQUE: o mesmo cartão pode pagar várias doações.
    -- NOT NULL: sem o número a forma de pagamento não está definida.
    nro_cartao VARCHAR(19) NOT NULL,

    -- ENUM: domínio fechado de bandeiras. NOT NULL: todo cartão tem bandeira.
    bandeira bandeira_cartao_enum NOT NULL,

    -- A PK é a própria chave da doação: no máximo um detalhe de cartão por doação.
    CONSTRAINT pk_cartao_credito PRIMARY KEY (id_comentario, seq_pg),

    -- Cartões têm de 13 a 19 dígitos, sem espaços nem traços.
    CONSTRAINT ck_cartao_credito_nro CHECK (nro_cartao ~ '^[0-9]{13,19}$'),

    -- CASCADE: o detalhe do cartão não existe sem a doação.
    -- RESTRICT: a PK de doacao não muda.
    CONSTRAINT fk_cartao_credito_doacao FOREIGN KEY (id_comentario, seq_pg)
        REFERENCES doacao (id_comentario, seq_pg)
        ON DELETE CASCADE ON UPDATE RESTRICT
);

/*
1-Número de cartão completo é dado sensível. Para o exercício, guardar o número como o modelo pede é o esperado.
 Em um sistema real, o número completo não deve ficar no banco (norma PCI DSS): o padrão é guardar um token do gateway de pagamento e,
  no máximo, os quatro últimos dígitos. Vale mencionar isso na entrega.
2-A bandeira é derivável do número (pelo prefixo), mas o modelo a traz como atributo, então mantive a coluna.
3-Os valores do ENUM são suposição. Adicionar valores depois é fácil (ALTER TYPE ... ADD VALUE), removê-los não.
4-Exclusividade entre formas de pagamento: agora são três tabelas de especialização (bitcoin, paypal, cartao_credito).
 Se existirem outras, me diga quais, e depois aplico em todas a regra de que cada doação usa uma única forma.
*/