#!/usr/bin/env python3
"""Gera sql/03_povoamento.sql com dados de aparência real, usando a biblioteca Faker.

Uso (só precisa de Python 3 e do pacote faker; o .sql gerado NÃO depende de Python):

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install faker
    /tmp/venv/bin/python dev/gerar_povoamento.py            # reescreve sql/03_povoamento.sql

A semente é fixa: com a mesma versão do Faker, a saída é sempre idêntica. Com outra versão do Faker os
nomes podem mudar; por isso o sql/03_povoamento.sql gerado é o que vale para a entrega.

O que torna os dados "orgânicos" (resumo; o detalhe está no cabeçalho do .sql gerado):
  * dados de referência reais: plataformas, países, DDIs, moedas e fatores de conversão aproximados;
  * nomes, nicks, e-mails, telefones, endereços e identificadores nacionais por país (Faker);
  * fama em cauda longa (poucos canais com muito público e muita receita, e a maioria pequena);
  * vídeos com horários de pico, durações por tipo (live, vídeo editado, short) e views coerentes com o canal;
  * comentários no idioma do canal, ao vivo durante a transmissão e offline nos dias seguintes;
  * doações na moeda de quem doou, em valores "redondos", e forma de pagamento coerente com o país.

Limites do enunciado que obrigam a certas escolhas (cada tabela tem de 1.000 a 10.000 tuplas):
  * pais, conversao e plataforma têm um núcleo real e uma cauda FICTÍCIA para chegar a 1.000 linhas;
  * bitcoin, paypal, cartao_credito e mecanismo_plat têm pelo menos 1.000 linhas cada, o que força
    um número alto de doações em relação ao de comentários.
"""
import bisect
import hashlib
import math
import random
import re
import string
import sys
import unicodedata
from datetime import date, datetime, timedelta
from pathlib import Path

import faker as faker_pkg
from faker import Faker

SEMENTE = 2026
HOJE = date(2026, 11, 14)          # "agora" do conjunto de dados
FIM_VIDEOS = date(2026, 10, 31)    # nenhum vídeo é postado depois disso
SAIDA = Path(__file__).resolve().parent.parent / "sql" / "03_povoamento.sql"

# ---- volumes (todos entre 1.000 e 10.000, exigência do enunciado) ----
N_MOEDAS = 1000
N_PAISES = 1000
N_PLATAFORMAS = 1000
N_STREAMERS = 1300
N_VIEWERS = 4700
N_CANAIS = 3000
N_CANAIS_COM_NIVEIS = 1980          # só os canais "parceiros" têm programa de membros (5 níveis cada)
N_INSCRICOES = 8000
N_PATROCINIOS = 1800
N_SPONSORS = 1500
N_VIDEOS = 9500
N_PARTICIPA = 3000
N_COMENTARIOS = 9800
QUOTA_DOACOES = {"plataforma": 2128, "cartao": 1456, "paypal": 1008, "bitcoin": 1008}
N_DOACOES = sum(QUOTA_DOACOES.values())

rng = random.Random(SEMENTE)
Faker.seed(SEMENTE)
_fakers = {}


def fk(locale):
    if locale not in _fakers:
        try:
            _fakers[locale] = Faker(locale)
        except Exception:
            _fakers[locale] = Faker("en_US")
    return _fakers[locale]


# =====================================================================
# Utilidades
# =====================================================================
class Amostrador:
    """Sorteio ponderado em O(log n) (random.choices recalcula as somas a cada chamada)."""

    def __init__(self, itens, pesos):
        self.itens = list(itens)
        self.cum = []
        acc = 0.0
        for p in pesos:
            acc += max(p, 0.0)
            self.cum.append(acc)
        self.total = acc

    def __len__(self):
        return len(self.itens)

    def sorteia(self):
        i = bisect.bisect_right(self.cum, rng.random() * self.total)
        return self.itens[min(i, len(self.itens) - 1)]


def sem_acento(s):
    return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode("ascii")


def slug(s):
    return "".join(c for c in sem_acento(s).lower() if c.isalnum())


def lit(v):
    """Valor Python -> literal SQL."""
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, datetime):
        return "'" + v.strftime("%Y-%m-%d %H:%M:%S") + "'"
    if isinstance(v, date):
        return "'" + v.isoformat() + "'"
    return "'" + str(v).replace("'", "''").replace("\n", " ").replace("\r", " ") + "'"


def pesos_pareto(n, alfa, minimo=1.0):
    return [minimo / (max(rng.random(), 0.0004) ** (1.0 / alfa)) for _ in range(n)]


def luhn_completa(prefixo, tamanho):
    """Completa um número de cartão com dígitos aleatórios e o dígito verificador de Luhn."""
    corpo = prefixo + "".join(str(rng.randrange(10)) for _ in range(tamanho - len(prefixo) - 1))
    soma = 0
    for i, d in enumerate(reversed(corpo)):
        n = int(d)
        if i % 2 == 0:
            n *= 2
            if n > 9:
                n -= 9
        soma += n
    return corpo + str((10 - soma % 10) % 10)


# =====================================================================
# Dados de referência reais
# =====================================================================
# (código, nome, fator para USD). Fatores aproximados: o enunciado só pede um fator por moeda.
MOEDAS_REAIS = [
    ("USD", "Dólar americano", 1.0), ("EUR", "Euro", 1.08), ("BRL", "Real brasileiro", 0.18),
    ("GBP", "Libra esterlina", 1.27), ("JPY", "Iene japonês", 0.0067), ("MXN", "Peso mexicano", 0.052),
    ("ARS", "Peso argentino", 0.001), ("CLP", "Peso chileno", 0.00105), ("COP", "Peso colombiano", 0.00024),
    ("PEN", "Sol peruano", 0.27), ("UYU", "Peso uruguaio", 0.025), ("PLN", "Zloty polonês", 0.25),
    ("SEK", "Coroa sueca", 0.095), ("NOK", "Coroa norueguesa", 0.093), ("DKK", "Coroa dinamarquesa", 0.145),
    ("CZK", "Coroa tcheca", 0.043), ("HUF", "Florim húngaro", 0.0027), ("TRY", "Lira turca", 0.029),
    ("RON", "Leu romeno", 0.217), ("KRW", "Won sul-coreano", 0.00073), ("INR", "Rupia indiana", 0.012),
    ("IDR", "Rupia indonésia", 0.000062), ("PHP", "Peso filipino", 0.017), ("THB", "Baht tailandês", 0.028),
    ("VND", "Dong vietnamita", 0.00004), ("RUB", "Rublo russo", 0.011), ("UAH", "Hryvnia ucraniana", 0.024),
    ("AUD", "Dólar australiano", 0.65), ("NZD", "Dólar neozelandês", 0.60), ("ZAR", "Rand sul-africano", 0.055),
    ("EGP", "Libra egípcia", 0.02), ("AED", "Dirham dos Emirados", 0.272), ("SAR", "Rial saudita", 0.267),
    ("ILS", "Novo xéquel israelense", 0.27), ("CHF", "Franco suíço", 1.12), ("CAD", "Dólar canadense", 0.73),
    ("CNY", "Yuan chinês", 0.14), ("SGD", "Dólar de Singapura", 0.75), ("MYR", "Ringgit malaio", 0.21),
    ("HKD", "Dólar de Hong Kong", 0.128), ("NGN", "Naira nigeriana", 0.00065), ("KES", "Xelim queniano", 0.0077),
    ("CRC", "Colón costa-riquenho", 0.0019), ("BOB", "Boliviano", 0.145), ("PYG", "Guarani paraguaio", 0.00013),
    ("MAD", "Dirham marroquino", 0.10), ("GTQ", "Quetzal guatemalteco", 0.13), ("AOA", "Kwanza angolano", 0.0011),
]

# (ddi, nome, moeda, locale do Faker, idioma, peso de usuários)
# idioma: pt, en, es, de, fr, ja têm textos próprios; os demais países usam "en" (inglês é a língua franca do chat).
PAISES_REAIS = [
    (55, "Brasil", "BRL", "pt_BR", "pt", 28), (1, "Estados Unidos", "USD", "en_US", "en", 22),
    (351, "Portugal", "EUR", "pt_PT", "pt", 2.2), (44, "Reino Unido", "GBP", "en_GB", "en", 4.5),
    (49, "Alemanha", "EUR", "de_DE", "de", 3.5), (33, "França", "EUR", "fr_FR", "fr", 3.5),
    (34, "Espanha", "EUR", "es_ES", "es", 3.8), (52, "México", "MXN", "es_MX", "es", 4.8),
    (54, "Argentina", "ARS", "es_AR", "es", 2.6), (56, "Chile", "CLP", "es_CL", "es", 1.5),
    (57, "Colômbia", "COP", "es_CO", "es", 1.8), (51, "Peru", "PEN", "es_MX", "es", 1.0),
    (598, "Uruguai", "UYU", "es_AR", "es", 0.5), (39, "Itália", "EUR", "it_IT", "en", 2.2),
    (31, "Países Baixos", "EUR", "nl_NL", "en", 1.2), (48, "Polônia", "PLN", "pl_PL", "en", 1.8),
    (46, "Suécia", "SEK", "sv_SE", "en", 0.9), (47, "Noruega", "NOK", "no_NO", "en", 0.6),
    (45, "Dinamarca", "DKK", "da_DK", "en", 0.6), (420, "Tchéquia", "CZK", "cs_CZ", "en", 0.7),
    (36, "Hungria", "HUF", "hu_HU", "en", 0.5), (90, "Turquia", "TRY", "tr_TR", "en", 2.0),
    (40, "Romênia", "RON", "ro_RO", "en", 0.8), (81, "Japão", "JPY", "ja_JP", "ja", 2.4),
    (82, "Coreia do Sul", "KRW", "ko_KR", "en", 1.6), (91, "Índia", "INR", "en_IN", "en", 2.8),
    (62, "Indonésia", "IDR", "id_ID", "en", 1.6), (63, "Filipinas", "PHP", "en_PH", "en", 1.4),
    (66, "Tailândia", "THB", "th_TH", "en", 0.9), (84, "Vietnã", "VND", "vi_VN", "en", 0.9),
    (7, "Rússia", "RUB", "ru_RU", "en", 1.2), (380, "Ucrânia", "UAH", "uk_UA", "en", 0.6),
    (61, "Austrália", "AUD", "en_AU", "en", 1.6), (64, "Nova Zelândia", "NZD", "en_NZ", "en", 0.4),
    (27, "África do Sul", "ZAR", "en_US", "en", 0.7), (20, "Egito", "EGP", "ar_EG", "en", 0.5),
    (971, "Emirados Árabes Unidos", "AED", "ar_AE", "en", 0.5), (966, "Arábia Saudita", "SAR", "ar_SA", "en", 0.6),
    (972, "Israel", "ILS", "he_IL", "en", 0.4), (41, "Suíça", "CHF", "de_CH", "de", 0.6),
    (43, "Áustria", "EUR", "de_AT", "de", 0.5), (32, "Bélgica", "EUR", "nl_BE", "fr", 0.6),
    (353, "Irlanda", "EUR", "en_IE", "en", 0.5), (30, "Grécia", "EUR", "el_GR", "en", 0.4),
    (86, "China", "CNY", "zh_CN", "en", 0.5), (65, "Singapura", "SGD", "en_GB", "en", 0.3),
    (60, "Malásia", "MYR", "en_GB", "en", 0.4), (234, "Nigéria", "NGN", "en_GB", "en", 0.3),
    (254, "Quênia", "KES", "en_GB", "en", 0.2), (506, "Costa Rica", "CRC", "es_MX", "es", 0.3),
    (591, "Bolívia", "BOB", "es_MX", "es", 0.3), (595, "Paraguai", "PYG", "es_MX", "es", 0.3),
    (212, "Marrocos", "MAD", "fr_FR", "fr", 0.3), (502, "Guatemala", "GTQ", "es_MX", "es", 0.2),
    (244, "Angola", "AOA", "pt_PT", "pt", 0.3), (852, "Hong Kong", "HKD", "en_GB", "en", 0.3),
]
LOCALES_NAO_LATINOS = {"ru_RU", "uk_UA", "ko_KR", "zh_CN", "ar_EG", "ar_AE", "ar_SA", "he_IL", "th_TH", "el_GR"}

