#!/usr/bin/env python3
"""Mede cada um dos 5 índices do sql/05_indices.sql: tempo SEM e COM o índice, com o cache frio.

Uso (da pasta do projeto):  python3 medicoes/medir_indices.py [--execucoes 10]

Método (pedido do professor na consultoria 2):
  * Antes de CADA execução o PostgreSQL é reiniciado ("matar o processo"), para o cache do SGBD
    (shared_buffers) começar vazio e a medição não ler tudo da memória.
  * Cada operação roda N vezes (padrão 10); calculamos a média e o desvio padrão.
  * O tempo é o "Execution Time" do EXPLAIN ANALYZE (tempo gasto dentro do servidor).
  * Linha de base: todas as operações sem nenhum dos 5 índices. Depois, cada índice é criado SOZINHO,
    roda-se ANALYZE, medem-se as operações que ele deve acelerar, e o índice é apagado.
  * Escritas (inserções) são medidas dentro de BEGIN ... ROLLBACK, para os dados não mudarem.
  * Limite: o cache de arquivos do sistema operacional não é limpo (no macOS isso exige "sudo purge";
    no Linux, "echo 3 > /proc/sys/vm/drop_caches" como root). Reiniciar o PostgreSQL limpa só o cache dele.

O script sobe um PostgreSQL DESCARTÁVEL (pasta temporária, só 127.0.0.1), roda 01 a 04, mede e apaga tudo.
Saídas: medicoes/tempos.csv (todas as execuções) e medicoes/grafico_indices.svg (antes/depois).
Só usa a biblioteca padrão do Python.
"""
import argparse
import csv
import glob
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Operações medidas. As consultas usam filtros (predicados): sem predicado, índice não ajuda.
# {streamer} é trocado pelo dono do canal 19 (descoberto no banco).
OPERACOES = {
    'Inserir 100 Super Chats': ("SELECT inserir_doacao_plataforma(c.id_comentario, 5, 'recebido') "
                                "FROM (SELECT id_comentario FROM comentario ORDER BY id_comentario LIMIT 100) c", True),
    'Inserir 100 comentários': ("SELECT inserir_comentario(v.id_video, 1, 'teste', now()::timestamp, true) "
                                "FROM (SELECT id_video FROM video ORDER BY id_video LIMIT 100) v", True),
    'Q2 filtro canal':    ('SELECT * FROM consulta2_videos_mais_comentados(19)', False),
    'Q3 filtro streamer': ('SELECT * FROM consulta3_canais_mais_interacoes({streamer})', False),
    'Q6 filtro usuário':  ('SELECT * FROM consulta6_membros_por_usuario(792)', False),
    'Q7 filtro canal':    ('SELECT * FROM consulta7_canais_com_doacoes(19)', False),
}

# Para cada índice do 05_indices.sql, as operações que motivaram a escolha (e, no I1, o custo extra
# que ele traz para a inserção de comentários).
OPERACOES_DO_INDICE = {
    'idx_comentario_usuario':  ['Inserir 100 Super Chats', 'Inserir 100 comentários'],
    'idx_mv_interacoes_canal': ['Q2 filtro canal', 'Q3 filtro streamer'],
    'idx_inscricao_usuario':   ['Q6 filtro usuário'],
    'idx_mv_doacoes_canal':    ['Q7 filtro canal'],
    'idx_canal_streamer':      ['Q3 filtro streamer'],
}


def achar_pgbin():
    initdb = shutil.which('initdb')
    if initdb:
        return os.path.dirname(initdb)
    candidatos = sorted(glob.glob('/Library/PostgreSQL/*/bin') + glob.glob('/opt/homebrew/opt/postgresql*/bin'))
    for c in reversed(candidatos):
        if os.path.exists(os.path.join(c, 'initdb')):
            return c
    sys.exit('initdb não encontrado. Instale o PostgreSQL e rode de novo.')


