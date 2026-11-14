"use client";

import Image from "next/image";
import { Copy, LoaderCircle, Plus, Smartphone, Trash2 } from "lucide-react";
import { useEffect, useState } from "react";

type Device = { id: string; name: string; createdAt: number; lastSeenAt: number };
type Activation = { activationCode: string; activationURL: string; activationQRCode: string; expiresAt: number };
type Result<T> = { ok: boolean; data?: T; message?: string };

async function api<T>(path: string, init?: RequestInit) {
  const response = await fetch(path, { cache: "no-store", ...init, headers: { "content-type": "application/json", ...init?.headers } });
  const payload = await response.json() as Result<T>;
  if (!response.ok || !payload.ok || payload.data === undefined) throw new Error(payload.message || "请求失败");
  return payload.data;
}

export function ClientManagement() {
  const [devices, setDevices] = useState<Device[]>([]);
  const [activation, setActivation] = useState<Activation>();
  const [busy, setBusy] = useState("");
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(true);
  const [now, setNow] = useState<number>();
  const [revokeTarget, setRevokeTarget] = useState<Device>();
  async function load() { try { setDevices(await api<Device[]>("/api/v1/client/devices")); setMessage(""); } catch (error) { setMessage(error instanceof Error ? error.message : "加载失败"); } finally { setLoading(false); } }
  useEffect(() => {
    let active = true;
    const refresh = () => { setNow(Date.now()); void api<Device[]>("/api/v1/client/devices").then((value) => { if (active) { setDevices(value); setMessage(""); setLoading(false); } }).catch((error) => { if (active) { setMessage(error instanceof Error ? error.message : "加载失败"); setLoading(false); } }); };
    refresh(); const timer = window.setInterval(refresh, 30_000);
    return () => { active = false; window.clearInterval(timer); };
  }, []);
  const activeCutoff = (now ?? 0) - 15 * 60_000;
  const activeDevices = now === undefined ? [] : devices.filter((device) => device.lastSeenAt >= activeCutoff);
  const inactiveDevices = now === undefined ? [] : devices.filter((device) => device.lastSeenAt < activeCutoff);

  async function create() {
    setBusy("create"); setMessage("");
    try { setActivation(await api<Activation>("/api/v1/client/activation-codes", { method: "POST", body: "{}" })); }
    catch (error) { setMessage(error instanceof Error ? error.message : "生成失败"); }
    finally { setBusy(""); }
  }
  async function revoke() {
    if (!revokeTarget) return;
    setBusy(revokeTarget.id); setMessage("");
    try { await api(`/api/v1/client/devices`, { method: "DELETE", body: JSON.stringify({ deviceId: revokeTarget.id }) }); setRevokeTarget(undefined); await load(); }
    catch (error) { setMessage(error instanceof Error ? error.message : "撤销失败"); }
    finally { setBusy(""); }
  }

  return <main className="mx-auto w-full max-w-[520px] space-y-3 px-4 py-5">
    <section className="surface-card p-5">
      <div className="flex items-center justify-between"><div><h2 className="text-base font-semibold">连接客户端</h2><p className="mt-1 text-xs text-[#77736b]">二维码和激活码 10 分钟内有效</p></div><button onClick={() => void create()} disabled={busy !== ""} className="primary-button h-10 bg-[#6b7562] px-4">{busy === "create" ? <LoaderCircle className="animate-spin" size={17} /> : <><Plus className="mr-1.5 inline" size={16} />添加</>}</button></div>
      {activation && <div className="mt-4 grid grid-cols-[148px_1fr] items-center gap-4 rounded-2xl bg-white p-3"><Image src={activation.activationQRCode} alt="OpenHome 激活二维码" width={148} height={148} unoptimized className="rounded-xl" /><div className="min-w-0"><p className="text-[10px] text-[#918d84]">激活码</p><strong className="mt-1 block font-mono text-xl tracking-[.12em]">{activation.activationCode}</strong><button onClick={() => void navigator.clipboard.writeText(activation.activationCode)} className="mt-3 flex items-center gap-1.5 text-xs font-medium text-[#59634f]"><Copy size={14} />复制激活码</button></div></div>}
    </section>
    <section className="surface-card p-5">
      <div className="flex items-center justify-between"><h2 className="text-base font-semibold">已连接客户端</h2><span className="rounded-full bg-[#e7eee5] px-2 py-1 text-[10px] font-semibold text-[#59634f]">活跃 {activeDevices.length}</span></div>
      <div className="mt-3 divide-y divide-[#e8e4dc]">{loading || now === undefined ? <div className="grid h-20 place-items-center"><LoaderCircle className="animate-spin text-[#6b7562]" size={18} /></div> : activeDevices.length ? activeDevices.map((device) => <DeviceRow key={device.id} device={device} active onRevoke={setRevokeTarget} />) : <p className="py-7 text-center text-sm text-[#918d84]">当前没有活跃客户端</p>}</div>
      {inactiveDevices.length > 0 && <details className="mt-3 border-t border-[#e8e4dc] pt-3"><summary className="cursor-pointer text-xs font-medium text-[#77736b]">其他已授权客户端 {inactiveDevices.length}</summary><div className="mt-2 divide-y divide-[#e8e4dc]">{inactiveDevices.map((device) => <DeviceRow key={device.id} device={device} active={false} onRevoke={setRevokeTarget} />)}</div></details>}
    </section>
    {message && <p role="status" className="rounded-xl bg-[#f4e7e2] px-3 py-2 text-xs text-[#8b4c3b]">{message}</p>}
    {revokeTarget && <div className="dialog-backdrop"><section role="dialog" aria-modal="true" className="dialog-card"><h2 className="font-display text-[22px]">撤销客户端？</h2><p className="mt-2 truncate text-sm text-[#77736b]">{revokeTarget.name}</p><div className="mt-6 grid grid-cols-2 gap-2"><button onClick={() => setRevokeTarget(undefined)} className="secondary-button">取消</button><button onClick={() => void revoke()} disabled={busy !== ""} className="primary-button bg-[#9b5e52]">{busy === revokeTarget.id ? <LoaderCircle className="mx-auto animate-spin" size={17} /> : "确认撤销"}</button></div></section></div>}
  </main>;
}

function DeviceRow({ device, active, onRevoke }: { device: Device; active: boolean; onRevoke: (device: Device) => void }) {
  return <div className="flex items-center gap-3 py-3"><span className={`relative grid h-10 w-10 place-items-center rounded-xl ${active ? "bg-[#e7eee5] text-[#59634f]" : "bg-[#ece8e0] text-[#8d887f]"}`}><Smartphone size={18} />{active && <span className="absolute right-1 top-1 h-2 w-2 rounded-full bg-[#65a46d] ring-2 ring-[#e7eee5]" />}</span><div className="min-w-0 flex-1"><strong className="block truncate text-sm">{device.name}</strong><span className="text-[10px] text-[#918d84]">最后活跃 {formatActivity(device.lastSeenAt)}</span></div><button onClick={() => onRevoke(device)} aria-label={`撤销 ${device.name}`} className="icon-button text-[#a65d48]"><Trash2 size={16} /></button></div>;
}

function formatActivity(value: number) {
  const seconds = Math.max(0, Math.floor((Date.now() - value) / 1000));
  if (seconds < 60) return "刚刚";
  if (seconds < 3600) return `${Math.floor(seconds / 60)} 分钟前`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} 小时前`;
  return new Date(value).toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" });
}