SUFIXO_LEGAL = {
    55: ["Ltda.", "S.A."], 1: ["Inc.", "LLC", "Corp."], 44: ["Ltd", "PLC"], 49: ["GmbH", "AG"],
    33: ["SAS", "SARL"], 34: ["S.L.", "S.A."], 39: ["S.r.l.", "S.p.A."], 351: ["Lda.", "S.A."],
    52: ["S.A. de C.V."], 54: ["S.A.", "S.R.L."], 81: ["Co., Ltd.", "K.K."], 31: ["B.V."],
}

# ---- plataformas reais: (nome, data de fundação, empresa fundadora, empresa responsável, país da sede) ----
PLATAFORMAS_REAIS = [
    ("YouTube", date(2005, 2, 14), ("YouTube, Inc.", "YouTube", 1), ("Google LLC", "Google", 1)),
    ("Twitch", date(2011, 6, 6), ("Justin.tv, Inc.", "Justin.tv", 1), ("Twitch Interactive, Inc.", "Twitch", 1)),
    ("Kick", date(2022, 12, 6), ("Kick Streaming Pty Ltd", "Kick", 61), ("Kick Streaming Pty Ltd", "Kick", 61)),
    ("Facebook Gaming", date(2018, 6, 1), ("Facebook, Inc.", "Facebook", 1), ("Meta Platforms, Inc.", "Meta", 1)),
    ("TikTok Live", date(2017, 9, 1), ("ByteDance Ltd.", "ByteDance", 86), ("TikTok Pte. Ltd.", "TikTok", 65)),
]
PESO_PLATAFORMA_REAL = [0.38, 0.28, 0.08, 0.09, 0.09]     # parcela das contas de usuário
PESO_FAMA_PLATAFORMA = [1.0, 1.0, 0.5, 0.5, 0.6]           # multiplicador da audiência dos canais
PARCELA_FICTICIAS = 0.08

JOGOS = [
    ("Fortnite", 9), ("Minecraft", 9), ("Valorant", 8), ("League of Legends", 8), ("Counter-Strike 2", 7),
    ("GTA V (RP)", 7), ("EA Sports FC 25", 5), ("Free Fire", 5), ("Call of Duty: Warzone", 5),
    ("Apex Legends", 4), ("Dota 2", 3), ("Roblox", 4), ("Elden Ring", 4), ("Baldur's Gate 3", 2.5),
    ("Rocket League", 2.5), ("Overwatch 2", 3), ("Genshin Impact", 3), ("World of Warcraft", 2.5),
    ("Terraria", 1.5), ("Stardew Valley", 1.8), ("Hollow Knight", 1.2), ("Resident Evil 4", 1.5),
    ("Hades II", 1), ("Celeste", 0.6), ("Super Mario 64", 0.8), ("Pokémon Scarlet", 1.5), ("Among Us", 1),
    ("The Sims 4", 1.5), ("Rainbow Six Siege", 2), ("Rust", 1.5), ("Escape from Tarkov", 1.5),
    ("Lethal Company", 1.2), ("Dark Souls III", 1.5), ("The Witcher 3", 1.3), ("Cyberpunk 2077", 1.3),
    ("Just Chatting", 8), ("Música ao vivo", 0.8), ("IRL", 1.5),
]

