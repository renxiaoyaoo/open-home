import { AppShell } from "./app-shell";

export default async function Home({ searchParams }: { searchParams: Promise<{ feature?: string }> }) {
  const { feature } = await searchParams;
  return <AppShell feature={feature === "dryer" || feature === "lock" || feature === "auto" ? feature : "gate"} />;
}
