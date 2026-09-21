"""Gera supabase/seed/cursos_por_grupo.json e a migração que carrega publico.cursos_aceitos.

Fonte: CLAUDE.md, seção 8.3 (itens 3.2 a 3.4 do edital). CONFERIR contra o edital original
quando ele estiver em docs/. Tecnólogo não é aceito em nenhum grupo/nível (item 5.1.6).

Uso:  python supabase/seed/gerar_cursos_aceitos.py
"""
import json
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]

ENGENHARIAS = [
    "Aeronáutica", "Agrícola", "Agronômica", "Ambiental", "Biomédica", "Cartográfica", "Civil",
    "da Computação", "de Agrimensura", "de Alimentos", "de Automação e Controle", "de Biossistemas",
    "de Controle e Automação", "de Energia", "de Materiais", "de Minas", "de Petróleo", "de Produção",
    "de Redes de Comunicação", "de Telecomunicações", "de Transportes", "Elétrica", "Eletrônica",
    "Florestal", "Física", "Geológica", "Hídrica", "Industrial", "Mecânica", "Mecatrônica",
    "Metalúrgica", "Naval", "Nuclear", "Química", "Sanitária", "Sanitária e Ambiental",
]
TODAS_ENG = [f"Engenharia {e}" for e in ENGENHARIAS]
ENG_SENIOR_A = [f"Engenharia {e}" for e in
                ["Ambiental", "Civil", "de Energia", "Hídrica", "Industrial", "Sanitária", "Sanitária e Ambiental"]]

BASE_A = ["Administração", "Arquitetura e Urbanismo", "Direito"]
BASE_B = ["Administração", "Arquitetura e Urbanismo", "Ciências Contábeis", "Ciências Econômicas",
          "Direito", "Sistemas de Informação", "Tecnologia da Informação"]
BASE_C = ["Administração", "Arquitetura e Urbanismo", "Ciências Contábeis", "Ciências Econômicas", "Direito"]

CURSOS = {
    "A": {"junior": BASE_A + TODAS_ENG, "pleno": BASE_A + TODAS_ENG,
          "senior": ["Arquitetura e Urbanismo", "Direito"] + ENG_SENIOR_A},
    "B": {n: BASE_B + TODAS_ENG for n in ("junior", "pleno", "senior")},
    "C": {n: BASE_C + TODAS_ENG for n in ("junior", "pleno", "senior")},
}

(RAIZ / "supabase/seed/cursos_por_grupo.json").write_text(
    json.dumps(CURSOS, ensure_ascii=False, indent=2), encoding="utf-8")

def q(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"

def vals(lista):
    return ", ".join(f"({q(c)})" for c in lista)

sql = f"""-- Fase 1 · Graduações aceitas por grupo/nível (itens 3.2 a 3.4). GERADO por supabase/seed/gerar_cursos_aceitos.py
-- Reversão: supabase/rollback/20260921200500_seed_cursos_aceitos.down.sql
with
  eng (curso)      as (values {vals(TODAS_ENG)}),
  eng_sr_a (curso) as (values {vals(ENG_SENIOR_A)}),
  base_a (curso)   as (values {vals(BASE_A)}),
  base_a_sr (curso) as (values {vals(["Arquitetura e Urbanismo", "Direito"])}),
  base_b (curso)   as (values {vals(BASE_B)}),
  base_c (curso)   as (values {vals(BASE_C)}),
  niveis (nivel)   as (values ('junior'), ('pleno'), ('senior')),
  lista (grupo, nivel, curso) as (
    select 'A', n.nivel, c.curso from niveis n, base_a c where n.nivel in ('junior', 'pleno')
    union all select 'A', n.nivel, c.curso from niveis n, eng c where n.nivel in ('junior', 'pleno')
    union all select 'A', 'senior', curso from base_a_sr
    union all select 'A', 'senior', curso from eng_sr_a
    union all select 'B', n.nivel, c.curso from niveis n, base_b c
    union all select 'B', n.nivel, c.curso from niveis n, eng c
    union all select 'C', n.nivel, c.curso from niveis n, base_c c
    union all select 'C', n.nivel, c.curso from niveis n, eng c
  )
insert into publico.cursos_aceitos (grupo, nivel, curso)
select grupo::publico.grupo_vaga, nivel::publico.nivel_vaga, curso from lista
on conflict do nothing;
"""
(RAIZ / "supabase/migrations/20260921200500_seed_cursos_aceitos.sql").write_text(sql, encoding="utf-8")
print("esperado:", sum(len(l) for n in CURSOS.values() for l in n.values()))