# =====================================================================
# Textos por idioma
# =====================================================================
DIAS = {
    "pt": ["segunda a sexta", "terça, quinta e sábado", "todo fim de semana", "quarta e domingo"],
    "en": ["Mon-Fri", "Tue, Thu & Sat", "weekends", "Wed & Sun"],
    "es": ["lunes a viernes", "martes, jueves y sábado", "fines de semana", "miércoles y domingo"],
    "de": ["Mo-Fr", "Di, Do & Sa", "am Wochenende", "Mi & So"],
    "fr": ["du lundi au vendredi", "mardi, jeudi et samedi", "le week-end", "mercredi et dimanche"],
    "ja": ["平日", "火・木・土", "週末", "水・日"],
}
DESCRICOES = {
    "pt": ["Canal de {g} e muito mais! Lives de {d} às {h}h. Bora pra cima!",
           "Gameplays de {g}, dicas e muita resenha com a comunidade. Vídeo novo toda semana.",
           "Aqui você encontra {g}, bate-papo e os melhores momentos das lives. Inscreva-se!",
           "Streamer de {g} desde {a}. Lives {d} a partir das {h}h. Respeito e diversão acima de tudo.",
           "Zerando jogos e fazendo amigos. Principal jogo: {g}. Contato comercial na aba sobre."],
    "en": ["{g} streams and more! Live {d} at {h}:00. Come hang out!",
           "Gameplay, tips and good vibes with the community. New videos every week. Mostly {g}.",
           "Your home for {g}, chill chat and stream highlights. Hit subscribe!",
           "Streaming {g} since {a}. Live {d} from {h}:00. Be kind, have fun.",
           "Beating games and making friends. Main game: {g}. Business inquiries in the about tab."],
    "es": ["Canal de {g} y mucho más! Directos de {d} a las {h}h. Vamos con todo!",
           "Gameplays de {g}, consejos y charla con la comunidad. Vídeo nuevo cada semana.",
           "Aquí encontrarás {g}, charla y los mejores momentos de los directos. Suscríbete!",
           "Streamer de {g} desde {a}. Directos {d} desde las {h}h. Respeto y diversión ante todo.",
           "Pasándome juegos y haciendo amigos. Juego principal: {g}. Contacto comercial en la pestaña de información."],
    "de": ["{g} Streams und mehr! Live {d} um {h} Uhr. Schau vorbei!",
           "Gameplay, Tipps und gute Laune mit der Community. Jede Woche neue Videos. Meistens {g}.",
           "Dein Kanal für {g}, entspannten Talk und Stream-Highlights. Jetzt abonnieren!",
           "Ich streame {g} seit {a}. Live {d} ab {h} Uhr. Respekt und Spaß stehen an erster Stelle."],
    "fr": ["Chaîne {g} et bien plus ! Lives {d} à {h}h. Venez nombreux !",
           "Gameplays {g}, astuces et bonne humeur avec la communauté. Nouvelle vidéo chaque semaine.",
           "Ici, c'est {g}, discussions et les meilleurs moments des lives. Abonne-toi !",
           "Streamer {g} depuis {a}. Lives {d} dès {h}h. Respect et bonne ambiance avant tout."],
    "ja": ["{g}の配信など！{d}の{h}時から配信しています。気軽に遊びに来てください！",
           "{g}を中心にゲーム実況をしています。毎週動画を投稿中。チャンネル登録お願いします！",
           "{g}のプレイや雑談、配信のハイライトをお届けします。"],
}
NOMES_CANAL = {
    "pt": ["Canal do {n}", "{n} Games", "{n} Plays", "{n} TV", "{n} ao vivo", "{N}"],
    "en": ["{n} Plays", "{n} Gaming", "{n}TV", "{n} Live", "The {n} Show", "{N}"],
    "es": ["Canal de {n}", "{n} Gaming", "{n} Juega", "{n} TV", "{N}"],
    "de": ["{n} Gaming", "{n} Plays", "{n} TV", "{n} Live", "{N}"],
    "fr": ["{n} Gaming", "Chaîne de {n}", "{n} TV", "{n} Live", "{N}"],
    "ja": ["{n}ゲーム実況", "{n} Gaming", "{n}チャンネル", "{N}"],
}
TITULOS = {   # por idioma e tipo de vídeo. {g} jogo, {n} nº do episódio, {h} horas, {m} minutos, {s} segundos
    "pt": {"live": ["ZERANDO {g} (Ao Vivo) #{n}", "LIVE | {g} com os inscritos", "Ranked no {g} | rumo ao topo",
                    "RESPONDENDO O CHAT e jogando {g}", "Jogando {g} até dormir", "{g} mas o chat decide tudo (live #{n})"],
           "vod": ["{g} — Parte {n}", "{g}: primeira vez jogando, e deu nisso", "Os melhores momentos de {g} da semana",
                   "Tentando platinar {g} (dia {n})", "Tudo que você precisa saber sobre {g} em {m} minutos",
                   "Eu joguei {g} por {h} horas seguidas"],
           "short": ["{g} em {s} segundos", "Essa jogada em {g} foi absurda 🔥", "Clipe do dia: {g} #{n}", "{g} #shorts"]},
    "en": {"live": ["Road to Top 500 | {g} Ranked (live #{n})", "First time playing {g} - LIVE blind run",
                    "Chill {g} stream with the community", "{g} but chat controls everything (stream #{n})",
                    "Answering your questions while playing {g}", "Late night {g} grind"],
           "vod": ["{g} - Episode {n}", "Trying not to rage quit {g} | Day {n}", "Best of {g} - Funny Moments",
                   "Full playthrough: {g} (Part {n})", "I played {g} for {h} hours straight",
                   "Everything you need to know about {g} in {m} minutes"],
           "short": ["{g} clip in {s} seconds", "This {g} play was insane 🔥", "{g} moment of the day #{n}", "{g} #shorts"]},
    "es": {"live": ["Jugando {g} con suscriptores (en directo)", "Rankeds de {g} hasta llegar a Diamante | DIRECTO",
                    "{g} pero el chat decide todo (directo #{n})", "Respondiendo al chat mientras juego {g}"],
           "vod": ["{g} - Capítulo {n}", "Primera vez en {g} 😱", "Mejores momentos de {g}",
                   "Intentando no rendirme en {g} (día {n})", "Jugué {g} durante {h} horas seguidas"],
           "short": ["{g} en {s} segundos", "Esta jugada de {g} fue una locura 🔥", "Clip del día: {g} #{n}"]},
    "de": {"live": ["Ranked Grind in {g} | Live auf Deutsch", "{g} mit dem Chat (Stream #{n})", "Late-Night-Stream: {g}"],
           "vod": ["{g} - Folge {n}", "Erstes Mal {g} (Blind Let's Play)", "Die besten Momente aus {g}",
                   "Ich zocke {g} {h} Stunden am Stück"],
           "short": ["{g} Clip in {s} Sekunden", "Dieser Play in {g} war krank 🔥", "{g} Moment des Tages #{n}"]},
    "fr": {"live": ["Ranked sur {g} | on monte ! (live #{n})", "{g} avec le chat (stream #{n})", "Live {g} : on discute et on joue"],
           "vod": ["{g} - Épisode {n}", "Première fois sur {g}", "Meilleurs moments {g}", "Je teste {g} pendant {h} heures"],
           "short": ["{g} en {s} secondes", "Ce play sur {g} était fou 🔥", "Clip du jour {g} #{n}"]},
    "ja": {"live": ["【{g}】ランクマッチ配信 #{n}", "【初見】{g}やってみる！(生配信)", "{g}をみんなでワイワイ遊ぶ配信 #{n}"],
           "vod": ["【{g}】実況プレイ #{n}", "【{g}】神プレイ集", "{g}を{h}時間ぶっ通しで遊んでみた"],
           "short": ["{g} {s}秒でわかる", "{g}のスーパープレイ🔥", "今日の{g}ハイライト #{n}"]},
}
TITULOS_CHAT = {   # categorias de conversa (Just Chatting, IRL): só fazem sentido ao vivo
    "pt": ["Bate-papo e reagindo a clipes #{n}", "Resenha com o chat | perguntas e respostas #{n}", "Conversa de domingo #{n}"],
    "en": ["Just chatting and reacting to clips #{n}", "Q&A with chat #{n}", "Sunday hangout #{n}"],
    "es": ["Charla y reaccionando a clips #{n}", "Preguntas y respuestas con el chat #{n}", "Charla del domingo #{n}"],
    "de": ["Quatschen und Clips schauen #{n}", "Fragen und Antworten mit dem Chat #{n}"],
    "fr": ["Discussion et réactions aux clips #{n}", "Questions-réponses avec le chat #{n}"],
    "ja": ["雑談配信 #{n}", "質問に答える雑談 #{n}"],
}
CHAT_LIVE = {
    "pt": ["boa noite {s}!", "salve salve chat", "primeiro!", "kkkkkkkk", "que jogada foi essa??", "GG",
           "chat tá on fogo hoje", "alguém me explica o que aconteceu kkk", "tô chegando agora, o que perdi?",
           "joga {g} amanhã também?", "mandou bem demais", "que lag do capeta", "clipa isso!!",
           "pior que eu faria igual kkk", "boa sorte nessa partida!", "o som tá baixo pra mim",
           "já vou dormir, mas valeu pela live!", "{s} é muito bom, disse"],
    "en": ["gg", "first!", "hello chat", "lets gooo", "that play was insane", "LOL",
           "can someone explain what just happened", "just got here, what did I miss?", "{s} you're cracked",
           "play {g} tomorrow too!", "clip that!!", "chat is going crazy tonight", "that lag tho",
           "no way he did that", "good luck this round", "sound is too low for me", "W stream",
           "gotta sleep, thanks for the stream!"],
    "es": ["buenas noches {s}!", "primero!", "jajajaja", "qué jugada fue esa??", "GG", "el chat está on fire hoy",
           "alguien me explica qué pasó jaja", "acabo de llegar, qué me perdí?", "juega {g} mañana también?",
           "lo hiciste genial", "qué lag más feo", "clipea eso!!", "mucha suerte en esta partida!",
           "el sonido está muy bajito", "ya me voy a dormir, gracias por el directo!"],
    "de": ["Moin {s}!", "erster!", "hahaha", "was war das für ein Play??", "GG", "Chat ist heute wieder wild",
           "kann mir jemand erklären was passiert ist?", "bin gerade erst gekommen, was habe ich verpasst?",
           "spielst du morgen wieder {g}?", "stark gespielt!", "der Lag ist heftig", "clip das!!",
           "viel Glück bei der Runde!", "Ton ist zu leise", "ich geh pennen, danke für den Stream!"],
    "fr": ["salut {s} !", "premier !", "mdrrr", "c'était quoi ce play ??", "GG", "le chat est en feu ce soir",
           "quelqu'un peut m'expliquer ce qui s'est passé ?", "j'arrive, j'ai raté quoi ?",
           "tu rejoues à {g} demain ?", "trop fort !", "ça lag à mort", "clippez ça !!",
           "bonne chance pour cette partie !", "le son est trop bas", "je vais dormir, merci pour le live !"],
    "ja": ["こんばんは！", "初見です", "草", "888888", "うますぎる", "今のプレイやばくない？",
           "{g}また明日もやってほしい", "ナイスー！", "ラグすぎて草", "クリップ撮った！", "お疲れ様でした！",
           "音が小さいです", "wwwww", "神プレイ", "ドンマイ！", "配信ありがとう！"],
}
CHAT_VOD = {
    "pt": ["Muito boa a edição! Já maratonei o canal todo", "Vim pelo recomendado e fiquei, parabéns pelo conteúdo",
           "Esse vídeo merecia mais views", "Quem mais está assistindo em 2026?", "A parte do minuto 12 me quebrou kkkkk",
           "Tutorial salvou minha vida, obrigado!", "Faz uma parte 2 desse vídeo por favor",
           "Melhor canal de {g} do Brasil, sem dúvida", "Já me inscrevi e ativei o sininho 🔔",
           "Toda vez que vejo isso dou risada", "O áudio ficou perfeito dessa vez",
           "Não concordo com o final mas o vídeo é excelente", "Assisti 3 vezes e ainda descubro coisa nova",
           "Pode fazer um vídeo sobre {g} com os inscritos?", "Primeira vez aqui e já virei fã"],
    "en": ["Great editing! Binged the whole channel", "Came from recommended and stayed, great content",
           "This video deserves way more views", "Who's watching in 2026?", "The part at 12:00 killed me lol",
           "This tutorial saved my run, thank you!", "Please make a part 2", "Best {g} channel out there, fight me",
           "Subscribed and hit the bell 🔔", "Every time I rewatch this I laugh", "Audio is so much better this time",
           "Disagree with the ending but the video is excellent", "Watched it 3 times and still catching new things",
           "Can you do a video on {g} with the community?", "First time here and already a fan"],
    "es": ["Muy buena la edición! Me maratoneé todo el canal", "Llegué por recomendado y me quedé, felicidades",
           "Este vídeo merece muchas más visitas", "Quién más lo ve en 2026?", "La parte del minuto 12 me mató jajaja",
           "El tutorial me salvó, gracias!", "Haz una parte 2 por favor", "El mejor canal de {g}, sin duda",
           "Ya me suscribí y activé la campanita 🔔", "Cada vez que lo veo me río",
           "No estoy de acuerdo con el final pero el vídeo es excelente", "Primera vez aquí y ya soy fan"],
    "de": ["Sehr gut geschnitten! Habe den ganzen Kanal durchgeschaut", "Über die Empfehlung gekommen und geblieben",
           "Das Video verdient viel mehr Aufrufe", "Wer schaut das 2026 noch?", "Die Stelle bei 12:00 hat mich zerstört",
           "Das Tutorial hat mir echt geholfen, danke!", "Bitte mach einen zweiten Teil",
           "Bester {g}-Kanal, keine Diskussion", "Abonniert und Glocke aktiviert 🔔", "Zum ersten Mal hier und schon Fan"],
    "fr": ["Super montage ! J'ai regardé toute la chaîne d'un coup", "Venu par recommandation et resté, bravo",
           "Cette vidéo mérite beaucoup plus de vues", "Qui regarde ça en 2026 ?", "Le passage à 12:00 m'a achevé mdr",
           "Ce tuto m'a sauvé, merci !", "Fais une partie 2 s'il te plaît", "La meilleure chaîne {g}, sans hésiter",
           "Abonné et cloche activée 🔔", "Première fois ici et déjà fan"],
    "ja": ["編集めっちゃ上手い！チャンネル全部見ました", "おすすめから来ました、面白かったです", "もっと再生されるべき動画",
           "12分のところで吹いた", "参考になりました、ありがとうございます！", "第2弾お願いします", "チャンネル登録しました🔔",
           "何回見ても笑える", "初めて来ましたがファンになりました"],
}
CHAT_DOACAO = {
    "pt": ["Salve {s}! Esse é pra ajudar no café ☕", "Toma aí pra pipoca da live 🍿", "Parabéns pelo canal, continue assim!",
           "Joga {g} amanhã? Fica o pedido kkk", "Manda um salve pro pessoal aqui de casa!", "Mais um pra você tilitar kkk",
           "Obrigado por alegrar minhas noites", "Aqui vai minha contribuição, vale cada segundo", "Salve pro chat! 🔥",
           "Lê meu nome aí por favor 🙏", "Aniversário do meu irmão, manda um salve?"],
    "en": ["Here's something for coffee ☕", "For the popcorn fund 🍿", "Keep up the great work!",
           "Play {g} tomorrow? Just a suggestion lol", "Shoutout to everyone in the chat!", "Another one to make you tilt lol",
           "Thanks for brightening my evenings", "Worth every second of the stream", "Please read my name 🙏",
           "It's my brother's birthday, could you say hi?", "Love the content {s}! 🔥"],
    "es": ["Para el café ☕", "Para las palomitas del directo 🍿", "Felicidades por el canal, sigue así!",
           "Juegas {g} mañana? Es una sugerencia jaja", "Un saludo para todo el chat!", "Gracias por alegrar mis noches",
           "Aquí va mi aporte, vale cada segundo", "Lee mi nombre por favor 🙏", "Es el cumpleaños de mi hermano, un saludo?"],
    "de": ["Für den Kaffee ☕", "Für die Popcorn-Kasse 🍿", "Weiter so!", "Spielst du morgen {g}? Nur so ein Wunsch",
           "Grüße an den ganzen Chat!", "Danke für die Unterhaltung", "Bitte meinen Namen vorlesen 🙏"],
    "fr": ["Pour le café ☕", "Pour le pop-corn du live 🍿", "Bravo pour la chaîne, continue comme ça !",
           "Tu joues à {g} demain ? Juste une idée", "Salut à tout le chat !", "Merci d'égayer mes soirées",
           "Lis mon pseudo s'il te plaît 🙏"],
    "ja": ["コーヒー代にどうぞ☕", "いつも楽しい配信ありがとう！", "{g}また見たいです！", "名前読んでほしいです🙏",
           "弟の誕生日なので一言お願いします！", "応援してます🔥"],
}
EMOTES_TEXTO = ["KEKW", "LUL", "Kappa", "PogU", "monkaS", "OMEGALUL", "Sadge", "GIGACHAD", "W", "L", "Copium", "EZ"]
EMOTES_EMOJI = ["😂", "🔥", "❤️", "👏", "😮", "🙌", "💀", "🤣", "👍", "😍"]
NOMES_NIVEL = {
    "pt": [["Bronze", "Prata", "Ouro", "Platina", "Diamante"], ["Iniciante", "Fã", "Apoiador", "Veterano", "Lenda"],
           ["Curioso", "Parceiro", "Fiel", "VIP", "Mito"]],
    "en": [["Rookie", "Fan", "Supporter", "Veteran", "Legend"], ["Bronze", "Silver", "Gold", "Platinum", "Diamond"],
           ["Member", "Regular", "Champion", "Elite", "MVP"]],
    "es": [["Novato", "Fan", "Apoyo", "Veterano", "Leyenda"], ["Bronce", "Plata", "Oro", "Platino", "Diamante"]],
    "de": [["Neuling", "Fan", "Unterstützer", "Veteran", "Legende"], ["Bronze", "Silber", "Gold", "Platin", "Diamant"]],
    "fr": [["Débutant", "Fan", "Soutien", "Vétéran", "Légende"], ["Bronze", "Argent", "Or", "Platine", "Diamant"]],
    "ja": [["ブロンズ", "シルバー", "ゴールド", "プラチナ", "ダイヤ"], ["ビギナー", "ファン", "サポーター", "ベテラン", "レジェンド"]],
}
PRECOS_NIVEL = [[0.99, 1.99, 2.99], [3.99, 4.99, 5.99], [7.99, 9.99, 12.99], [19.99, 24.99], [49.99, 99.99]]

GAMER_ADJ = ["dark", "mad", "silent", "lucky", "toxic", "chill", "turbo", "salty", "sneaky", "wild", "royal", "lost", "frozen", "rapid"]
GAMER_SUBST = ["wolf", "ninja", "sniper", "phoenix", "panda", "pixel", "ghost", "dragon", "tank", "shadow", "viking", "samurai",
               "falcon", "raven", "knight", "wizard", "cat", "fox", "bear", "storm", "blade", "hero", "rogue", "noob"]
GAMER_PREF = ["xX", "Mr", "Lord", "The", "Pro", "Sir", "Dr", "Capitao", "El", "Der"]
PREF_MARCA = ["Nova", "Apex", "Pixel", "Vortex", "Quantum", "Turbo", "Hyper", "Nitro", "Aero", "Titan", "Zenith", "Omni", "Blaze",
              "Cyber", "Delta", "Echo", "Flux", "Gamma", "Helix", "Ion", "Jet", "Luma", "Matrix", "Nimbus", "Orbit", "Prime",
              "Quasar", "Rapid", "Sigma", "Terra", "Ultra", "Vega", "Warp", "Xeno", "Zephyr", "Alpha", "Bravo", "Crimson",
              "Dynamo", "Ember", "Falcon", "Granite", "Horizon", "Iron", "Jade", "Karma", "Lynx", "Magma", "Nexus", "Onyx", "Pulse",
              "Radiant", "Solar", "Tango", "Umbra", "Vertex", "Wyvern", "Axiom", "Boreal", "Cobalt", "Drift", "Elara", "Forge",
              "Glacier", "Harbor", "Indigo", "Juno", "Kestrel", "Lumen", "Meridian", "Nova", "Opal", "Pioneer", "Quill",
              "Raven", "Summit", "Tundra", "Unity", "Valor", "Willow", "Xylo", "Yonder", "Zenit"]
