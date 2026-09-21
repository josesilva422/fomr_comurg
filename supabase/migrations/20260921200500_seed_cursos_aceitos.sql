-- Fase 1 · Graduações aceitas por grupo/nível (itens 3.2 a 3.4). GERADO por supabase/seed/gerar_cursos_aceitos.py
-- Reversão: supabase/rollback/20260921200500_seed_cursos_aceitos.down.sql
with
  eng (curso)      as (values ('Engenharia Aeronáutica'), ('Engenharia Agrícola'), ('Engenharia Agronômica'), ('Engenharia Ambiental'), ('Engenharia Biomédica'), ('Engenharia Cartográfica'), ('Engenharia Civil'), ('Engenharia da Computação'), ('Engenharia de Agrimensura'), ('Engenharia de Alimentos'), ('Engenharia de Automação e Controle'), ('Engenharia de Biossistemas'), ('Engenharia de Controle e Automação'), ('Engenharia de Energia'), ('Engenharia de Materiais'), ('Engenharia de Minas'), ('Engenharia de Petróleo'), ('Engenharia de Produção'), ('Engenharia de Redes de Comunicação'), ('Engenharia de Telecomunicações'), ('Engenharia de Transportes'), ('Engenharia Elétrica'), ('Engenharia Eletrônica'), ('Engenharia Florestal'), ('Engenharia Física'), ('Engenharia Geológica'), ('Engenharia Hídrica'), ('Engenharia Industrial'), ('Engenharia Mecânica'), ('Engenharia Mecatrônica'), ('Engenharia Metalúrgica'), ('Engenharia Naval'), ('Engenharia Nuclear'), ('Engenharia Química'), ('Engenharia Sanitária'), ('Engenharia Sanitária e Ambiental')),
  eng_sr_a (curso) as (values ('Engenharia Ambiental'), ('Engenharia Civil'), ('Engenharia de Energia'), ('Engenharia Hídrica'), ('Engenharia Industrial'), ('Engenharia Sanitária'), ('Engenharia Sanitária e Ambiental')),
  base_a (curso)   as (values ('Administração'), ('Arquitetura e Urbanismo'), ('Direito')),
  base_a_sr (curso) as (values ('Arquitetura e Urbanismo'), ('Direito')),
  base_b (curso)   as (values ('Administração'), ('Arquitetura e Urbanismo'), ('Ciências Contábeis'), ('Ciências Econômicas'), ('Direito'), ('Sistemas de Informação'), ('Tecnologia da Informação')),
  base_c (curso)   as (values ('Administração'), ('Arquitetura e Urbanismo'), ('Ciências Contábeis'), ('Ciências Econômicas'), ('Direito')),
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
