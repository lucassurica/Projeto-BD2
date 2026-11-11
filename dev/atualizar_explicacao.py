#!/usr/bin/env python3
"""Copia os trechos de código para dentro de docs/EXPLICACAO-DIDATICA.md.

No documento, cada trecho é marcado assim (o conteúdo entre os dois comentários é gerado):

    <!-- codigo: sql/01_ddl.sql | ^CREATE TABLE empresa\\b | ^\\);$ -->
    <!-- /codigo -->

Campos: arquivo | regex da linha de início | regex da linha de fim.
- O trecho vai da 1ª linha que casa com o início até a 1ª linha (a partir dela) que casa com o fim.
- Os comentários SQL colados logo acima do início entram junto (são a explicação curta do código).
- Fim começando com "antes:" termina na linha ANTERIOR à que casa (e descarta linhas em branco e
  separadores "-- ----" do final).

Uso:
    python3 dev/atualizar_explicacao.py              # reescreve o documento
    python3 dev/atualizar_explicacao.py --verificar  # só confere se está em dia (usado pelo dev/testar.sh)
"""
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DOC = RAIZ / "docs" / "EXPLICACAO-DIDATICA.md"
BLOCO = re.compile(r"<!-- codigo: (.+?) -->\n.*?<!-- /codigo -->", re.S)
SEPARADOR = re.compile(r"^\s*$|^-- [-=#]+$")


def extrair(spec: str) -> str:
    arquivo, inicio, fim = (parte.strip() for parte in spec.split(" | "))
    linhas = (RAIZ / arquivo).read_text(encoding="utf-8").splitlines()

    try:
        i = next(n for n, l in enumerate(linhas) if re.search(inicio, l))
    except StopIteration:
        raise SystemExit(f"Início não encontrado: {spec}")
    antes = fim.startswith("antes:")
    padrao_fim = fim[len("antes:"):] if antes else fim
    try:
        j = next(n for n in range(i + (1 if antes else 0), len(linhas)) if re.search(padrao_fim, linhas[n]))
    except StopIteration:
        raise SystemExit(f"Fim não encontrado: {spec}")
    if antes:
        j -= 1
        while j > i and SEPARADOR.match(linhas[j]):
            j -= 1
    while i > 0 and linhas[i - 1].startswith("--"):
        i -= 1

    codigo = "\n".join(linhas[i:j + 1])
    return (
        f"<!-- codigo: {spec} -->\n"
        f"<details>\n<summary>Ver o código: <code>{arquivo}</code>, linhas {i + 1}–{j + 1}</summary>\n\n"
        f"```sql\n{codigo}\n```\n\n</details>\n<!-- /codigo -->"
    )


def main() -> None:
    atual = DOC.read_text(encoding="utf-8")
    novo = BLOCO.sub(lambda m: extrair(m.group(1)), atual)
    if "--verificar" in sys.argv:
        if novo != atual:
            raise SystemExit("docs/EXPLICACAO-DIDATICA.md está desatualizado: rode python3 dev/atualizar_explicacao.py")
        print(f"{len(BLOCO.findall(novo))} trechos em dia")
        return
    DOC.write_text(novo, encoding="utf-8")
    print(f"{len(BLOCO.findall(novo))} trechos atualizados")


if __name__ == "__main__":
    main()