SUF_MARCA = ["Tech", "Labs", "Gaming", "Energy", "Peripherals", "Studios", "Systems", "Foods", "Drinks", "Wear", "Mobile",
             "Interactive", "Hardware", "Chairs", "Networks", "Digital", "Games", "Audio", "Cloud", "Sports", "Snacks", "Pay",
             "VPN", "Bank", "Robotics", "Analytics", "Media", "Logistics", "Coffee", "Apparel", "Software", "Security", "Foods Co",
             "Electronics", "Fitness", "Energy Drinks", "Telecom", "Motors", "Home", "Eyewear"]
PLAT_A = ["Stream", "Live", "Cast", "Play", "Tube", "Vibe", "Wave", "Pulse", "Nest", "Hub", "Loop", "Spark", "Pixel", "Orbit",
          "Nova", "Zap", "Glow", "Echo", "Beam", "Flow", "Rift", "Dash", "Volt", "Mint"]
PLAT_B = ["Nest", "TV", "Cast", "Hub", "Live", "Wave", "Box", "Zone", "Lab", "Room", "Tube", "Play", "Net", "Arena", "Spot"]
PLAT_C = ["", "", "", "", "", "", "", "Pro", "Plus", "Go", "X"]     # a maioria sem sufixo
SIL_A = ["Val", "Kar", "Nor", "Zan", "Mor", "Ter", "Bel", "Lun", "Sol", "Ast", "Dor", "Fen", "Gor", "Hal", "Ith", "Jor", "Kel",
         "Lor", "Mir", "Nev", "Ora", "Pol", "Qua", "Ros", "Sil", "Tur", "Ulm", "Ven", "Wes", "Yar", "Zel", "Bra", "Cal", "Dra"]
SIL_B = ["dória", "vânia", "landia", "bia", "tânia", "nésia", "gária", "stão", "nia", "dávia", "ria", "lândia", "mar", "rica",
         "zona", "ndra", "lia", "sia", "vênia", "tenia"]
NOMES_MOEDA = ["Coroa", "Dinar", "Florim", "Peso", "Rupia", "Franco", "Lira", "Real", "Dólar", "Marco", "Escudo", "Rublo"]
DOMINIOS = {
    "pt": [("gmail.com", 60), ("hotmail.com", 12), ("outlook.com", 10), ("yahoo.com.br", 8), ("uol.com.br", 5), ("icloud.com", 5)],
    "en": [("gmail.com", 55), ("yahoo.com", 12), ("outlook.com", 12), ("hotmail.com", 6), ("icloud.com", 8), ("proton.me", 4), ("aol.com", 3)],
    "es": [("gmail.com", 60), ("hotmail.com", 15), ("outlook.com", 10), ("yahoo.es", 10), ("icloud.com", 5)],
    "de": [("gmail.com", 35), ("web.de", 20), ("gmx.de", 20), ("t-online.de", 15), ("outlook.de", 10)],
    "fr": [("gmail.com", 40), ("orange.fr", 20), ("free.fr", 15), ("laposte.net", 10), ("hotmail.fr", 15)],
    "ja": [("gmail.com", 45), ("yahoo.co.jp", 25), ("docomo.ne.jp", 15), ("icloud.com", 15)],
}
DDD_BR = [11, 21, 31, 41, 51, 61, 71, 81, 85, 19, 27, 62, 47, 48, 92, 98]


# =====================================================================
# Referência: moedas, países, empresas, plataformas
# =====================================================================
def gerar_referencia():
    # --- moedas ---
    moedas = list(MOEDAS_REAIS)
    codigos = {m[0] for m in moedas}
    reservados_x = {"XAF", "XAG", "XAU", "XBA", "XBB", "XBC", "XBD", "XCD", "XCG", "XDR", "XOF", "XPD", "XPF", "XPT", "XSU", "XTS", "XUA", "XXX"}
    livres = [a + b + c for a in "QX" for b in string.ascii_uppercase for c in string.ascii_uppercase
              if (a == "X" or b >= "M") and a + b + c not in reservados_x and a + b + c not in codigos]
    rng.shuffle(livres)

    # --- países ---
    paises = [(d, n, m) for d, n, m, *_ in PAISES_REAIS]
    nomes_usados = {slug(n) for _, n, _ in paises}
    ficticios = []
    while len(paises) + len(ficticios) < N_PAISES:
        nome = rng.choice(SIL_A) + rng.choice(["", "", "ra", "li", "no"]) + rng.choice(SIL_B)
        if slug(nome) in nomes_usados:
            continue
        nomes_usados.add(slug(nome))
        ficticios.append(nome)
    ddi_livres = list(range(3001, 3001 + len(ficticios)))
    n_moedas_fict = N_MOEDAS - len(moedas)
    moedas_fict = []
    for i in range(n_moedas_fict):
        pais_nome = ficticios[i % len(ficticios)]
        # fator: log-normal em torno de 0,05 USD, entre ~0,001 e ~10
        fator = round(min(max(rng.lognormvariate(math.log(0.05), 1.5), 0.001), 10.0), 6)
        moedas_fict.append((livres[i], f"{rng.choice(NOMES_MOEDA)} de {pais_nome}", fator, pais_nome))
        # (se houver mais moedas que países, as extras ficam sem país, como moedas fora de circulação)
    moedas += [(c, n, f) for c, n, f, _ in moedas_fict]
    for i, nome in enumerate(ficticios):
        moeda = moedas_fict[i % len(moedas_fict)][0]
        paises.append((ddi_livres[i], nome, moeda))
    assert len(moedas) == N_MOEDAS and len(paises) == N_PAISES, (len(moedas), len(paises))
    return moedas, paises


def nome_marca():
    p, s = rng.choice(PREF_MARCA), rng.choice(SUF_MARCA)
    return p + s if rng.random() < 0.35 else f"{p} {s}"


def sufixo_legal(ddi):
    return rng.choice(SUFIXO_LEGAL.get(ddi, ["Ltd"]))


class Registro:
    def __init__(self, **kw):
        self.__dict__.update(kw)


def gerar_empresas_e_plataformas(paises_reais_amostra):
    """Empresas: 9 reais das plataformas, as das plataformas fictícias e os patrocinadores."""
    empresas = []   # Registro(nome, fantasia, ddi, ids)
    nomes = set()

    def nova(nome, fantasia, ddi):
        base = nome
        k = 2
        while nome.lower() in nomes:
            nome = f"{base} {k}"
            k += 1
        nomes.add(nome.lower())
        empresas.append(Registro(ord=len(empresas) + 1, nome=nome, fantasia=fantasia, ddi=ddi))
        return empresas[-1].ord

    plataformas = []
    pesos_conta = []
    fama = []
    ids_reais = {}
    for nome, fund_data, f, r in PLATAFORMAS_REAIS:
        fo = ids_reais.get(f[0]) or nova(*f)
        ids_reais[f[0]] = fo
        ro = ids_reais.get(r[0]) or nova(*r)
        ids_reais[r[0]] = ro
        plataformas.append(Registro(ord=len(plataformas) + 1, nome=nome, fund=fo, resp=ro, data=fund_data))
    nomes_plat = {p.nome.lower() for p in plataformas}
    n_fict = N_PLATAFORMAS - len(plataformas)
    zipf = [1.0 / (i + 1) ** 1.1 for i in range(n_fict)]
    soma = sum(zipf)
    pesos_conta = PESO_PLATAFORMA_REAL + [PARCELA_FICTICIAS * z / soma for z in zipf]
    fama = PESO_FAMA_PLATAFORMA + [0.1] * n_fict
    while len(plataformas) < N_PLATAFORMAS:
        a, b = rng.choice(PLAT_A), rng.choice(PLAT_B)
        nome = a + b + rng.choice(PLAT_C) if (rng.random() < 0.75 and a != b) else a + ".tv"
        if nome.lower() in nomes_plat:
            continue
        nomes_plat.add(nome.lower())
        ddi = paises_reais_amostra.sorteia()
        fo = nova(f"{nome} {sufixo_legal(ddi)}", nome, ddi)
        ro = fo
        if rng.random() < 0.3:
            ddi2 = paises_reais_amostra.sorteia()
            for _ in range(40):                 # empresa-mãe com nome ainda não usado
                marca = f"{rng.choice(PREF_MARCA)} {rng.choice(['Media Group', 'Holdings', 'Entertainment', 'Digital Group'])}"
                razao = f"{marca} {sufixo_legal(ddi2)}"
                if razao.lower() not in nomes:
                    break
            ro = nova(razao, marca, ddi2)
        ano = min(2025, int(2007 + 18 * rng.betavariate(2, 1.3)))
        plataformas.append(Registro(ord=len(plataformas) + 1, nome=nome, fund=fo, resp=ro,
                                    data=date(ano, rng.randint(1, 12), rng.randint(1, 28))))
    n_fix_empresas = len(empresas)
    patrocinadores = []
    por_ord_emp = {}
    while len(patrocinadores) < N_SPONSORS:
        ddi = paises_reais_amostra.sorteia()
        if rng.random() < 0.3:
            # empresa "tradicional" do país (Faker): a razão social é o nome completo; a fantasia, só o primeiro sobrenome
            razao = fk(next(l for d, _, _, l, *_ in PAISES_REAIS if d == ddi)).company()
            fantasia = re.split(r",| e | and | y | und | et ", razao)[0].strip()
            if not re.search(r"(Ltda\.?|S\.A\.?|Inc\.?|LLC|Ltd|GmbH|AG|SARL|SAS|S\.L\.|S\.r\.l\.|Lda\.?|B\.V\.|Co\.|Group|PLC)$", razao):
                razao = f"{razao} {sufixo_legal(ddi)}"
        elif patrocinadores and rng.random() < 0.04:
            # mesma marca em outro país: razão social diferente, mesmo nome fantasia (o modelo permite)
            fantasia = por_ord_emp[rng.choice(patrocinadores)].fantasia
            razao = f"{fantasia} {rng.choice(['International', 'Latam', 'Europe', 'Americas', 'Asia'])} {sufixo_legal(ddi)}"
        else:
            for _ in range(30):                 # sorteia de novo se a razão social já existir (evita "Ltd 2")
                fantasia = nome_marca()
                razao = f"{fantasia} {sufixo_legal(ddi)}"
                if razao.lower() not in nomes:
                    break
        eo = nova(razao, fantasia[:255], ddi)
        patrocinadores.append(eo)
        por_ord_emp[eo] = empresas[-1]
    return empresas, plataformas, pesos_conta, fama, patrocinadores


def id_nacional(ddi, usados):
    loc = next(l for d, _, _, l, *_ in PAISES_REAIS if d == ddi)
    for _ in range(50):
        f = fk(loc)
        if ddi == 55:
            v = fk("pt_BR").cnpj()
        elif ddi == 1:
            v = fk("en_US").ein()
        elif ddi == 49:
            v = fk("de_DE").vat_id()
        elif ddi == 33:
            v = fk("fr_FR").siret()
        elif ddi == 34:
            v = rng.choice("ABCDEFGHJNPQRSUVW") + f"{rng.randrange(10**7):07d}" + rng.choice("0123456789JABCDEFGHI")  # CIF (o cif() do Faker não obedece à semente)
        elif ddi == 44:
            v = f"{rng.randrange(10**7, 10**8)}"
        elif ddi == 351:
            v = f"5{rng.randrange(10**7, 10**8)}"
        elif ddi == 81:
            v = f"{rng.randrange(10**12, 10**13)}"
        else:
            v = f"{ddi}-{rng.randrange(10**9, 10**10)}"
        if (ddi, v) not in usados:
            usados.add((ddi, v))
            return v
    raise RuntimeError("não consegui um identificador nacional único")


