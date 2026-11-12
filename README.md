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

**2. Rode os 5 arquivos, nesta ordem, a partir da pasta do projeto:**

```bash
psql -U postgres -d streaming -v ON_ERROR_STOP=1 -f sql/01_ddl.sql
```

```bash
psql -U postgres -d streaming -v ON_ERROR_STOP=1 -f sql/02_ddl_estendida.sql
```

```bash
psql -U postgres -d streaming -v ON_ERROR_STOP=1 -f sql/03_povoamento.sql
```

```bash
psql -U postgres -d streaming -v ON_ERROR_STOP=1 -f sql/04_consultas.sql
```

```bash
psql -U postgres -d streaming -v ON_ERROR_STOP=1 -f sql/05_indices.sql
```

O povoamento leva poucos segundos. Ele roda numa transação só: se algo falhar, o banco fica vazio, sem dados pela metade. Os dados são sempre os mesmos, porque a semente é fixa (`setseed`).

**3. Rode as consultas.** Exemplos:

```sql
SELECT * FROM consulta1_streamers_mais_videos() LIMIT 10;      -- todas as plataformas
SELECT * FROM consulta1_streamers_mais_videos(2) LIMIT 10;     -- só a Twitch
SELECT * FROM consulta5_patrocinios('Empresa 10 S.A.');        -- versão polimórfica (por nome)
SELECT * FROM consulta11_top_k_faturamento(5);                 -- top 5 canais que mais faturam
SELECT * FROM consulta12_top_k_plataformas(3, 'Twitch');       -- desafio, versão polimórfica
```

A lista completa, com um exemplo de cada consulta, está no fim de `sql/04_consultas.sql`.

## O que tem em cada arquivo

| Arquivo | Conteúdo |
|---|---|
| `sql/01_ddl.sql` | Design físico: 3 ENUMs e as 20 tabelas, com PK, FK (e suas políticas), UNIQUE, NOT NULL e CHECK comentados. |
| `sql/02_ddl_estendida.sql` | 7 triggers de consistência, functions de inserção e as 5 visões (2 materializadas e 3 virtuais). |
| `sql/03_povoamento.sql` | Carga de 1.000 a 10.000 tuplas por tabela, com distribuição concentrada (cauda longa), feita pelas functions de inserção. |
| `sql/04_consultas.sql` | As 12 consultas do enunciado como functions parametrizadas. A 5 e a 12 são polimórficas. |
| `sql/05_indices.sql` | Os 5 índices de apoio, com a justificativa de cada um e a conferência medida. |
| `medicoes/medir_indices.py` | Script que mede cada índice sem e com ele, com o cache frio. |
| `medicoes/resultados.md` | Os números dessa medição (média e desvio padrão) e o gráfico `grafico_indices.svg`. |
| `docs/EXPLICACAO-DIDATICA.md` | O porquê de cada decisão, para estudo do grupo e para a apresentação. |

## Reproduzir a medição dos índices (opcional)

A medição compara cada índice com a situação sem ele, reiniciando o PostgreSQL antes de cada execução (cache frio) e rodando cada operação 10 vezes. Ela sobe um PostgreSQL temporário sozinha, então não mexe no seu banco. Precisa do Python 3 e dos programas do PostgreSQL (`initdb`, `pg_ctl`, `psql`):

```bash
python3 medicoes/medir_indices.py
```

Leva cerca de 3 minutos e reescreve `medicoes/tempos.csv` e `medicoes/grafico_indices.svg`. Os tempos variam conforme a máquina; o que importa é a comparação sem/com.

## Para o grupo: testes automáticos

`./dev/testar.sh` faz o processo inteiro sem mexer em nenhum banco seu:
1. Sobe um PostgreSQL temporário.
2. Roda os 5 arquivos.
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
