#!/bin/sh
# Testes locais. Uso: ./dev/testar.sh   (o hook de pre-push também chama este script)
#
# Sobe um PostgreSQL DESCARTÁVEL (pasta temporária, porta aleatória, só localhost), roda os 5 arquivos
# da entrega na ordem do README, roda dev/verificacoes.sql e apaga tudo no fim. Não toca em nenhum
# banco que você já tenha.
# Precisa dos programas do PostgreSQL (initdb, pg_ctl, psql). Procura no PATH e em /Library/PostgreSQL/*/bin.
cd "$(dirname "$0")/.." || exit 1
falhou=0
passo() {  # passo "nome" comando...
  nome=$1; shift
  if "$@" >/tmp/testar.$$ 2>&1; then echo "ok     $nome"
  else echo "FALHOU $nome"; tail -n 25 /tmp/testar.$$; falhou=1; fi
  rm -f /tmp/testar.$$
}

# --- localizar o PostgreSQL ---
if command -v initdb >/dev/null 2>&1; then
  PGBIN=$(dirname "$(command -v initdb)")
else
  PGBIN=$(ls -d /Library/PostgreSQL/*/bin /opt/homebrew/opt/postgresql*/bin 2>/dev/null | sort -V | tail -n 1)
fi
if [ -z "$PGBIN" ] || [ ! -x "$PGBIN/initdb" ]; then
  echo "FALHOU postgres: initdb não encontrado. Instale o PostgreSQL (https://www.postgresql.org/download/) e rode de novo."
  exit 1
fi

passo "sintaxe dev/testar.sh" sh -n dev/testar.sh
# O código dentro de docs/EXPLICACAO-DIDATICA.md precisa bater com os .sql (se falhar: python3 dev/atualizar_explicacao.py).
passo "explicação didática em dia" python3 -I dev/atualizar_explicacao.py --verificar

# --- banco descartável ---
DIR=$(mktemp -d /tmp/bd2teste.XXXXXX)
PORTA=$(( 50000 + $$ % 10000 ))
trap '"$PGBIN/pg_ctl" -D "$DIR/dados" -m immediate stop >/dev/null 2>&1; rm -rf "$DIR"' EXIT INT TERM

echo "...    ligando um PostgreSQL temporário na porta $PORTA"
if ! "$PGBIN/initdb" -D "$DIR/dados" -U postgres --auth=trust -E UTF8 --locale=C >"$DIR/initdb.log" 2>&1; then
  echo "FALHOU initdb"; tail -n 25 "$DIR/initdb.log"; exit 1
fi
# -k '': sem socket Unix (o caminho temporário pode passar de 103 caracteres); só TCP em 127.0.0.1.
if ! "$PGBIN/pg_ctl" -D "$DIR/dados" -o "-p $PORTA -k '' -c listen_addresses=127.0.0.1" -l "$DIR/pg.log" -w start >/dev/null 2>&1; then
  echo "FALHOU subir postgres"; tail -n 25 "$DIR/pg.log"; exit 1
fi

psql_teste() { "$PGBIN/psql" -h 127.0.0.1 -p "$PORTA" -U postgres -d streaming -X -q -v ON_ERROR_STOP=1 "$@"; }
"$PGBIN/createdb" -h 127.0.0.1 -p "$PORTA" -U postgres streaming

# --- blocos do projeto (mesma ordem do README) ---
passo "01_ddl.sql"             psql_teste -f sql/01_ddl.sql
passo "02_ddl_estendida.sql"   psql_teste -f sql/02_ddl_estendida.sql
passo "03_povoamento.sql"      psql_teste -f sql/03_povoamento.sql
passo "04_consultas.sql"       psql_teste -f sql/04_consultas.sql
passo "05_indices.sql"         psql_teste -f sql/05_indices.sql
passo "verificacoes.sql"       psql_teste -f dev/verificacoes.sql
# --- fim ---
[ "$falhou" = 0 ] && echo "Tudo certo." || echo "Há verificações falhando."
exit $falhou