# =====================================================================
# Usuários
# =====================================================================
def nick_para(base_first, base_last, usados):
    a, b = slug(base_first), slug(base_last)
    for _ in range(60):
        r = rng.random()
        yy = rng.choice([str(rng.randrange(70, 100)), str(rng.randrange(0, 12)).zfill(2), str(rng.randrange(1, 9999))])
        if r < 0.20:
            n = f"{a}{b}{yy}"
        elif r < 0.34:
            n = f"{a}_{b}"
        elif r < 0.44:
            n = f"{a}.{b[:1]}{yy}"
        elif r < 0.60:
            n = f"{rng.choice(GAMER_PREF)}{rng.choice(GAMER_ADJ).capitalize()}{rng.choice(GAMER_SUBST).capitalize()}"
            n += yy if rng.random() < 0.6 else ""
        elif r < 0.75:
            n = rng.choice(GAMER_SUBST).capitalize() + rng.choice(GAMER_SUBST).capitalize()
            n += yy if rng.random() < 0.5 else ""
        elif r < 0.87:
            n = f"{a}{rng.choice(['plays', 'gamer', 'tv', 'live', 'oficial', 'yt', 'br'])}"
        else:
            n = f"{rng.choice(GAMER_ADJ)}_{rng.choice(GAMER_SUBST)}_{rng.randrange(1, 999)}"
        n = n.strip("_.")[:30]
        if len(n) >= 4 and n.lower() not in usados:
            usados.add(n.lower())
            return n
    n = f"{a}{b}{rng.randrange(10**4, 10**6)}"[:40]
    usados.add(n.lower())
    return n


def email_para(nick, first, last, lang, ddi, usados):
    dominios = DOMINIOS.get(lang, DOMINIOS["en"])
    dom = Amostrador([d for d, _ in dominios], [p for _, p in dominios]).sorteia()
    if dom == "yahoo.com.br" and ddi != 55:
        dom = "yahoo.com"
    for _ in range(30):
        r = rng.random()
        if r < 0.45:
            local = slug(nick)
        elif r < 0.75:
            local = f"{slug(first)}.{slug(last)}"
        elif r < 0.9:
            local = f"{slug(first)}{slug(last)[:1]}{rng.randrange(1, 99)}"
        else:
            local = f"{slug(first)}{rng.randrange(1970, 2010)}"
        local = (local or "user") + (str(rng.randrange(10, 9999)) if rng.random() < 0.15 else "")
        e = f"{local}@{dom}"
        if e not in usados:
            usados.add(e)
            return e
    e = f"{slug(nick)}{rng.randrange(10**5, 10**7)}@{dom}"
    usados.add(e)
    return e


def telefone_para(ddi):
    if ddi == 55:
        return f"+55 {rng.choice(DDD_BR)} 9{rng.randrange(10**4):04d}-{rng.randrange(10**4):04d}"
    if ddi == 1:
        return f"+1 {rng.randrange(2, 10)}{rng.randrange(100):02d}-{rng.randrange(200, 1000)}-{rng.randrange(10**4):04d}"
    n = rng.choice([9, 9, 9, 10])
    digitos = "".join(str(rng.randrange(10)) for _ in range(n))
    return f"+{ddi} {digitos[:3]} {digitos[3:6]} {digitos[6:]}"


def passaporte_para(ddi, usados):
    L = string.ascii_uppercase
    for _ in range(50):
        if ddi == 55:
            v = "".join(rng.choice(L) for _ in range(2)) + f"{rng.randrange(10**6):06d}"
        elif ddi in (1, 44):
            v = f"{rng.randrange(10**8, 10**9)}"
        elif ddi == 351:
            v = rng.choice(L) + f"{rng.randrange(10**6):06d}"
        elif ddi == 33:
            v = f"{rng.randrange(100):02d}" + "".join(rng.choice(L) for _ in range(2)) + f"{rng.randrange(10**5):05d}"
        elif ddi in (34, 54):
            v = "".join(rng.choice(L) for _ in range(3)) + f"{rng.randrange(10**6):06d}"
        elif ddi == 49:
            v = "C" + "".join(rng.choice("CFGHJKLMNPRTVWXYZ0123456789") for _ in range(8))
        elif ddi == 52:
            v = "G" + f"{rng.randrange(10**8):08d}"
        else:
            v = "".join(rng.choice(L) for _ in range(2)) + f"{rng.randrange(10**7):07d}"
        if (ddi, v) not in usados:
            usados.add((ddi, v))
            return v
    raise RuntimeError("passaporte")


def endereco_para(loc):
    try:
        return fk(loc).address().replace("\n", ", ")[:255]
    except Exception:
        return fk("en_US").address().replace("\n", ", ")[:255]


def gerar_usuarios(paises_amostra, plataformas, pesos_conta):
    info = {d: (m, loc, lang) for d, _, m, loc, lang, _ in PAISES_REAIS}
    flags = [True] * N_STREAMERS + [False] * N_VIEWERS
    rng.shuffle(flags)
    nicks, emails, passaportes = set(), set(), set()
    usuarios = []
    for i, streamer in enumerate(flags, start=1):
        ddi = paises_amostra.sorteia()
        _, loc, lang = info[ddi]
        f = fk(loc)
        base = fk("en_US") if loc in LOCALES_NAO_LATINOS else f
        if loc == "ja_JP" and hasattr(f, "first_romanized_name"):
            first, last = f.first_romanized_name(), f.last_romanized_name()
        else:
            first = base.first_name()
            last = base.last_name()
        if not slug(first) or not slug(last):          # nome sem letras latinas (ex.: kanji): usa nomes em inglês
            first, last = fk("en_US").first_name(), fk("en_US").last_name()
        nick = nick_para(first, last, nicks)
        idade = rng.triangular(18, 55, 26) if streamer else rng.triangular(13, 62, 22)
        nasc = HOJE - timedelta(days=int(idade * 365.25) + rng.randrange(0, 300))
        ddi_pass, pass_nro = None, None
        if streamer:
            ddi_pass = ddi if rng.random() < 0.9 else paises_amostra.sorteia()
            pass_nro = passaporte_para(ddi_pass, passaportes)
        usuarios.append(Registro(
            ord=i, streamer=streamer, nick=nick, first=first, ddi=ddi, lang=lang, loc=loc,
            email=email_para(nick, first, last, lang, ddi, emails),
            nasc=nasc,
            telefone=telefone_para(ddi) if rng.random() < 0.82 else None,
            endereco=endereco_para(loc) if rng.random() < 0.9 else None,
            ddi_pass=ddi_pass, passaporte=pass_nro,
            atividade=rng.lognormvariate(0, 1.0) * (0.5 if streamer else 1.0),
            plats=[], moeda=info[ddi][0]))
    # --- contas nas plataformas ---
    plat_sorteio = Amostrador([p.ord for p in plataformas], pesos_conta)
    contas, nros_usados = [], {}
    for u in usuarios:
        k = rng.choices([1, 2, 3, 4], [0.18, 0.36, 0.30, 0.16] if u.streamer else [0.70, 0.24, 0.06, 0.0])[0]
        escolhidas = []
        while len(escolhidas) < k:
            p = plat_sorteio.sorteia()
            if p not in escolhidas:
                escolhidas.append(p)
        for p in escolhidas:
            usados = nros_usados.setdefault(p, set())
            while True:
                nro = rng.randrange(10**9, 10**10)
                if nro not in usados:
                    usados.add(nro)
                    break
            contas.append((u.ord, p, nro))
        u.plats = escolhidas
    assert len(contas) <= 9900, f"contas demais: {len(contas)}"
    return usuarios, contas


# =====================================================================
# Canais, patrocínios, membros
# =====================================================================
def tipo_canal():
    r = rng.random()
    return "publico" if r < 0.72 else "misto" if r < 0.92 else "privado"


def nome_de_canal(u, lang, usados_plat):
    n_curto = u.first if rng.random() < 0.65 else re.sub(r"[\d_.]+$", "", u.nick) or u.first
    n_curto = n_curto[:1].upper() + n_curto[1:]
    for _ in range(40):
        modelo = rng.choice(NOMES_CANAL.get(lang, NOMES_CANAL["en"]))
        nome = modelo.format(n=n_curto, N=u.nick)
        if nome.lower() not in usados_plat:
            usados_plat.add(nome.lower())
            return nome
    nome = f"{u.nick} {rng.randrange(2, 99)}"
    usados_plat.add(nome.lower())
    return nome


def jogo_do_canal(lang, ddi):
    itens = [j for j, _ in JOGOS]
    pesos = [p for _, p in JOGOS]
    if lang == "pt":
        pesos = [p * (3 if j == "Free Fire" else 1) for j, p in zip(itens, pesos)]
    else:
        pesos = [p * (0.4 if j == "Free Fire" else 1) for j, p in zip(itens, pesos)]
    return Amostrador(itens, pesos).sorteia()


def gerar_canais(usuarios, plataformas, fama_plat):
    por_ord = {p.ord: p for p in plataformas}
    streamers = [u for u in usuarios if u.streamer]
    fama_streamer = {u.ord: min(pesos_pareto(1, 1.15, 40.0)[0], 60000.0) for u in streamers}
    contas_streamers = [(u, p) for u in streamers for p in u.plats]
    # 1 canal garantido por streamer, o resto sorteado entre as demais contas de streamer
    escolhidos = []
    usadas = set()
    for u in streamers:
        p = rng.choice(u.plats)
        escolhidos.append((u, p))
        usadas.add((u.ord, p))
    restantes = [(u, p) for u, p in contas_streamers if (u.ord, p) not in usadas]
    rng.shuffle(restantes)
    escolhidos += restantes[:max(0, N_CANAIS - len(escolhidos))]
    assert len(escolhidos) >= 1000, len(escolhidos)

    canais = []
    nomes_por_plat = {}
    for u, p in escolhidos:
        plat = por_ord[p]
        lang = u.lang if rng.random() < 0.92 else "en"
        lang = lang if lang in DESCRICOES else "en"
        jogo = jogo_do_canal(lang, u.ddi)
        limite_inf = max(plat.data, u.nasc + timedelta(days=16 * 365), date(2008, 1, 1))
        limite_sup = FIM_VIDEOS - timedelta(days=45)
        if limite_inf >= limite_sup:
            limite_inf = limite_sup - timedelta(days=200)
        inicio = limite_inf + timedelta(days=int((limite_sup - limite_inf).days * rng.betavariate(2.2, 1.2)))
        f = fama_streamer[u.ord] * fama_plat[p - 1] * rng.lognormvariate(0, 0.5)
        dia = rng.choice(DIAS.get(lang, DIAS["en"]))
        desc = rng.choice(DESCRICOES[lang]).format(g=jogo, d=dia, h=rng.choice([14, 16, 18, 19, 20, 21, 22]), a=inicio.year)
        canais.append(Registro(
            ord=0, streamer=u, plat=p, lang=lang, jogo=jogo, tipo=tipo_canal(), inicio=inicio, desc=desc, f=f,
            nome=nome_de_canal(u, lang, nomes_por_plat.setdefault(p, set())), niveis=False, membros=[]))
    canais.sort(key=lambda c: (c.inicio, c.streamer.ord, c.plat))
    for i, c in enumerate(canais, start=1):
        c.ord = i
    # --- canais parceiros (têm programa de membros) ---
    ranking = sorted(canais, key=lambda c: c.f * rng.lognormvariate(0, 0.8), reverse=True)
    for c in ranking[:N_CANAIS_COM_NIVEIS]:
        c.niveis = True
    return canais


def gerar_niveis(canais):
    linhas = []
    for c in canais:
        if not c.niveis:
            continue
        conj = rng.choice(NOMES_NIVEL.get(c.lang, NOMES_NIVEL["en"]))
        escala = 1.0
        precos = [rng.choice(opcoes) * escala for opcoes in PRECOS_NIVEL]
        for k in range(1, 5):                 # garante preços crescentes
            if precos[k] <= precos[k - 1]:
                precos[k] = round(precos[k - 1] * 1.6, 2)
        for n in range(5):
            linhas.append((c.ord, n + 1, conj[n], round(precos[n], 2)))
    return linhas


def gerar_patrocinios(canais, patrocinadores, empresas):
    por_ord = {e.ord: e for e in empresas}
    amostra_canais = Amostrador(canais, [c.f ** 0.9 for c in canais])
    amostra_emp = Amostrador(patrocinadores, pesos_pareto(len(patrocinadores), 1.3))
    pares = {}
    while len(pares) < N_PATROCINIOS:
        c = amostra_canais.sorteia()
        e = amostra_emp.sorteia()
        if (e, c.ord) in pares:
            continue
        v = max(100.0, 80 * c.f ** 0.5 * rng.lognormvariate(0, 0.45))
        v = round(v / 50) * 50 if v >= 500 else round(v / 10) * 10
        pares[(e, c.ord)] = max(100, v)
    return [(e, c, float(v)) for (e, c), v in pares.items()]


