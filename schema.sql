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
    CONSTRAINT uq_plataforma_nome UNIQUE (nome)
    CONSTRAINT ck_plataforma_qtd_users CHECK (qtd_users>=0)--! esse atributo não deve permanecer na tabela, deve ser removido e escolher uma politica de trigger para atualizar esse atributo

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
    -- UNIQUE: duas moedas não devem ter o mesmo nome.
    -- VARCHAR(50): nomes de moeda são curtos, e o limite evita lixo.
    nome VARCHAR(50) NOT NULL UNIQUE,
    -- Fator de conversão para dólar (USD = 1).
    -- NUMERIC(18, 6): 18 dígitos no total, 6 casas decimais suficiente para taxas como 0,182345.
    -- NOT NULL: uma moeda sem fator não serve para conversão.
    -- CHECK (> 0): fator zero ou negativo não faz sentido e zeraria ou inverteria todo valor convertido.
    fator_conver NUMERIC(18, 6) NOT NULL CHECK (fator_conver > 0),

    PRIMARY KEY (id)
);

CREATE TABLE pais(
     -- SMALLINT: DDIs têm no máximo 3 dígitos
    ddi SMALLINT,
    -- NOT NULL: obrigatório.
    -- UNIQUE: dois países não devem ter o mesmo nome.
    nome VARCHAR(100) NOT NULL UNIQUE,
    -- NOT NULL: assume que todo país tem uma moeda no modelo.
    moeda_id SMALLINT NOT NULL,

    CONSTRAINT pk_pais PRIMARY KEY (ddi),

    CONSTRAINT uq_pais_nome UNIQUE (nome),

    -- ON DELETE RESTRICT: não deixa apagar uma moeda que ainda é usada por algum país.
    -- ON UPDATE RESTRICT: a PK de conversao é identity e não muda.
    CONSTRAINT fk_pais_conversao FOREIGN KEY (moeda_id)
        REFERENCES conversao (id) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE usuario (

    -- Chave artificial que substitui "nick" como PK.
    -- BIGINT: é a tabela com maior cardinalidade do modelo. 
    nro_usuario BIGINT GENERATED ALWAYS AS IDENTITY,

    -- Antiga PK natural, agora chave candidata.
    -- NOT NULL + UNIQUE: preserva a unicidade da chave original.
    nick VARCHAR(50) NOT NULL,

    -- E-mail. NOT NULL + UNIQUE: uma conta por e-mail. 254 é o tamanho máximo de um e-mail válido (RFC).
    email VARCHAR(254) NOT NULL,

    -- Data de nascimento. DATE, não TIMESTAMP: a hora não importa.
    -- NOT NULL: assumi que é obrigatória no cadastro.
    data_nasc DATE NOT NULL,

    -- Telefone. VARCHAR e não numérico: tem "+", parênteses, zeros à
    --   esquerda, e ninguém faz conta com ele.
    -- Nulável: assumimos que é opcional.
    -- Sem UNIQUE: é comum compartilhar telefone .
    telefone VARCHAR(20),

    -- Endereço postal. Nulável: assumimos que é opcional.
    end_postal VARCHAR(255),

    -- FK para o país de residência. SMALLINT, o mesmo tipo de pais.ddi.
    -- NOT NULL: assumimos que todo usuário informa o país.
    pais_residencia SMALLINT NOT NULL,

    CONSTRAINT pk_usuario PRIMARY KEY (nro_usuario),
    CONSTRAINT uq_usuario_nick UNIQUE (nick),
    CONSTRAINT uq_usuario_email UNIQUE (email),

    -- RESTRICT: não permite apagar um país que ainda tem usuários.
    -- CASCADE seria perigoso aqui, pois apagaria todos os usuários do país.
    CONSTRAINT fk_usuario_pais FOREIGN KEY (pais_residencia)
        REFERENCES pais (ddi) ON DELETE RESTRICT ON UPDATE RESTRICT
);


