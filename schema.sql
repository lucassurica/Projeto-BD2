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
    nome VARCHAR(100) NOT NULL UNIQUE,
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

    -- RESTRICT: empresa é dado de domínio e esta tabela guarda histórico financeiro. Não pode sumir enquanto houver patrocínio.
    CONSTRAINT fk_patrocinio_empresa FOREIGN KEY (nro_empresa)
        REFERENCES empresa (nro_empresa) ON DELETE RESTRICT ON UPDATE RESTRICT,

    -- RESTRICT também: apagar um canal não deve apagar os registros de quanto foi pago a ele
    CONSTRAINT fk_patrocinio_canal FOREIGN KEY (nro_canal)
        REFERENCES canal (id_canal) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE nivel_canal (

    -- Substitui o par (nome_canal, nro_plataforma).
    nro_canal BIGINT NOT NULL,

    -- Número do nível dentro do canal (1, 2, 3...)
    -- SMALLINT: um canal tem poucos níveis, e o limite de 32.767 sobra.
    nivel SMALLINT NOT NULL,

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
    -- Título do vídeo. Faz parte da identificação (PK)
    titulo VARCHAR(255) NOT NULL,

    -- TIMESTAMP para guardar data e hora de postagem. Faz parte da identificação (PK)
    dataH TIMESTAMP NOT NULL,

    -- NOT NULL: todo vídeo tem um tema
    tema VARCHAR(127) NOT NULL,

    -- Duração em segundos. NOT NULL: todo vídeo tem duração
    duracao INTEGER NOT NULL,

    -- Pico de visualizações simultâneas.
    -- Atributo derivado: a trigger atualiza esse valor.
    -- DEFAULT 0: o vídeo começa sem nenhuma visualização
    visu_simul INTEGER NOT NULL DEFAULT 0,

    -- Total de visualizações. A trigger também atualiza esse valor.
    -- BIGINT: mesmo tipo de canal.qtd_visualizacoes
    visu_total BIGINT NOT NULL DEFAULT 0,

    -- FK para canal. Substitui o par (nome_canal, nro_plataforma)
    -- BIGINT: mesmo tipo da PK de canal
    -- NOT NULL: todo vídeo pertence a um único canal
    nro_canal BIGINT NOT NULL,

    -- PK composta com 2 atributos, conforme o enunciado
    CONSTRAINT pk_video PRIMARY KEY (titulo, dataH),

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

CREATE TABLE comentario (
    --campos relacionados a identificacao do vídeo 
    nro_canal BIGINT NOT NULL,
    titulo_video VARCHAR(255) NOT NULL,
    dataH_video TIMESTAMP NOT NULL,

    -- valor deve ser gerado por uma trigger
    seq INTEGER NOT NULL,

    --FK e NOT NULL, todo comentario precisa de um usuário autor
    nro_usuario BIGINT NOT NULL,

    -- TEXT para permitir comentários de diferentes tamanhos
    texto TEXT NOT NULL,

    dataH TIMESTAMP NOT NULL,

    -- true/false para comentarios online/offline
    coment_on BOOLEAN NOT NULL,

      -- O sequencial começa em 1
    CONSTRAINT ck_comentario_seq CHECK (seq > 0),

    -- RESTRICT, a PK de video não deve mudar
    CONSTRAINT fk_comentario_video FOREIGN KEY (nro_canal, titulo_video, dataH_video)
        REFERENCES video (nro_canal, titulo, dataH)
        ON DELETE CASCADE ON UPDATE RESTRICT,

    -- RESTRICT: a PK de usuario é identity e não muda
    CONSTRAINT fk_comentario_usuario FOREIGN KEY (nro_usuario)
        REFERENCES usuario (nro_usuario)
        ON DELETE RESTRICT ON UPDATE RESTRICT
)