class PoolUsuarios:
    """Usuários por plataforma, com preferência pelo idioma do canal."""

    def __init__(self, usuarios):
        por_plat = {}
        for u in usuarios:
            for p in u.plats:
                por_plat.setdefault(p, []).append(u)
        self.todos = {p: Amostrador(us, [u.atividade for u in us]) for p, us in por_plat.items()}
        self.por_lang = {}
        for p, us in por_plat.items():
            langs = {}
            for u in us:
                langs.setdefault(u.lang, []).append(u)
            self.por_lang[p] = {l: Amostrador(v, [u.atividade for u in v]) for l, v in langs.items()}

    def sorteia(self, plat, lang):
        if plat not in self.todos:
            return None
        if rng.random() < 0.8 and lang in self.por_lang[plat]:
            return self.por_lang[plat][lang].sorteia()
        return self.todos[plat].sorteia()


def gerar_inscricoes(canais, pool):
    com_niveis = [c for c in canais if c.niveis]
    amostra = Amostrador(com_niveis, [c.f ** 0.8 for c in com_niveis])
    nivel = Amostrador([1, 2, 3, 4, 5], [0.55, 0.20, 0.13, 0.08, 0.04])
    pares = {}
    tentativas = 0
    while len(pares) < N_INSCRICOES and tentativas < N_INSCRICOES * 20:
        tentativas += 1
        c = amostra.sorteia()
        u = pool.sorteia(c.plat, c.lang)
        if u is None or u.ord == c.streamer.ord or (c.ord, u.ord) in pares:
            continue
        pares[(c.ord, u.ord)] = nivel.sorteia()
        c.membros.append(u)
    assert len(pares) >= 1000
    return [(c, u, n) for (c, u), n in pares.items()]


# =====================================================================
# Vídeos
# =====================================================================
PESO_DIA_SEMANA = [0.9, 0.9, 1.0, 1.0, 1.2, 1.5, 1.4]       # seg..dom
PESO_HORA = [0.5, 0.3, 0.2, 0.1, 0.1, 0.1, 0.2, 0.4, 0.6, 0.8, 0.9, 1.0, 1.1, 1.0, 1.1, 1.3, 1.5, 1.8, 2.2, 2.8, 3.0, 2.8, 2.0, 1.2]


def gerar_videos(canais):
    amostra_canal = Amostrador(canais, [c.f ** 0.45 * rng.lognormvariate(0, 0.5) for c in canais])
    amostra_hora = Amostrador(range(24), PESO_HORA)
    amostra_jogo_cache = {}
    contadores = {}
    usados = set()
    videos = []
    while len(videos) < N_VIDEOS:
        c = amostra_canal.sorteia()
        # data: mais perto do presente é mais provável; respeita o início do canal e o peso do dia da semana
        for _ in range(30):
            dias = (FIM_VIDEOS - c.inicio).days
            if dias < 1:
                dia = c.inicio
            else:
                dia = c.inicio + timedelta(days=int(dias * rng.betavariate(1.6, 1.0)))
            if rng.random() < PESO_DIA_SEMANA[dia.weekday()] / 1.5:
                break
        hora = amostra_hora.sorteia()
        t0 = datetime(dia.year, dia.month, dia.day, hora, rng.randrange(60), rng.randrange(60))
        r = rng.random()
        tipo = "live" if r < 0.52 else "vod" if r < 0.88 else "short"
        # o tema do vídeo costuma ser o jogo principal do canal; às vezes outro
        jogo = c.jogo if rng.random() < 0.72 else jogo_do_canal(c.lang, c.streamer.ddi)
        k = contadores.get((c.ord, jogo), 0) + 1
        contadores[(c.ord, jogo)] = k
        lang = c.lang
        modelos = TITULOS.get(lang, TITULOS["en"])
        if jogo in ("Just Chatting", "IRL") and tipo == "live":
            titulo = rng.choice(TITULOS_CHAT.get(lang, TITULOS_CHAT["en"])).format(n=k)
        else:
            titulo = rng.choice(modelos[tipo]).format(g=jogo, n=k, h=rng.randint(2, 12), m=rng.choice([5, 8, 10, 12, 15, 20]),
                                                     s=rng.choice([15, 20, 30, 45, 60]))
        if tipo == "live" and rng.random() < 0.35:
            titulo = ("🔴 " if rng.random() < 0.5 else "[AO VIVO] " if lang == "pt" else "[LIVE] ") + titulo
        chave = (c.ord, titulo, t0)
        if chave in usados:
            continue
        usados.add(chave)
        if tipo == "live":
            dur = int(min(max(rng.lognormvariate(math.log(9000), 0.55), 1800), 50400))
        elif tipo == "vod":
            dur = int(min(max(rng.lognormvariate(math.log(1080), 0.6), 180), 5400))
        else:
            dur = rng.randint(15, 170)
        fator = {"live": 1.0, "vod": 1.1, "short": 2.0}[tipo]
        total = max(1, int(c.f * rng.lognormvariate(math.log(0.55), 0.9) * fator))
        if tipo == "live":
            simul = max(1, int(total * rng.uniform(0.02, 0.15)))
        else:
            simul = int(total * rng.uniform(0.002, 0.03))
        simul = min(simul, total)
        videos.append(Registro(ord=0, canal=c, titulo=titulo, t0=t0, tema=jogo, dur=dur, simul=simul,
                               total=total, tipo=tipo))
    videos.sort(key=lambda v: v.t0)
    for i, v in enumerate(videos, start=1):
        v.ord = i
    return videos


def gerar_participa(videos, usuarios):
    streamers_por_plat = {}
    for u in usuarios:
        if u.streamer:
            for p in u.plats:
                streamers_por_plat.setdefault(p, []).append(u)
    pools = {p: Amostrador(us, [u.atividade for u in us]) for p, us in streamers_por_plat.items()}
    amostra_video = Amostrador(videos, [v.total ** 0.5 * (2.0 if v.tipo == "live" else 1.0) for v in videos])
    pares = set()
    guard = 0
    while len(pares) < N_PARTICIPA and guard < N_PARTICIPA * 30:
        guard += 1
        v = amostra_video.sorteia()
        s = pools.get(v.canal.plat)
        if s is None:
            continue
        g = s.sorteia()
        if g.ord == v.canal.streamer.ord or (v.ord, g.ord) in pares:
            continue
        pares.add((v.ord, g.ord))
    assert len(pares) >= 1000
    return sorted(pares)


# =====================================================================
# Comentários e doações
# =====================================================================
def estilizar(texto, lang, plat_ord):
    r = rng.random()
    if r < 0.25:
        texto = texto.lower()
    elif r < 0.30 and len(texto) < 22:
        texto = texto.upper()
    if rng.random() < 0.35:
        if plat_ord in (2, 3):
            texto += " " + rng.choice(EMOTES_TEXTO)
        else:
            texto += " " + rng.choice(EMOTES_EMOJI) * rng.choice([1, 1, 2, 3])
    return texto


def texto_comentario(tipo, lang, canal, jogo, plat_ord):
    base = {"live": CHAT_LIVE, "vod": CHAT_VOD, "doacao": CHAT_DOACAO}[tipo]
    idioma = lang if rng.random() < 0.85 else "en"
    pool = base.get(idioma) or base["en"]
    modelo = rng.choice(pool)
    s = canal.streamer.nick if rng.random() < 0.6 else canal.nome
    t = modelo.format(s=s, g=jogo, pais_ex="")
    if tipo != "doacao" or rng.random() < 0.5:
        t = estilizar(t, idioma, plat_ord)
    return t[:500]


def nice_local(usd, fator):
    """Valor em moeda local, em degraus 'redondos' (1, 2, 5, 10...), perto do alvo em dólar."""
    alvo = usd / fator
    degraus = [0.5, 1, 1.5, 2, 2.5, 3, 4, 5, 7.5, 10, 15, 20, 25, 30, 40, 50, 75, 100, 150, 200, 250, 300, 400, 500, 750,
               1000, 1500, 2000, 2500, 3000, 5000, 7500, 10000, 15000, 20000, 25000, 50000, 100000, 250000, 500000,
               1000000, 2500000, 5000000]
    alvo = max(alvo, 0.5)
    i = min(range(len(degraus)), key=lambda k: abs(math.log(degraus[k]) - math.log(alvo)))
    if rng.random() < 0.25:                   # às vezes o degrau vizinho
        i = max(0, min(len(degraus) - 1, i + rng.choice([-1, 1])))
    return degraus[i]


BANDEIRAS_PAIS = {
    55: [("visa", 45), ("mastercard", 35), ("elo", 12), ("hipercard", 3), ("amex", 3), ("diners", 2)],
    1: [("visa", 50), ("mastercard", 30), ("amex", 18), ("diners", 2)],
}
BANDEIRAS_PADRAO = [("visa", 55), ("mastercard", 38), ("amex", 5), ("diners", 2)]
FORMAS = ["plataforma", "cartao", "paypal", "bitcoin"]


def afinidade_forma(ddi, plat_ord, forma):
    if forma == "plataforma":
        return 1.6 if plat_ord in (1, 2, 3) else 0.8
    if forma == "cartao":
        return 1.4 if ddi in (55, 52, 54, 56, 57, 51) else 1.0
    if forma == "paypal":
        return 1.5 if ddi in (1, 44, 49, 33, 34, 39, 61, 91) else 0.6
    return 0.7 if ddi in (55, 1) else 1.0   # bitcoin


def numero_cartao(bandeira):
    if bandeira == "visa":
        return luhn_completa("4", 16)
    if bandeira == "mastercard":
        return luhn_completa(rng.choice(["51", "52", "53", "54", "55", "2221"]), 16)
    if bandeira == "amex":
        return luhn_completa(rng.choice(["34", "37"]), 15)
    if bandeira == "diners":
        return luhn_completa(rng.choice(["300", "301", "36"]), 14)
    if bandeira == "elo":
        return luhn_completa(rng.choice(["636368", "504175", "438935", "451416", "636297"]), 16)
    return luhn_completa("606282", 16)        # hipercard


