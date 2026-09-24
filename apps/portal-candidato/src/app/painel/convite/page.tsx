import { ConviteForm } from "./ConviteForm";

export const metadata = { title: "Convite · Painel da Comissão", robots: { index: false, follow: false } };

export default async function ConvitePage({ searchParams }: { searchParams: Promise<{ t?: string }> }) {
  const { t } = await searchParams;
  return (
    <main className="wrap" style={{ padding: "48px 16px" }}>
      <ConviteForm token={t ?? ""} />
    </main>
  );
}
