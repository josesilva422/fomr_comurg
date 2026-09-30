"use client";

import { useEffect, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { CATEGORIAS, tamanhoArquivo, type CategoriaPublicacao } from "@/lib/portal";

interface Publicacao {
  id: string;
  categoria: CategoriaPublicacao;
  titulo: string;
  texto: string | null;
  arquivo_path: string | null;
  arquivo_nome: string | null;
  arquivo_bytes: number | null;
  publicado: boolean;
  publicado_em: string | null;
  criado_por: string | null;
  created_at: string;
}

const LIMITE_BYTES = 20 * 1024 * 1024;
const fmtData = (v: string) => new Date(v).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo", dateStyle: "short", timeStyle: "short" });

// Publicações da página inicial: a Comissão envia PDF ou escreve comunicado, publica e retira do ar. O PDF vai para o
// bucket privado 'publicacoes'; o público só consegue abrir o arquivo de publicação publicada (rota /publicacoes/[id]).
export function PublicacoesGestao() {
  const [lista, setLista] = useState<Publicacao[] | null>(null);
  const [erro, setErro] = useState("");
  const [versao, setVersao] = useState(0);

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("listar_publicacoes")
      .then(({ data, error }: { data: Publicacao[] | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else setLista(data ?? []);
      });
  }, [versao]);

  const recarregar = () => setVersao((v) => v + 1);

  return (
    <div style={{ display: "grid", gap: 20 }}>
      <NovaPublicacao aoSalvar={recarregar} />
      {erro ? <p className="err">{erro}</p> : null}
      {!lista ? (
        <p className="hint">Carregando…</p>
      ) : lista.length === 0 ? (
        <div className="empty">Nenhuma publicação ainda.</div>
      ) : (
        <ul className="doc-lista">
          {lista.map((p) => (
            <ItemPublicacao key={p.id} p={p} aoMudar={recarregar} />
          ))}
        </ul>
      )}
    </div>
  );
}