def gerar_comentarios_e_doacoes(videos, pool, usuarios, fator_moeda):
    amostra_video = Amostrador(videos, [v.total ** 0.85 * {"live": 1.0, "vod": 0.7, "short": 0.25}[v.tipo] for v in videos])
    por_ord_user = {u.ord: u for u in usuarios}
    comentarios = []
    for _ in range(N_COMENTARIOS):
        v = amostra_video.sorteia()
        c = v.canal
        if c.membros and rng.random() < 0.12:
            u = rng.choice(c.membros)
        else:
            u = pool.sorteia(c.plat, c.lang)
        if u is None:
            u = rng.choice(usuarios)
        p_online = {"live": 0.78, "vod": 0.08, "short": 0.02}[v.tipo]
        online = rng.random() < p_online
        if online:
            t = v.t0 + timedelta(seconds=v.dur * rng.betavariate(1.2, 2.0))
        else:
            t = v.t0 + timedelta(seconds=v.dur) + timedelta(days=min(rng.expovariate(1 / 1.3), 45))
        t = min(t, datetime(HOJE.year, HOJE.month, HOJE.day, 12, 0, 0))
        t = t.replace(microsecond=0)
        t = max(t, v.t0)
        comentarios.append(Registro(ord=0, video=v, user=u, t=t, online=online, doacoes=0, texto=None))

    # --- quais comentários trazem doação ---
    peso_doador = {u.ord: rng.lognormvariate(0, 1.2) for u in usuarios}
    pesos = [(4.0 if (c.online and c.video.tipo == "live") else 1.0) * peso_doador[c.user.ord] for c in comentarios]
    n_distintos = N_DOACOES - 800
    escolhidos = set()
    amostra = Amostrador(range(len(comentarios)), pesos)
    guard = 0
    while len(escolhidos) < n_distintos and guard < 10 ** 6:
        guard += 1
        escolhidos.add(amostra.sorteia())
    for i in escolhidos:
        comentarios[i].doacoes = 1
    extras = 0
    lista = sorted(escolhidos)
    while extras < N_DOACOES - len(escolhidos):
        i = rng.choice(lista)
        if comentarios[i].doacoes < 3:
            comentarios[i].doacoes += 1
            extras += 1

    # --- texto dos comentários ---
    for c in comentarios:
        v, ch = c.video, c.video.canal
        tipo = "doacao" if c.doacoes else ("live" if c.online else "vod")
        c.texto = texto_comentario(tipo, ch.lang, ch, v.tema, ch.plat)
    comentarios.sort(key=lambda c: (c.t, c.video.ord))
    for i, c in enumerate(comentarios, start=1):
        c.ord = i

    # --- doações ---
    quotas = dict(QUOTA_DOACOES)
    doacoes = []
    txids, paypals = set(), set()
    pendentes = [c for c in comentarios if c.doacoes for _ in range(c.doacoes)]
    rng.shuffle(pendentes)
    for c in pendentes:
        u = c.user
        pesos_forma = [afinidade_forma(u.ddi, c.video.canal.plat, f) if quotas[f] > 0 else 0.0 for f in FORMAS]
        forma = Amostrador(FORMAS, pesos_forma).sorteia()
        quotas[forma] -= 1
        usd = rng.lognormvariate(math.log(3.5), 0.9)
        if rng.random() < 0.02:
            usd = rng.lognormvariate(math.log(80), 0.8)
        usd = min(max(usd, 0.5), 600)
        valor = nice_local(usd, fator_moeda[u.moeda])
        p_recusado = {"cartao": 0.06, "paypal": 0.025, "bitcoin": 0.01, "plataforma": 0.01}[forma]
        r = rng.random()
        if r < p_recusado:
            status = "recusado"
        elif rng.random() < (0.6 if (c.online and c.video.tipo == "live") else 0.12):
            status = "lido"
        else:
            status = "recebido"
        ref, bandeira, dh = None, None, None
        if forma == "bitcoin":
            while True:
                ref = hashlib.sha256(f"{SEMENTE}-tx-{len(txids)}-{rng.random()}".encode()).hexdigest()
                if ref not in txids:
                    txids.add(ref)
                    break
        elif forma == "paypal":
            while True:
                ref = "".join(rng.choice(string.ascii_uppercase + string.digits) for _ in range(17))
                if ref not in paypals:
                    paypals.add(ref)
                    break
        elif forma == "cartao":
            band = BANDEIRAS_PAIS.get(u.ddi, BANDEIRAS_PADRAO)
            bandeira = Amostrador([b for b, _ in band], [p for _, p in band]).sorteia()
            ref = numero_cartao(bandeira)
            dh = c.t + timedelta(seconds=rng.randint(1, 45))
        doacoes.append(Registro(ord=0, comentario=c, forma=forma, valor=valor, status=status, ref=ref,
                                bandeira=bandeira, dh=dh))
    assert all(q == 0 for q in quotas.values()), quotas
    doacoes.sort(key=lambda d: (d.comentario.t, d.comentario.ord))
    for i, d in enumerate(doacoes, start=1):
        d.ord = i
    return comentarios, doacoes


# =====================================================================
# Escrita do SQL
# =====================================================================
class Saida:
    def __init__(self):
        self.partes = []

    def txt(self, s=""):
        self.partes.append(s + "\n")

    def tabela(self, nome, colunas, linhas, lote=250):
        """Cria a tabela temporária de apoio e a enche com INSERTs em lotes."""
        self.txt(f"CREATE TEMP TABLE {nome} (")
        self.txt(",\n".join(f"    {c} {t}" for c, t in colunas))
        self.txt(") ON COMMIT DROP;")
        cols = ", ".join(c for c, _ in colunas)
        for i in range(0, len(linhas), lote):
            bloco = linhas[i:i + lote]
            self.txt(f"INSERT INTO {nome} ({cols}) VALUES")
            self.txt(",\n".join("(" + ", ".join(lit(x) for x in l) + ")" for l in bloco) + ";")
        self.txt()


def main():
    global SAIDA
    if len(sys.argv) > 1:                       # opcional: caminho de saída diferente do padrão
        SAIDA = Path(sys.argv[1])
    moedas, paises = gerar_referencia()
    amostra_paises = Amostrador([d for d, *_ in PAISES_REAIS], [p for *_, p in PAISES_REAIS])
    empresas, plataformas, pesos_conta, fama_plat, patrocinadores = gerar_empresas_e_plataformas(amostra_paises)
    usuarios, contas = gerar_usuarios(amostra_paises, plataformas, pesos_conta)
    canais = gerar_canais(usuarios, plataformas, fama_plat)
    niveis = gerar_niveis(canais)
    pool = PoolUsuarios(usuarios)
    inscricoes = gerar_inscricoes(canais, pool)
    patrocinios = gerar_patrocinios(canais, patrocinadores, empresas)
    videos = gerar_videos(canais)
    participa = gerar_participa(videos, usuarios)
    fator_moeda = {c: f for c, _, f in moedas}
    comentarios, doacoes = gerar_comentarios_e_doacoes(videos, pool, usuarios, fator_moeda)

    # empresa_pais: sede de cada empresa + filial em outro país para ~25%
    usados_id = set()
    empresa_pais = []
    for e in empresas:
        empresa_pais.append((e.ord, e.ddi, id_nacional(e.ddi, usados_id)))
        if rng.random() < 0.25:
            ddi2 = amostra_paises.sorteia()
            if ddi2 != e.ddi:
                empresa_pais.append((e.ord, ddi2, id_nacional(ddi2, usados_id)))

    contagens = {
        "conversao": len(moedas), "pais": len(paises), "empresa": len(empresas), "empresa_pais": len(empresa_pais),
        "plataforma": len(plataformas), "usuario": len(usuarios),
        "streamer_pais": sum(1 for u in usuarios if u.streamer), "plataforma_usuario": len(contas),
        "canal": len(canais), "nivel_canal": len(niveis), "inscricao": len(inscricoes), "patrocinio": len(patrocinios),
        "video": len(videos), "participa": len(participa), "comentario": len(comentarios), "doacao": len(doacoes),
    }
    for f in FORMAS:
        contagens[{"plataforma": "mecanismo_plat", "cartao": "cartao_credito"}.get(f, f)] = sum(1 for d in doacoes if d.forma == f)
    for t, n in contagens.items():
        assert 1000 <= n <= 10000, (t, n)

    o = Saida()
    o.txt(CABECALHO.format(versao=faker_pkg.VERSION, semente=SEMENTE, resumo="\n".join(
        f"--   {t:<19} {n:>6}" for t, n in contagens.items())))
    o.txt("BEGIN;")
    o.txt()
    o.txt("""-- Confere que os ids gerados pelo banco (identity) batem com a numeração usada nos dados abaixo.
-- Os dados se referenciam pelo número de ordem; o banco numera na mesma ordem em que insere.
CREATE FUNCTION pg_temp.confere_ids(p_tabela TEXT, p_pk TEXT, p_dados TEXT, p_chave TEXT) RETURNS VOID AS $$
DECLARE
    v_erros BIGINT;
BEGIN
    EXECUTE format('SELECT count(*) FROM %I t FULL JOIN %I d ON d.%I = t.%I WHERE t.%I IS DISTINCT FROM d.ord',
                   p_tabela, p_dados, p_chave, p_chave, p_pk) INTO v_erros;
    IF v_erros > 0 THEN
        RAISE EXCEPTION 'Os ids de % não batem com a numeração dos dados (% linhas divergentes)', p_tabela, v_erros;
    END IF;
END;
$$ LANGUAGE plpgsql;
""")
    o.txt("-- ---------------------------------------------------------------------")
    o.txt("-- DADOS GERADOS (Faker) — tabelas temporárias, descartadas no COMMIT")
    o.txt("-- Cada linha já traz os números de ordem (ord) usados pelas FKs das tabelas seguintes.")
    o.txt("-- ---------------------------------------------------------------------")
    o.txt()
    o.tabela("d_conversao", [("ord", "INTEGER"), ("moeda", "CHAR(3)"), ("nome", "VARCHAR(63)"), ("fator", "NUMERIC(18, 6)")],
             [(i, c, n, f) for i, (c, n, f) in enumerate(moedas, start=1)])
    o.tabela("d_pais", [("ord", "INTEGER"), ("ddi", "SMALLINT"), ("nome", "VARCHAR(127)"), ("moeda", "CHAR(3)")],
             [(i, d, n, m) for i, (d, n, m) in enumerate(paises, start=1)])
    o.tabela("d_empresa", [("ord", "INTEGER"), ("nome", "VARCHAR(255)"), ("fantasia", "VARCHAR(255)")],
             [(e.ord, e.nome, e.fantasia) for e in empresas])
    o.tabela("d_empresa_pais", [("nro_empresa", "INTEGER"), ("ddi_pais", "SMALLINT"), ("id_nacional", "VARCHAR(50)")],
             empresa_pais)
    o.tabela("d_plataforma", [("ord", "INTEGER"), ("nome", "VARCHAR(100)"), ("fund", "INTEGER"), ("resp", "INTEGER"), ("data_fund", "DATE")],
             [(p.ord, p.nome, p.fund, p.resp, p.data) for p in plataformas])
    o.tabela("d_usuario", [("ord", "BIGINT"), ("eh_streamer", "BOOLEAN"), ("nick", "VARCHAR(63)"), ("email", "VARCHAR(254)"),
                           ("data_nasc", "DATE"), ("telefone", "VARCHAR(20)"), ("end_postal", "VARCHAR(255)"),
                           ("ddi_residencia", "SMALLINT"), ("ddi_passaporte", "SMALLINT"), ("passaporte", "VARCHAR(20)")],
             [(u.ord, u.streamer, u.nick, u.email, u.nasc, u.telefone, u.endereco, u.ddi, u.ddi_pass, u.passaporte) for u in usuarios])
    o.tabela("d_conta", [("nro_usuario", "BIGINT"), ("nro_plataforma", "INTEGER"), ("nro_conta", "BIGINT")], contas)
    o.tabela("d_canal", [("ord", "INTEGER"), ("nro_streamer", "BIGINT"), ("nro_plataforma", "INTEGER"), ("nome", "VARCHAR(255)"),
                         ("tipo", "tipo_canal_enum"), ("data_inicio", "DATE"), ("descricao", "TEXT")],
             [(c.ord, c.streamer.ord, c.plat, c.nome, c.tipo, c.inicio, c.desc) for c in canais])
    o.tabela("d_nivel", [("id_canal", "INTEGER"), ("nivel", "SMALLINT"), ("nome", "VARCHAR(50)"), ("valor", "NUMERIC(10, 2)")], niveis)
    o.tabela("d_inscricao", [("id_canal", "INTEGER"), ("nro_usuario", "BIGINT"), ("nivel", "SMALLINT")], inscricoes)
    o.tabela("d_patrocinio", [("nro_empresa", "INTEGER"), ("id_canal", "INTEGER"), ("valor", "NUMERIC(14, 2)")], patrocinios)
    o.tabela("d_video", [("ord", "BIGINT"), ("id_canal", "INTEGER"), ("titulo", "VARCHAR(255)"), ("dataH", "TIMESTAMP"),
                         ("tema", "VARCHAR(127)"), ("duracao", "INTEGER"), ("visu_simul", "INTEGER"), ("visu_total", "BIGINT")],
             [(v.ord, v.canal.ord, v.titulo, v.t0, v.tema, v.dur, v.simul, v.total) for v in videos])
    o.tabela("d_participa", [("id_video", "BIGINT"), ("nro_streamer", "BIGINT")], participa)
    o.tabela("d_comentario", [("ord", "BIGINT"), ("id_video", "BIGINT"), ("nro_usuario", "BIGINT"), ("texto", "TEXT"),
                              ("dataH", "TIMESTAMP"), ("online", "BOOLEAN")],
             [(c.ord, c.video.ord, c.user.ord, c.texto, c.t, c.online) for c in comentarios])
    o.tabela("d_doacao", [("ord", "BIGINT"), ("id_comentario", "BIGINT"), ("forma", "VARCHAR(10)"), ("valor", "NUMERIC(14, 2)"),
                          ("status", "status_doacao_enum"), ("ref", "VARCHAR(64)"), ("bandeira", "bandeira_cartao_enum"),
                          ("dataH", "TIMESTAMP")],
             [(d.ord, d.comentario.ord, d.forma, d.valor, d.status, d.ref, d.bandeira, d.dh) for d in doacoes])
    o.txt(CORPO.replace("@MOEDAS_REAIS@", str(len(MOEDAS_REAIS))).replace("@PAISES_REAIS@", str(len(PAISES_REAIS)))
          .replace("@N_CANAIS@", f"{len(canais):,}".replace(",", ".")))
    SAIDA.write_text("".join(o.partes), encoding="utf-8")
    print(f"escrito {SAIDA} ({SAIDA.stat().st_size / 1e6:.1f} MB)", file=sys.stderr)
    for t, n in contagens.items():
        print(f"  {t:<20}{n:>7}", file=sys.stderr)


