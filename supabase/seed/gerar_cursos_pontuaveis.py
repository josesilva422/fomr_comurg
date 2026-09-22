"""Gera a migração que carrega interno.cursos_pontuaveis (Anexo I, item 2.1 do edital).

A lista é "exemplificativa" (item 2.1, última linha): cursos fora dela podem pontuar por
deliberação motivada da Comissão. O motor de regras sinaliza os que não batem; não decide sozinho.

Uso:  python supabase/seed/gerar_cursos_pontuaveis.py
"""
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]

CATALOGO = {
    "A": [
        "Alvenaria Estrutural", "AutoCAD Avançado", "Autodesk Civil 3D", "Básico de Licitações e Contratos",
        "Compliance", "Eberick", "Estudo Técnico Preliminar (ETP)", "Excel Avançado",
        "Geotecnologias (GPS, RTK, Drones)", "Gestão e Fiscalização de Contratos",
        "Portal de Compras do Governo Federal", "QiBuilder", "Revit", "SEI Avançado", "SEI Básico",
        "Termo de Referência (TR)", "TQS",
    ],
    "B": [
        "Básico de Licitações e Contratos", "BPM, gestão de processos, melhoria contínua", "Canva",
        "Compliance", "ETP", "Excel Avançado", "Gestão e Fiscalização de Contratos",
        "Governança pública e corporativa", "MS Project", "Planejamento estratégico, indicadores/KPIs, OKRs",
        "PMO", "PMP/PgMP, PRINCE2, Scrum, Agile, Kanban ou certificações equivalentes", "Power BI",
        "Power Point", "Primavera", "SEI Avançado", "SEI Básico", "TR",
    ],
    "C": [
        "Agente de Contratação", "Aplicação de Sanções Administrativas", "AutoCAD",
        "Capacitação em orçamentação de obras civis (SINAPI/SICRO/GOINFRA)", "Compliance Público",
        "Elaboração de ETP", "Elaboração de TR", "Excel Avançado", "Gestão e Fiscalização de Contratos",
        "LGPD", "Licitações e Contratos — Lei nº 14.133/2021", "Mapeamento de Processos", "MS Project",
        "Orçamento Público", "Pesquisa de Preços", "Planejamento de Contratação", "PMO",
        "Portal de Compras do Governo Federal", "Pregão Eletrônico", "Primavera", "Redação Oficial",
        "Registro de Preços", "Revit", "SEI Avançado", "SEI Básico", "Transparência Pública",
        "Termos de Ajustes e Convênios", "Tomada de Contas Especial",
        "Utilização de bases SINAPI/SICRO/GOINFRA",
    ],
}


def q(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


linhas = [
    "-- Fase 2 · Catálogo de cursos e certificações pontuáveis por Grupo (Anexo I, item 2.1).",
    "-- GERADO por supabase/seed/gerar_cursos_pontuaveis.py. Lista exemplificativa (item 2.1, última linha):",
    "-- cursos fora dela podem pontuar por deliberação motivada da Comissão; o motor apenas sinaliza.",
    "-- Reversão: supabase/rollback/20260922100000_catalogo_cursos_pontuaveis.down.sql",
    "insert into interno.cursos_pontuaveis (grupo, denominacao) values",
]
valores = [f"  ('{g}', {q(c)})" for g, itens in CATALOGO.items() for c in itens]
linhas.append(",\n".join(valores))
linhas.append("on conflict do nothing;")
(RAIZ / "supabase/migrations/20260922100000_catalogo_cursos_pontuaveis.sql").write_text(
    "\n".join(linhas) + "\n", encoding="utf-8"
)
print("linhas:", len(valores))
