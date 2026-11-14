# Passo a passo para reprodução da solução

Trabalho final de Projeto de Banco de Dados (UFF, 2026/2, Prof. Marcos Bedo).
É um banco de streamers de jogos online em PostgreSQL, com design físico, triggers, functions de inserção, povoamento com distribuição realista, 5 visões, 12 consultas em PL/pgSQL e 5 índices.

## Requisitos

- PostgreSQL 14 ou mais novo. Testado no **PostgreSQL 18.4**.
- `psql` disponível no terminal. No Windows, use o "SQL Shell (psql)" que vem com o instalador.

## Passo a passo

**1. Crie um banco vazio** (o nome `streaming` é só uma sugestão):

```bash
createdb -U postgres streaming
```

**2. Rode os 3 primeiros arquivos, nesta ordem, a partir da pasta do projeto:**

```bash
psql -U postgres -d streaming -v ON_ERROR_STOP=1 -f sql/1_ddl.sql
```

```bash
psql -U postgres -d streaming -v ON_ERROR_STOP=1 -f sql/2_plpgsql.sql
```

```bash
psql -U postgres -d streaming -v ON_ERROR_STOP=1 -f sql/3_dados.sql
```

O povoamento leva cerca de 1 minuto (o arquivo tem uns 5 MB de dados). Ele roda numa transação só: se algo falhar, o banco fica vazio, sem dados pela metade. Os dados são sempre os mesmos, porque o arquivo é gerado com semente fixa (veja "Regenerar o povoamento" abaixo).

**3. Rode as consultas.** Exemplos:

```sql
SELECT * FROM consulta1_streamers_mais_videos() LIMIT 10;      -- todas as plataformas
SELECT * FROM consulta1_streamers_mais_videos(2) LIMIT 10;     -- só a Twitch
SELECT * FROM consulta5_patrocinios('Anderson-Riley Corp.');        -- versão polimórfica (por nome)
SELECT * FROM consulta11_top_k_faturamento(5);                 -- top 5 canais que mais faturam
SELECT * FROM consulta12_top_k_plataformas(3, 'Twitch');       -- desafio, versão polimórfica
```

As 12 consultas, com os parâmetros de cada uma, estão na Seção 2 do `sql/2_plpgsql.sql`. Para rodar todas de uma vez, com e sem filtro, e as functions de inserção (tudo desfeito no fim por `ROLLBACK`):

```bash
psql -U postgres -d streaming -v ON_ERROR_STOP=1 -f sql/4_chamadas.sql
```

No pgAdmin, rodar o arquivo inteiro mostra só o resultado do último comando. Para ver uma consulta por vez, selecione a linha e aperte F5.

## O que tem em cada arquivo

Os 4 arquivos de `sql/` seguem os itens do aviso do professor no Classroom (o 5º item é o PDF do relatório, escrito pelo grupo).

| Arquivo | Item do aviso | Conteúdo |
|---|---|---|
| `sql/1_ddl.sql` | 1. DDL das tabelas | Design físico: 3 ENUMs e as 20 tabelas, com PK, FK (e suas políticas), UNIQUE, NOT NULL e CHECK comentados. |
| `sql/2_plpgsql.sql` | 2. PL/pgSQL | Seção 1: 7 triggers de consistência, functions de inserção e as 5 visões (2 materializadas e 3 virtuais). Seção 2: as 12 consultas como functions parametrizadas (a 5 e a 12 são polimórficas). Seção 3: os 5 índices, com a justificativa de cada um. |
| `sql/3_dados.sql` | 3. Dados para inserção | Carga de 1.000 a 10.000 tuplas por tabela, com dados de aparência real (nomes, idiomas, datas e distribuição de cauda longa), feita pelas functions de inserção. É **gerado** por `dev/gerar_povoamento.py` (Faker); não edite à mão. |
| `sql/4_chamadas.sql` | 4. Chamadas para teste | As 12 consultas (com e sem filtro, e as versões polimórficas) e as functions de inserção, dentro de `BEGIN ... ROLLBACK`. |

| Outros arquivos | Conteúdo |
|---|---|
| `medicoes/medir_indices.py` | Script que mede cada índice sem e com ele, com o cache frio. |
| `medicoes/resultados.md` | Os números dessa medição (média e desvio padrão) e o gráfico `grafico_indices.svg`. |
| `docs/EXPLICACAO-DIDATICA.md` | O porquê de cada decisão, para estudo do grupo e para a apresentação. |

## Regenerar o povoamento (opcional)

O `sql/3_dados.sql` já vem pronto e é o que vale para a entrega. Para gerá-lo de novo (por exemplo, depois de mudar o gerador), é preciso Python 3 e a biblioteca Faker:

```bash
python3 -m venv /tmp/venv && /tmp/venv/bin/pip install faker
```

```bash
/tmp/venv/bin/python dev/gerar_povoamento.py
```

A semente é fixa: com a mesma versão do Faker, o arquivo sai idêntico. Depois de regenerar, rode `python3 dev/atualizar_explicacao.py` para atualizar os trechos de código do `docs/EXPLICACAO-DIDATICA.md`.

## Reproduzir a medição dos índices (opcional)

A medição compara cada índice com a situação sem ele, reiniciando o PostgreSQL antes de cada execução (cache frio) e rodando cada operação 10 vezes. Ela sobe um PostgreSQL temporário sozinha, então não mexe no seu banco. Precisa do Python 3 e dos programas do PostgreSQL (`initdb`, `pg_ctl`, `psql`):

```bash
python3 medicoes/medir_indices.py
```

Leva cerca de 3 minutos e reescreve `medicoes/tempos.csv` e `medicoes/grafico_indices.svg`. Os tempos variam conforme a máquina; o que importa é a comparação sem/com.

## Para o grupo: testes automáticos

`./dev/testar.sh` faz o processo inteiro sem mexer em nenhum banco seu:
1. Sobe um PostgreSQL temporário.
2. Roda os 4 arquivos .sql.
3. Confere, com `dev/verificacoes.sql`:
   - o volume de cada tabela;
   - os atributos derivados;
   - os sequenciais;
   - se as triggers barram o que devem barrar;
   - se as 12 consultas funcionam.
4. Apaga tudo.

O `docs/EXPLICACAO-DIDATICA.md` mostra trechos dos arquivos `.sql`. Depois de alterar um `.sql`, atualize esses trechos com o comando abaixo (o `./dev/testar.sh` avisa quando o documento estiver desatualizado):

```bash
python3 dev/atualizar_explicacao.py
```

O hook de pre-push roda esse script antes de cada push. Num clone novo, ligue o hook uma vez:

```bash
git config core.hooksPath dev/hooks
```
