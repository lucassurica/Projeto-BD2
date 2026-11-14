#!/bin/sh
# Monta a pasta entrega/ com os arquivos pedidos no aviso do professor, juntando os arquivos de sql/.
# Uso: ./dev/montar_entrega.sh            (reescreve entrega/)
#      ./dev/montar_entrega.sh --verificar (só confere se entrega/ está em dia com sql/; usado pelo testar.sh)
#
# sql/ continua sendo a fonte: edite lá e rode este script de novo. O conteúdo de cada arquivo é copiado
# sem alteração; o script só acrescenta uma faixa marcando onde começa cada arquivo original.
cd "$(dirname "$0")/.." || exit 1

faixa() {  # faixa "ARQUIVO N — título" "sql/xx.sql"
  printf -- '-- #####################################################################\n'
  printf -- '-- %s\n' "$1"
  printf -- '-- Início do conteúdo de %s\n' "$2"
  printf -- '-- #####################################################################\n\n'
}
junta() {  # junta "título" destino origem...
  titulo=$1; destino=$2; shift 2
  for origem in "$@"; do faixa "$titulo" "$origem"; cat "$origem"; printf '\n\n'; done > "$destino"
}

monta() {  # monta pasta
  mkdir -p "$1"
  junta "ARQUIVO 1 — DDL DE CONSTRUÇÃO DAS TABELAS" "$1/1_ddl.sql" sql/01_ddl.sql
  # As consultas e os índices vêm depois das triggers e visões porque os índices I2 e I4 são sobre as
  # visões materializadas criadas no 02.
  junta "ARQUIVO 2 — PL/pgSQL: TRIGGERS, FUNCTIONS, VISÕES, CONSULTAS E ÍNDICES" "$1/2_plpgsql.sql" \
        sql/02_ddl_estendida.sql sql/04_consultas.sql sql/05_indices.sql
  junta "ARQUIVO 3 — DADOS PARA INSERÇÃO" "$1/3_dados.sql" sql/03_povoamento.sql
  junta "ARQUIVO 4 — CHAMADAS DAS CONSULTAS E FUNÇÕES PARA TESTE" "$1/4_chamadas.sql" sql/06_chamadas.sql
}

if [ "$1" = "--verificar" ]; then
  tmp=$(mktemp -d); monta "$tmp"
  r=0
  for f in "$tmp"/*.sql; do cmp -s "$f" "entrega/$(basename "$f")" || r=1; done
  rm -rf "$tmp"
  [ $r = 0 ] || echo "entrega/ desatualizada: rode ./dev/montar_entrega.sh"
  exit $r
fi
monta entrega
echo "entrega/ montada: $(ls entrega | tr '\n' ' ')"
