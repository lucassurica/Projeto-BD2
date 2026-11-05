# Medição dos índices candidatos

Rodada em 04/11/2026 com `medicoes/medir_indices.sql`, **duas vezes seguidas** (rodada A e rodada B) para separar ganho real de ruído.

**Ambiente:** PostgreSQL 18.4, macOS (Apple M4 Pro), banco povoado pelo `03_povoamento.sql` (seed 0.2026), sem o `05_indices.sql`.

**Método:**
- Cada consulta roda 300 vezes, e cada escrita ou REFRESH, 20 vezes.
- A primeira execução de cada uma só aquece o cache e é descartada.
- Uma rodada inteira de aquecimento vem antes da linha de base.
- Cada índice candidato é criado sozinho, depois roda-se `ANALYZE`, mede-se tudo e o índice é apagado.
- As escritas são desfeitas depois de medidas, para não mudar os dados entre uma medição e outra.

Os tempos são médias em milissegundos. "Ganho" é o tempo sem índice dividido pelo tempo com índice, então acima de 1 significa mais rápido.

## Linha de base (rodada A, sem nenhum índice extra)

| Operação | ms |
|---|---|
| Refresh das 2 visões materializadas | 20,955 |
| Inserir 100 Super Chats (trigger T5) | 17,506 |
| Inserir 100 comentários (trigger T3) | 1,982 |
| Q1 filtro plataforma | 0,551 |
| Q3 filtro streamer | 0,414 |
| Q2 filtro canal | 0,305 |
| Q6 filtro usuário | 0,256 |
| Q4 filtro plataforma | 0,221 |
| Q12 filtro plataforma | 0,060 |
| Q5 filtro empresa | 0,041 |
| Q7 filtro canal | 0,039 |

## Ganhos dos candidatos (operações em que o índice mudou o tempo em mais de 25%)

| Índice candidato | Operação | Ganho rodada A | Ganho rodada B |
|---|---|---|---|
| **comentario(nro_usuario)** B+-tree | Inserir 100 Super Chats | 4,07x | 3,86x |
| **comentario(nro_usuario)** hash | Inserir 100 Super Chats | 3,38x | 4,08x |
| **mv_interacoes_video(id_canal)** B+-tree | Q2 filtro canal | 5,26x | 5,26x |
| | Q3 filtro streamer | 1,98x | 1,89x |
| mv_interacoes_video(id_canal) hash | Q2 filtro canal | 5,17x | 5,26x |
| | Q3 filtro streamer | 1,99x | 1,96x |
| **inscricao(nro_usuario)** hash | Q6 filtro usuário | 3,88x | 3,95x |
| inscricao(nro_usuario) B+-tree | Q6 filtro usuário | 3,94x | 3,90x |
| **mv_doacoes_canal(id_canal)** B+-tree | Q7 filtro canal | 2,17x | 2,17x |
| mv_doacoes_canal(id_canal) hash | Q7 filtro canal | 2,29x | 2,17x |
| **canal(nro_streamer)** hash | Q3 filtro streamer | < 1,25x | 1,35x |
| canal(nro_streamer) B+-tree | Q3 filtro streamer | 1,34x | 1,38x |
| video(id_canal) | nenhuma consulta | sem ganho | sem ganho |
| canal(nro_plataforma) | nenhuma consulta | sem ganho (já coberto pelo UNIQUE) | sem ganho |
| doacao(id_comentario) parcial | nenhuma consulta | sem ganho (já coberto pelo UNIQUE) | sem ganho |

Em negrito estão os 5 escolhidos para o `sql/05_indices.sql`.

## Como ler o ruído

- **REFRESH:** o tempo do REFRESH variou até 50% entre as medições, inclusive com índices que não participam dele. A medição do REFRESH não serve para comparar índices; ela fica só como referência de custo.
- **Hash contra B+-tree:** a diferença entre as duas estruturas inverte de uma rodada para outra. No `comentario(nro_usuario)`, a B+-tree ganhou na rodada A e o hash na B. Ou seja, **empataram**. O desempate foi conceitual e está explicado no `05_indices.sql`.
- **`canal(nro_streamer)` hash:** ficou logo abaixo do corte de 25% na rodada A e logo acima na B. É um ganho real, mas o menor dos cinco.

## Conclusões

1. **Quase todos os filtros por plataforma e por empresa já tinham índice.**
   - `UNIQUE (nro_plataforma, nome_canal)` e a PK `(nro_empresa, id_canal)` começam por essas colunas.
   - Por isso as consultas 1, 4, 5 e 12 não precisam de índice novo.
   - O índice `canal(nro_plataforma)` que o grupo tinha planejado seria redundante.
2. **O maior ganho absoluto veio de uma escrita, não de uma consulta.** A trigger que numera os Super Chats varria a tabela de comentários inteira a cada doação. Com o índice, inserir 100 Super Chats caiu de cerca de 17 ms para cerca de 4 ms.
3. **Hash e B+-tree empataram** em todas as buscas por igualdade.
4. **Os ganhos absolutos são pequenos,** frações de milissegundo nas consultas, porque o enunciado limita cada tabela a 10.000 linhas. O que vale para a justificativa é o ganho relativo. Ele cresce com o volume: sem índice o custo é proporcional ao tamanho da tabela; com índice, ao tamanho do resultado.