class Banco:
    def __init__(self, pgbin, pasta):
        self.pgbin, self.dados = pgbin, os.path.join(pasta, 'dados')
        self.log = os.path.join(pasta, 'pg.log')
        self.porta = str(50000 + os.getpid() % 10000)

    def _rodar(self, *args, entrada=None):
        r = subprocess.run(args, input=entrada, capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f'falhou: {" ".join(args[:3])}...\n{r.stdout}\n{r.stderr}')
        return r.stdout

    def criar(self):
        self._rodar(f'{self.pgbin}/initdb', '-D', self.dados, '-U', 'postgres', '--auth=trust',
                    '-E', 'UTF8', '--locale=C')
        self.ligar()
        self._rodar(f'{self.pgbin}/createdb', '-h', '127.0.0.1', '-p', self.porta, '-U', 'postgres', 'streaming')

    def ligar(self):
        # -k '': sem socket Unix (o caminho temporário pode ser longo demais); só TCP em 127.0.0.1.
        self._rodar(f'{self.pgbin}/pg_ctl', '-D', self.dados, '-l', self.log, '-w', 'start',
                    '-o', f"-p {self.porta} -k '' -c listen_addresses=127.0.0.1")

    def reiniciar(self):
        # "Matar o processo": o PostgreSQL sobe de novo com o cache (shared_buffers) vazio.
        self._rodar(f'{self.pgbin}/pg_ctl', '-D', self.dados, '-m', 'fast', '-w', 'stop')
        self.ligar()

    def desligar(self):
        subprocess.run([f'{self.pgbin}/pg_ctl', '-D', self.dados, '-m', 'immediate', 'stop'], capture_output=True)

    def psql(self, sql=None, arquivo=None):
        args = [f'{self.pgbin}/psql', '-h', '127.0.0.1', '-p', self.porta, '-U', 'postgres', '-d', 'streaming',
                '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1']
        args += ['-f', arquivo] if arquivo else []
        return self._rodar(*args, entrada=sql)


def medir_uma_vez(banco, sql, escrita):
    banco.reiniciar()
    explain = f'EXPLAIN (ANALYZE, FORMAT JSON) {sql};'
    saida = banco.psql(f'BEGIN;\n{explain}\nROLLBACK;\n' if escrita else explain + '\n')
    return json.loads(saida[saida.index('['):saida.rindex(']') + 1])[0]['Execution Time']


def medir(banco, nome, sql, escrita, n, cenario, linhas):
    tempos = [medir_uma_vez(banco, sql, escrita) for _ in range(n)]
    for i, t in enumerate(tempos, 1):
        linhas.append({'cenario': cenario, 'operacao': nome, 'execucao': i, 'ms': round(t, 3)})
    media, desvio = statistics.mean(tempos), statistics.stdev(tempos)
    print(f'  {cenario:<26} {nome:<26} média {media:9.3f} ms   desvio {desvio:8.3f} ms', flush=True)
    return media, desvio


def indices_do_05():
    texto = open(os.path.join(RAIZ, 'sql', '05_indices.sql'), encoding='utf-8').read()
    return {nome: comando for comando, nome in re.findall(r'^(CREATE INDEX (\w+) .*?;)', texto, re.M)}


def fmt(x):
    return (f'{x:.1f}' if x >= 10 else f'{x:.2f}').replace('.', ',')  # vírgula decimal (pt-BR)