function NovaPublicacao({ aoSalvar }: { aoSalvar: () => void }) {
  const [categoria, setCategoria] = useState<CategoriaPublicacao>("comunicado");
  const [titulo, setTitulo] = useState("");
  const [texto, setTexto] = useState("");
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [publicarAgora, setPublicarAgora] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState("");
  const [ok, setOk] = useState("");
  const [chaveArquivo, setChaveArquivo] = useState(0);
  const inputArquivo = useRef<HTMLInputElement>(null);

  function escolherArquivo(f: File | null) {
    setErro("");
    if (f && f.type !== "application/pdf") {
      setChaveArquivo((k) => k + 1);
      return setErro("Anexe o documento em PDF.");
    }
    if (f && f.size > LIMITE_BYTES) {
      setChaveArquivo((k) => k + 1);
      return setErro("O PDF passa de 20 MB.");
    }
    setArquivo(f);
  }

  async function salvar() {
    setErro("");
    setOk("");
    if (titulo.trim().length < 3) return setErro("Informe o título.");
    if (!arquivo && texto.trim().length < 3) return setErro("Anexe um PDF ou escreva o texto do comunicado.");
    if (arquivo && arquivo.type !== "application/pdf") return setErro("Envie o arquivo em PDF.");
    if (arquivo && arquivo.size > LIMITE_BYTES) return setErro("O PDF passa de 20 MB.");
    if (publicarAgora && !window.confirm(`Publicar agora na página inicial?\n\n"${titulo.trim()}"`)) return;
    setEnviando(true);
    const supabase = createClient();
    let caminho: string | null = null;
    if (arquivo) {
      caminho = `${new Date().getFullYear()}/${crypto.randomUUID()}.pdf`;
      const { error } = await supabase.storage.from("publicacoes").upload(caminho, arquivo, { contentType: "application/pdf", upsert: false });
      if (error) {
        setEnviando(false);
        return setErro(`Falha ao enviar o PDF: ${error.message}`);
      }
    }
    const { data: id, error } = await supabase.schema("painel").rpc("salvar_publicacao", {
      p_id: null,
      p_categoria: categoria,
      p_titulo: titulo.trim(),
      p_texto: texto.trim() || null,
      p_arquivo_path: caminho,
      p_arquivo_nome: arquivo?.name ?? null,
      p_arquivo_bytes: arquivo?.size ?? null,
    });
    if (error || !id) {
      setEnviando(false);
      return setErro(error?.message ?? "Não foi possível salvar.");
    }
    if (publicarAgora) {
      const r = await supabase.schema("painel").rpc("publicar_publicacao", { p_id: id, p_publicar: true });
      if (r.error) {
        setEnviando(false);
        return setErro(`Salvo, mas não publicado: ${r.error.message}`);
      }
    }
    setEnviando(false);
    setOk(publicarAgora ? "Publicado na página inicial." : "Salvo como não publicado. Use \"Publicar\" na lista quando quiser.");
    setTitulo("");
    setTexto("");
    setArquivo(null);
    setPublicarAgora(false);
    setChaveArquivo((k) => k + 1);
    aoSalvar();
  }

  return (
    <div className="panel" style={{ marginTop: 0 }}>
      <h3 style={{ marginTop: 0 }}>Nova publicação</h3>
      <div style={{ display: "grid", gridTemplateColumns: "minmax(160px, 220px) 1fr", gap: 12 }}>
        <div className="field">
          <label htmlFor="pub-cat">Categoria</label>
          <select id="pub-cat" value={categoria} onChange={(e) => setCategoria(e.target.value as CategoriaPublicacao)}>
            {(Object.keys(CATEGORIAS) as CategoriaPublicacao[]).map((c) => (
              <option key={c} value={c}>
                {CATEGORIAS[c]}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label htmlFor="pub-titulo">Título</label>
          <input
            id="pub-titulo"
            value={titulo}
            maxLength={200}
            onChange={(e) => setTitulo(e.target.value)}
            placeholder={categoria === "edital" ? "Edital nº 001/2026" : categoria === "resultado" ? "Resultado dos pedidos de isenção" : "Título"}
          />
        </div>
      </div>
      <div className="field">
        <label htmlFor="pub-texto">Texto {categoria === "comunicado" ? "do comunicado" : "(opcional, aparece abaixo do título)"}</label>
        <textarea id="pub-texto" rows={3} maxLength={5000} value={texto} onChange={(e) => setTexto(e.target.value)} />
      </div>
      <input
        key={chaveArquivo}
        ref={inputArquivo}
        id="pub-arquivo"
        type="file"
        accept="application/pdf"
        hidden
        onChange={(e) => escolherArquivo(e.target.files?.[0] ?? null)}
      />
      {arquivo ? (
        <div className="pub-anexo">
          <span className="portal-docs-icone" aria-hidden>
            PDF
          </span>
          <div className="pub-anexo-info">
            <b>{arquivo.name}</b>
            <small>{tamanhoArquivo(arquivo.size)} · será enviado ao salvar</small>
          </div>
          <button
            type="button"
            className="btn btn-sm btn-ghost"
            onClick={() => {
              setArquivo(null);
              setChaveArquivo((k) => k + 1);
            }}
          >
            Remover
          </button>
        </div>
      ) : (
        <p className="hint" style={{ margin: "4px 0 0" }}>
          Documento em PDF, até 20 MB{categoria === "comunicado" ? " (opcional no comunicado)" : ""}. Use o botão Anexar documento abaixo.
        </p>
      )}
      {categoria === "resultado" ? (
        <div className="alert alert-warn">
          <p>
            Resultados: publique só o que o edital manda divulgar (pontuação por etapa, classificação e situação), sem CPF completo, e-mail, telefone ou
            dados de saúde (itens 13.2 e 13.3; LGPD).
          </p>
        </div>
      ) : null}
      <label className="check" style={{ marginTop: 4 }}>
        <input type="checkbox" checked={publicarAgora} onChange={(e) => setPublicarAgora(e.target.checked)} />
        Publicar agora na página inicial
      </label>
      {erro ? (
        <p className="err" role="alert">
          {erro}
        </p>
      ) : null}
      {ok ? <p className="hint">{ok}</p> : null}
      <div style={{ marginTop: 12, display: "flex", gap: 8, flexWrap: "wrap" }}>
        <button type="button" className="btn" disabled={enviando} onClick={() => inputArquivo.current?.click()}>
          {arquivo ? "Trocar documento" : "Anexar documento"}
        </button>
        <button type="button" className="btn btn-primary" disabled={enviando} onClick={() => void salvar()}>
          {enviando ? "Salvando…" : publicarAgora ? "Salvar e publicar" : "Salvar"}
        </button>
      </div>
    </div>
  );
}

function ItemPublicacao({ p, aoMudar }: { p: Publicacao; aoMudar: () => void }) {
  const [editando, setEditando] = useState(false);
  const [categoria, setCategoria] = useState<CategoriaPublicacao>(p.categoria);
  const [titulo, setTitulo] = useState(p.titulo);
  const [texto, setTexto] = useState(p.texto ?? "");
  const [erro, setErro] = useState("");
  const [ocupado, setOcupado] = useState(false);

  async function abrir() {
    if (!p.arquivo_path) return;
    const { data, error } = await createClient().storage.from("publicacoes").createSignedUrl(p.arquivo_path, 300);
    if (error) return setErro(error.message);
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  async function publicar(publicar: boolean) {
    const msg = publicar ? `Publicar na página inicial?\n\n"${p.titulo}"` : `Retirar do ar?\n\n"${p.titulo}"\n\nO registro continua no painel e na auditoria.`;
    if (!window.confirm(msg)) return;
    setOcupado(true);
    const { error } = await createClient().schema("painel").rpc("publicar_publicacao", { p_id: p.id, p_publicar: publicar });
    setOcupado(false);
    if (error) return setErro(error.message);
    aoMudar();
  }

  async function salvarEdicao() {
    setErro("");
    setOcupado(true);
    const { error } = await createClient().schema("painel").rpc("salvar_publicacao", {
      p_id: p.id,
      p_categoria: categoria,
      p_titulo: titulo.trim(),
      p_texto: texto.trim() || null,
      p_arquivo_path: null,
      p_arquivo_nome: null,
      p_arquivo_bytes: null,
    });
    setOcupado(false);
    if (error) return setErro(error.message);
    setEditando(false);
    aoMudar();
  }

  return (
    <li style={{ flexDirection: "column", alignItems: "stretch" }}>
      <div style={{ display: "flex", gap: 12, justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap" }}>
        <div className="doc-info">
          <span className="doc-cat">
            {CATEGORIAS[p.categoria]}
            {p.publicado ? <span className="pill pill-ok">Publicado</span> : <span className="pill pill-muted">Não publicado</span>}
          </span>
          <b>{p.titulo}</b>
          {p.texto && !editando ? <span className="doc-texto">{p.texto}</span> : null}
          <small className="hint">
            Criado em {fmtData(p.created_at)}
            {p.criado_por ? ` por ${p.criado_por}` : ""}
            {p.publicado_em ? ` · publicado em ${fmtData(p.publicado_em)}` : ""}
            {p.arquivo_nome ? ` · ${p.arquivo_nome}${p.arquivo_bytes ? ` (${tamanhoArquivo(p.arquivo_bytes)})` : ""}` : ""}
          </small>
        </div>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {p.arquivo_path ? (
            <button type="button" className="btn btn-sm" onClick={() => void abrir()}>
              Abrir PDF
            </button>
          ) : null}
          <button type="button" className="btn btn-sm btn-ghost" onClick={() => setEditando(!editando)}>
            {editando ? "Cancelar" : "Editar"}
          </button>
          {p.publicado ? (
            <button type="button" className="btn btn-sm" disabled={ocupado} onClick={() => void publicar(false)}>
              Retirar do ar
            </button>
          ) : (
            <button type="button" className="btn btn-sm btn-primary" disabled={ocupado} onClick={() => void publicar(true)}>
              Publicar
            </button>
          )}
        </div>
      </div>
      {editando ? (
        <div style={{ display: "grid", gap: 4, marginTop: 10 }}>
          <div style={{ display: "grid", gridTemplateColumns: "minmax(160px, 220px) 1fr", gap: 12 }}>
            <div className="field">
              <label htmlFor={`cat-${p.id}`}>Categoria</label>
              <select id={`cat-${p.id}`} value={categoria} onChange={(e) => setCategoria(e.target.value as CategoriaPublicacao)}>
                {(Object.keys(CATEGORIAS) as CategoriaPublicacao[]).map((c) => (
                  <option key={c} value={c}>
                    {CATEGORIAS[c]}
                  </option>
                ))}
              </select>
            </div>
            <div className="field">
              <label htmlFor={`tit-${p.id}`}>Título</label>
              <input id={`tit-${p.id}`} value={titulo} maxLength={200} onChange={(e) => setTitulo(e.target.value)} />
            </div>
          </div>
          <div className="field">
            <label htmlFor={`txt-${p.id}`}>Texto</label>
            <textarea id={`txt-${p.id}`} rows={3} maxLength={5000} value={texto} onChange={(e) => setTexto(e.target.value)} />
          </div>
          <p className="hint" style={{ margin: 0 }}>
            O PDF não pode ser trocado: para corrigir um arquivo, crie uma nova publicação e retire esta do ar.
          </p>
          <div>
            <button type="button" className="btn btn-sm btn-primary" disabled={ocupado} onClick={() => void salvarEdicao()}>
              Salvar alterações
            </button>
          </div>
        </div>
      ) : null}
      {erro ? <p className="err">{erro}</p> : null}
    </li>
  );
}
