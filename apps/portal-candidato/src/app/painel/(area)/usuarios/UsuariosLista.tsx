"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

interface Avaliado {
  inscricao_id: string;
  candidato: string;
  grupo: string | null;
  nivel: string | null;
  avaliador_informado: string;
  lancada_em: string;
}

interface UsuarioPainel {
  user_id: string;
  nome: string;
  email: string;
  perfil: string;
  ativo: boolean;
  cpf_mascarado: string | null;
  senha_definida: boolean;
  bloqueado_ate: string | null;
  ultimo_acesso: string | null;
  qtd_fichas: number;
  avaliados: Avaliado[];
}

const PERFIL: Record<string, string> = { comissao: "Comissão" };
const fmtData = (v: string | null) => (v ? new Date(v).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }) : "—");

export function UsuariosLista() {
  const [usuarios, setUsuarios] = useState<UsuarioPainel[] | null>(null);
  const [erro, setErro] = useState("");
  const [aberto, setAberto] = useState<string | null>(null);

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("listar_usuarios_painel")
      .then(({ data, error }: { data: UsuarioPainel[] | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else setUsuarios(data ?? []);
      });
  }, []);

  if (erro) return <p className="err">{erro}</p>;
  if (!usuarios) return <p className="hint">Carregando…</p>;

  return (
    <div className="tabela-wrap">
      <table className="tabela">
        <thead>
          <tr>
            <th>Usuário</th>
            <th>Perfil</th>
            <th>Situação</th>
            <th>CPF</th>
            <th>Último acesso</th>
            <th>Fichas lançadas</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {usuarios.map((u) => (
            <LinhaUsuario key={u.user_id} u={u} aberto={aberto === u.user_id} alternar={() => setAberto(aberto === u.user_id ? null : u.user_id)} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

function LinhaUsuario({ u, aberto, alternar }: { u: UsuarioPainel; aberto: boolean; alternar: () => void }) {
  const bloqueado = !!u.bloqueado_ate;
  return (
    <>
      <tr>
        <td>
          <strong>{u.nome}</strong>
          <div>
            <small className="hint">{u.email}</small>
          </div>
        </td>
        <td>{PERFIL[u.perfil] ?? u.perfil}</td>
        <td>
          <span className={`pill ${u.ativo ? "pill-ok" : "pill-muted"}`}>{u.ativo ? "Ativo" : "Desativado"}</span>
          {!u.senha_definida ? <div className="hint">Senha ainda não definida</div> : null}
          {bloqueado ? <div className="hint">Bloqueado até {fmtData(u.bloqueado_ate)}</div> : null}
        </td>
        <td>{u.cpf_mascarado ?? <span className="hint">não cadastrado</span>}</td>
        <td>{fmtData(u.ultimo_acesso)}</td>
        <td>{u.qtd_fichas}</td>
        <td style={{ textAlign: "right" }}>
          {u.qtd_fichas > 0 ? (
            <button type="button" className="btn btn-sm" onClick={alternar}>
              {aberto ? "Fechar" : "Ver candidatos"}
            </button>
          ) : null}
        </td>
      </tr>
      {aberto ? (
        <tr>
          <td colSpan={7}>
            <p className="hint" style={{ marginTop: 0 }}>
              Candidatos avaliados por {u.nome} (fichas de entrevista técnica enviadas com este login — as notas não aparecem aqui):
            </p>
            <ul style={{ margin: "6px 0", paddingLeft: 18 }}>
              {u.avaliados.map((a) => (
                <li key={`${a.inscricao_id}-${a.lancada_em}`}>
                  <Link href={`/painel/candidato/${a.inscricao_id}?aba=entrevista`}>{a.candidato}</Link>
                  {a.grupo && a.nivel ? ` — ${a.grupo} · ${a.nivel}` : ""} — enviada em {fmtData(a.lancada_em)}
                  {a.avaliador_informado !== u.nome ? <small className="hint"> (nome informado na ficha: {a.avaliador_informado})</small> : null}
                </li>
              ))}
            </ul>
          </td>
        </tr>
      ) : null}
    </>
  );
}