def grafico_svg(paineis, caminho):
    """Pequenos múltiplos: um painel por (índice, operação), barras sem/com índice e desvio padrão.
    Cada painel tem a própria escala, porque os tempos vão de frações de ms a dezenas de ms."""
    cor_sem, cor_com = '#2a78d6', '#eb6834'
    larg, alt, colunas = 250, 230, 4
    linhas_grade = (len(paineis) + colunas - 1) // colunas
    W, H = colunas * larg + 20, linhas_grade * alt + 110
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
         'font-family="Helvetica, Arial, sans-serif">',
         f'<rect width="{W}" height="{H}" fill="#fcfcfb"/>',
         '<text x="20" y="30" font-size="17" font-weight="bold" fill="#0b0b0b">'
         'Tempo médio antes e depois de cada índice (cache frio)</text>',
         '<text x="20" y="50" font-size="12" fill="#52514e">Média de 10 execuções, PostgreSQL reiniciado antes '
         'de cada uma; o traço é ± 1 desvio padrão. Cada painel tem a própria escala.</text>',
         f'<rect x="20" y="64" width="12" height="12" rx="2" fill="{cor_sem}"/>'
         '<text x="38" y="75" font-size="12" fill="#0b0b0b">sem o índice</text>',
         f'<rect x="130" y="64" width="12" height="12" rx="2" fill="{cor_com}"/>'
         '<text x="148" y="75" font-size="12" fill="#0b0b0b">com o índice</text>']
    for k, p in enumerate(paineis):
        x0 = 20 + (k % colunas) * larg
        y0 = 95 + (k // colunas) * alt
        topo = max(p['sem'][0] + p['sem'][1], p['com'][0] + p['com'][1]) * 1.15
        base_y, alt_plot = y0 + 175, 125
        ganho = p['sem'][0] / p['com'][0]
        s.append(f'<text x="{x0}" y="{y0 + 14}" font-size="12" font-weight="bold" fill="#0b0b0b">{p["indice"]}</text>')
        s.append(f'<text x="{x0}" y="{y0 + 30}" font-size="12" fill="#52514e">{p["operacao"]} · '
                 f'{fmt(ganho)}x</text>')
        s.append(f'<line x1="{x0}" y1="{base_y}" x2="{x0 + 200}" y2="{base_y}" stroke="#c9c8c2"/>')
        for j, (rot, (media, desvio), cor) in enumerate([('sem', p['sem'], cor_sem), ('com', p['com'], cor_com)]):
            bx = x0 + 35 + j * 90
            h = alt_plot * media / topo
            s.append(f'<path d="M{bx},{base_y} v{-h + 4} q0,-4 4,-4 h42 q4,0 4,4 v{h - 4} z" fill="{cor}"/>')
            yt, yb = base_y - alt_plot * (media + desvio) / topo, base_y - alt_plot * max(media - desvio, 0) / topo
            s.append(f'<line x1="{bx + 25}" y1="{yt}" x2="{bx + 25}" y2="{yb}" stroke="#0b0b0b" stroke-width="1.5"/>')
            s.append(f'<line x1="{bx + 19}" y1="{yt}" x2="{bx + 31}" y2="{yt}" stroke="#0b0b0b" stroke-width="1.5"/>')
            s.append(f'<text x="{bx + 25}" y="{yt - 5}" font-size="11" text-anchor="middle" fill="#0b0b0b">'
                     f'{fmt(media)} ms</text>')
            s.append(f'<text x="{bx + 25}" y="{base_y + 15}" font-size="11" text-anchor="middle" '
                     f'fill="#52514e">{rot}</text>')
    s.append('</svg>')
    with open(caminho, 'w', encoding='utf-8') as f:
        f.write('\n'.join(s))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--execucoes', type=int, default=10)
    n = ap.parse_args().execucoes
    if n < 2:
        sys.exit('--execucoes precisa ser pelo menos 2 (para o desvio padrão).')

    indices = indices_do_05()
    assert set(indices) == set(OPERACOES_DO_INDICE), f'índices do 05 mudaram: {sorted(indices)}'
    pasta = tempfile.mkdtemp(prefix='bd2med.', dir='/tmp')
    banco = Banco(achar_pgbin(), pasta)
    try:
        print('Subindo um PostgreSQL temporário e carregando 01 a 04 (sem o 05)...', flush=True)
        banco.criar()
        for arq in ['01_ddl.sql', '02_ddl_estendida.sql', '03_povoamento.sql', '04_consultas.sql']:
            banco.psql(arquivo=os.path.join(RAIZ, 'sql', arq))
        streamer = banco.psql('SELECT nro_streamer FROM canal WHERE id_canal = 19;').strip()
        ops = {nome: (sql.format(streamer=streamer), esc) for nome, (sql, esc) in OPERACOES.items()}

        linhas, base = [], {}
        print(f'Linha de base (sem índice), {n} execuções por operação:', flush=True)
        for nome, (sql, esc) in ops.items():
            base[nome] = medir(banco, nome, sql, esc, n, 'sem índice', linhas)

        paineis = []
        for idx, nomes in OPERACOES_DO_INDICE.items():
            banco.psql(indices[idx] + '\nANALYZE;\n')
            for nome in nomes:
                com = medir(banco, nome, *ops[nome], n, idx, linhas)
                paineis.append({'indice': idx, 'operacao': nome, 'sem': base[nome], 'com': com})
            banco.psql(f'DROP INDEX {idx};\nANALYZE;\n')
    finally:
        banco.desligar()
        shutil.rmtree(pasta, ignore_errors=True)

    with open(os.path.join(RAIZ, 'medicoes', 'tempos.csv'), 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=['cenario', 'operacao', 'execucao', 'ms'])
        w.writeheader()
        w.writerows(linhas)
    grafico_svg(paineis, os.path.join(RAIZ, 'medicoes', 'grafico_indices.svg'))

    print('\n| Índice | Operação | Sem índice (ms) | Com índice (ms) | Ganho |')
    print('|---|---|---|---|---|')
    for p in paineis:
        (ms, ds), (mc, dc) = p['sem'], p['com']
        print(f'| `{p["indice"]}` | {p["operacao"]} | {fmt(ms)} ± {fmt(ds)} | {fmt(mc)} ± {fmt(dc)} | {fmt(ms / mc)}x |')
    print('\nGravados: medicoes/tempos.csv e medicoes/grafico_indices.svg')


if __name__ == '__main__':
    main()