CABECALHO = """-- =====================================================================
-- 03_povoamento.sql — POVOAMENTO (dados artificiais com aparência de dados reais)
-- Rodar depois de 01_ddl.sql e 02_ddl_estendida.sql, num banco vazio.
--
-- ARQUIVO GERADO por dev/gerar_povoamento.py (Faker {versao}, semente {semente}). Não edite à mão:
-- altere o gerador e rode de novo. O SQL abaixo não depende de Python para rodar.
--
-- O que torna os dados parecidos com os reais:
--   * Referência real: plataformas (YouTube, Twitch, Kick, Facebook Gaming, TikTok Live), países com DDI,
--     moedas e fatores de conversão aproximados.
--   * Pessoas: nicks de gamer, e-mails em provedores comuns do país, telefones, endereços e passaportes
--     no formato de cada país, idade de quem joga (mais gente entre 16 e 30 anos).
--   * Cauda longa: poucos canais concentram o público, os vídeos, os patrocínios e as doações.
--   * Tempo: canais nascem depois da plataforma, vídeos saem à noite e nos fins de semana, comentários ao vivo
--     aparecem durante a transmissão e os offline nos dias seguintes.
--   * Texto no idioma do canal; doações na moeda de quem doou, em valores redondos (5, 10, 20...).
--
-- O que é FICTÍCIO por exigência do enunciado (1.000 a 10.000 tuplas em CADA tabela):
--   * a cauda de países, moedas e plataformas (só o núcleo é real);
--   * a densidade de doações: bitcoin, paypal, cartão e mecanismo da plataforma precisam de 1.000 linhas cada.
-- Todos os identificadores (nacionais, passaportes, telefones, e-mails, cartões) são gerados ao acaso, inclusive
--   os das empresas reais; qualquer coincidência com dados de verdade é acidental.
--
-- Tuplas por tabela:
{resumo}
--
-- A carga roda numa transação só: se algo falhar, o banco volta ao estado vazio (atomicidade, Aula 15).
-- Tudo entra pelas functions de inserção do 02, então as triggers numeram e conferem os dados.
-- =====================================================================
"""

CORPO = """
-- ---------------------------------------------------------------------
-- 1. CONVERSAO — 1.000 moedas (@MOEDAS_REAIS@ reais + o restante fictício)
-- ---------------------------------------------------------------------
INSERT INTO conversao (moeda, nome, fator_conver)
SELECT moeda, nome, fator FROM d_conversao ORDER BY ord;


-- ---------------------------------------------------------------------
-- 2. PAIS — 1.000 países (@PAISES_REAIS@ reais com DDI verdadeiro + o restante fictício, com DDI de 3001 em diante)
-- A moeda do país é ligada pelo código (CHAR(3)), então não depende de numeração.
-- ---------------------------------------------------------------------
INSERT INTO pais (ddi, nome, moeda_id)
SELECT d.ddi, d.nome, c.id
  FROM d_pais d
  JOIN conversao c ON c.moeda = d.moeda
 ORDER BY d.ord;


-- ---------------------------------------------------------------------
-- 3. EMPRESA — plataformas (reais e fictícias) e patrocinadores
-- 4. EMPRESA_PAIS — sede de cada empresa e filial em outro país para parte delas
-- 5. PLATAFORMA — YouTube (1), Twitch (2), Kick, Facebook Gaming, TikTok Live e a cauda fictícia.
--    qtd_users nasce 0; a trigger T1 conta as contas depois.
-- ---------------------------------------------------------------------
INSERT INTO empresa (nome, nome_fantasia)
SELECT nome, fantasia FROM d_empresa ORDER BY ord;
SELECT pg_temp.confere_ids('empresa', 'nro_empresa', 'd_empresa', 'nome');

INSERT INTO empresa_pais (nro_empresa, ddi_pais, id_nacional)
SELECT nro_empresa, ddi_pais, id_nacional FROM d_empresa_pais;

INSERT INTO plataforma (nome, empresa_fund, empresa_respo, data_fund)
SELECT nome, fund, resp, data_fund FROM d_plataforma ORDER BY ord;
SELECT pg_temp.confere_ids('plataforma', 'nro_plataforma', 'd_plataforma', 'nome');


-- ---------------------------------------------------------------------
-- 6 e 7. USUARIO e STREAMER_PAIS — usuários comuns e streamers, misturados na ordem de cadastro
-- Streamer entra por inserir_streamer (usuário + passaporte juntos); os demais, por inserir_usuario.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    r    RECORD;
    v_id BIGINT;
BEGIN
    FOR r IN SELECT * FROM d_usuario ORDER BY ord LOOP
        IF r.eh_streamer THEN
            v_id := inserir_streamer(r.nick, r.email, r.data_nasc, r.telefone, r.end_postal,
                                     r.ddi_residencia, r.ddi_passaporte, r.passaporte);
        ELSE
            v_id := inserir_usuario(r.nick, r.email, r.data_nasc, r.telefone, r.end_postal, r.ddi_residencia);
        END IF;
        IF v_id <> r.ord THEN
            RAISE EXCEPTION 'usuario % recebeu o id % (esperado %)', r.nick, v_id, r.ord;
        END IF;
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 8. PLATAFORMA_USUARIO — contas dos usuários nas plataformas
-- Streamers têm de 1 a 4 contas (para ter canais em plataformas diferentes); a maioria dos demais, uma.
-- A trigger T1 atualiza plataforma.qtd_users a cada conta.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM d_conta LOOP
        PERFORM inserir_conta_plataforma(r.nro_usuario, r.nro_plataforma, r.nro_conta);
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 9. CANAL — @N_CANAIS@ canais, sempre de um streamer numa plataforma onde ele tem conta (a trigger T7 confere)
-- Ordenados pela data de início: os canais mais antigos têm os menores ids.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    r    RECORD;
    v_id INTEGER;
BEGIN
    FOR r IN SELECT * FROM d_canal ORDER BY ord LOOP
        v_id := inserir_canal(r.nro_streamer, r.nro_plataforma, r.nome, r.tipo, r.data_inicio, r.descricao);
        IF v_id <> r.ord THEN
            RAISE EXCEPTION 'canal % recebeu o id % (esperado %)', r.nome, v_id, r.ord;
        END IF;
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 10. NIVEL_CANAL — os 5 níveis de membro dos canais parceiros (só parte dos canais tem programa de membros)
-- Cada canal escolhe os nomes e os preços dos seus níveis (em dólar), sempre crescentes.
-- ---------------------------------------------------------------------
INSERT INTO nivel_canal (id_canal, nivel, nome, valor, gif)
SELECT id_canal, nivel, nome, valor,
       'https://cdn.exemplo.com/niveis/' || id_canal || '_' || nivel || '.gif'
  FROM d_nivel
 ORDER BY id_canal, nivel;


-- ---------------------------------------------------------------------
-- 11. INSCRICAO — membros vigentes (a maioria no nível 1, o mais barato)
-- Cada membro tem conta na plataforma do canal e prefere canais do próprio idioma.
-- ---------------------------------------------------------------------
INSERT INTO inscricao (id_canal, nro_usuario, nivel)
SELECT id_canal, nro_usuario, nivel FROM d_inscricao;


-- ---------------------------------------------------------------------
-- 12. PATROCINIO — patrocínios vigentes, concentrados nos canais grandes
-- O valor (em dólar) cresce com o tamanho do canal e é arredondado como num contrato (múltiplos de 10 ou 50).
-- ---------------------------------------------------------------------
INSERT INTO patrocinio (nro_empresa, id_canal, valor)
SELECT nro_empresa, id_canal, valor FROM d_patrocinio;


-- ---------------------------------------------------------------------
-- 13. VIDEO — vídeos de três tipos: live (horas), vídeo editado (minutos) e short (segundos)
-- Ordenados pela data de postagem. Canais grandes têm mais vídeos e mais visualizações.
-- A trigger T2 soma visu_total em canal.qtd_visualizacoes.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    r    RECORD;
    v_id BIGINT;
BEGIN
    FOR r IN SELECT * FROM d_video ORDER BY ord LOOP
        v_id := inserir_video(r.id_canal, r.titulo, r.dataH, r.tema, r.duracao, r.visu_simul, r.visu_total);
        IF v_id <> r.ord THEN
            RAISE EXCEPTION 'video % recebeu o id % (esperado %)', r.titulo, v_id, r.ord;
        END IF;
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 14. PARTICIPA — streamers convidados (nunca o dono do canal), da mesma plataforma
-- ---------------------------------------------------------------------
INSERT INTO participa (id_video, nro_streamer)
SELECT id_video, nro_streamer FROM d_participa;


-- ---------------------------------------------------------------------
-- 15. COMENTARIO — comentários ordenados no tempo, para o seq (trigger T3) seguir a ordem em que apareceram
-- Online: durante a transmissão, mais no começo. Offline: nos dias seguintes, em queda.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    r    RECORD;
    v_id BIGINT;
BEGIN
    FOR r IN SELECT * FROM d_comentario ORDER BY ord LOOP
        v_id := inserir_comentario(r.id_video, r.nro_usuario, r.texto, r.dataH, r.online);
        IF v_id <> r.ord THEN
            RAISE EXCEPTION 'comentario % recebeu o id % (esperado %)', r.ord, v_id, r.ord;
        END IF;
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 16. DOACAO + BITCOIN, PAYPAL, CARTAO_CREDITO, MECANISMO_PLAT
-- Valor na moeda do país de quem doou, em degraus redondos. Forma de pagamento coerente com o país
--   e a plataforma; recusas são mais comuns no cartão. Cada doação entra com a sua forma, e as
--   functions gravam doacao e subtabela juntas (as triggers T4, T5 e T6 numeram e conferem).
-- ---------------------------------------------------------------------
DO $$
DECLARE
    r    RECORD;
    v_id BIGINT;
BEGIN
    FOR r IN SELECT * FROM d_doacao ORDER BY ord LOOP
        CASE r.forma
            WHEN 'bitcoin'    THEN v_id := inserir_doacao_bitcoin(r.id_comentario, r.valor, r.status, r.ref::CHAR(64));
            WHEN 'paypal'     THEN v_id := inserir_doacao_paypal(r.id_comentario, r.valor, r.status, r.ref);
            WHEN 'cartao'     THEN v_id := inserir_doacao_cartao(r.id_comentario, r.valor, r.status, r.ref, r.bandeira, r.dataH);
            ELSE                   v_id := inserir_doacao_plataforma(r.id_comentario, r.valor, r.status);
        END CASE;
        IF v_id <> r.ord THEN
            RAISE EXCEPTION 'doacao % recebeu o id % (esperado %)', r.ord, v_id, r.ord;
        END IF;
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- Finalização
-- ---------------------------------------------------------------------
DROP FUNCTION pg_temp.confere_ids(TEXT, TEXT, TEXT, TEXT);

-- Preenche as visões materializadas (criadas WITH NO DATA no 02).
SELECT atualizar_visoes_materializadas();

-- Atualiza as estatísticas do catálogo (Aula 12): o otimizador usa esses números para estimar a
--   seletividade dos predicados e escolher o plano. Sem ANALYZE ele estimaria às cegas.
ANALYZE;

COMMIT;
"""


if __name__ == "__main__":
    main()
