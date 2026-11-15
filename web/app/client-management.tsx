"use client";

import Image from "next/image";
import { Check, Copy, ExternalLink, LoaderCircle, Plus, Smartphone, Trash2 } from "lucide-react";
import { useEffect, useState } from "react";

type Device = { id: string; name: string; createdAt: number; lastSeenAt: number };
type Activation = { activationID: string; activationCode: string; activationURL: string; activationQRCode: string; publicAPIURL: string; expiresAt: number };
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
  const [toast, setToast] = useState("");
  async function load() { try { setDevices(await api<Device[]>("/api/v1/client/devices")); setMessage(""); } catch (error) { setMessage(error instanceof Error ? error.message : "加载失败"); } finally { setLoading(false); } }
  useEffect(() => {
    let active = true;
    const refresh = () => { setNow(Date.now()); void api<Device[]>("/api/v1/client/devices").then((value) => { if (active) { setDevices(value); setMessage(""); setLoading(false); } }).catch((error) => { if (active) { setMessage(error instanceof Error ? error.message : "加载失败"); setLoading(false); } }); };
    refresh(); const timer = window.setInterval(refresh, 30_000);
    return () => { active = false; window.clearInterval(timer); };
  }, []);
  useEffect(() => {
    if (!toast) return;
    const timer = window.setTimeout(() => setToast(""), 2200);
    return () => window.clearTimeout(timer);
  }, [toast]);
  useEffect(() => {
    if (!activation) return;
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [activation]);
  useEffect(() => {
    if (!activation) return;
    let mounted = true;
    const check = () => void api<{ active: boolean }>(`/api/v1/client/activation-codes?id=${encodeURIComponent(activation.activationID)}`).then((value) => {
      if (mounted && !value.active) { setActivation(undefined); setToast("客户端已连接"); void load(); }
    }).catch(() => {});
    const timer = window.setInterval(check, 2000);
    return () => { mounted = false; window.clearInterval(timer); };
  }, [activation]);
  const activeCutoff = (now ?? 0) - 15 * 60_000;
  const activeDevices = now === undefined ? [] : devices.filter((device) => device.lastSeenAt >= activeCutoff);
  const inactiveDevices = now === undefined ? [] : devices.filter((device) => device.lastSeenAt < activeCutoff);
  const activationSeconds = activation && now !== undefined ? Math.max(0, Math.ceil((activation.expiresAt - now) / 1000)) : 0;

  async function copy(value: string, label: string) {
    try { await navigator.clipboard.writeText(value); setToast(`${label}已复制`); }
    catch { setToast("复制失败，请长按内容复制"); }
  }

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
      <div className="flex items-center justify-between"><div><h2 className="text-base font-semibold">连接客户端</h2><p className="mt-1 text-xs text-[#77736b]">在 iPhone 上扫码或打开连接链接</p></div><button onClick={() => void create()} disabled={busy !== ""} className="primary-button h-10 bg-[#6b7562] px-4">{busy === "create" ? <LoaderCircle className="animate-spin" size={17} /> : <><Plus className="mr-1.5 inline" size={16} />添加</>}</button></div>
      {activation && <div className="mt-4 rounded-2xl bg-white p-3"><div className="grid grid-cols-[132px_1fr] items-center gap-4"><Image src={activation.activationQRCode} alt="OpenHome 激活二维码" width={132} height={132} unoptimized className="rounded-xl" /><div className="min-w-0"><div className="flex items-center justify-between gap-2"><p className="text-[10px] text-[#918d84]">激活码</p><span className={`font-mono text-[11px] ${activationSeconds ? "text-[#59634f]" : "text-[#a65d48]"}`}>{activationSeconds ? `${String(Math.floor(activationSeconds / 60)).padStart(2, "0")}:${String(activationSeconds % 60).padStart(2, "0")}` : "已过期"}</span></div><strong className="mt-1 block font-mono text-xl tracking-[.12em]">{activation.activationCode}</strong><button onClick={() => void copy(activation.activationCode, "激活码")} disabled={!activationSeconds} className="mt-3 flex min-h-8 items-center gap-1.5 text-xs font-medium text-[#59634f] disabled:opacity-40"><Copy size={14} />复制激活码</button></div></div><div className="mt-3 flex items-center gap-3 rounded-xl bg-[#f5f4ef] px-3 py-2.5"><div className="min-w-0 flex-1"><p className="text-[10px] text-[#918d84]">OpenHome 地址</p><p className="mt-0.5 truncate font-mono text-xs text-[#4f4c46]">{activation.publicAPIURL}</p></div><button onClick={() => void copy(activation.publicAPIURL, "OpenHome 地址")} className="icon-button shrink-0 text-[#59634f]" aria-label="复制 OpenHome 地址"><Copy size={15} /></button></div><div className="mt-3 grid grid-cols-2 gap-2"><button onClick={() => void copy(activation.activationURL, "连接链接")} disabled={!activationSeconds} className="secondary-button h-10 text-xs disabled:opacity-40"><Copy className="mr-1.5 inline" size={14} />复制连接链接</button><a href={activationSeconds ? activation.activationURL : undefined} aria-disabled={!activationSeconds} className={`primary-button grid h-10 place-items-center bg-[#6b7562] text-xs ${activationSeconds ? "" : "pointer-events-none opacity-40"}`}><span><ExternalLink className="mr-1.5 inline" size={14} />在 iPhone 上打开</span></a></div></div>}
    </section>
    <section className="surface-card p-5">
      <div className="flex items-center justify-between"><h2 className="text-base font-semibold">已连接客户端</h2><span className="rounded-full bg-[#e7eee5] px-2 py-1 text-[10px] font-semibold text-[#59634f]">活跃 {activeDevices.length}</span></div>
      <div className="mt-3 divide-y divide-[#e8e4dc]">{loading || now === undefined ? <div className="grid h-20 place-items-center"><LoaderCircle className="animate-spin text-[#6b7562]" size={18} /></div> : activeDevices.length ? activeDevices.map((device) => <DeviceRow key={device.id} device={device} active onRevoke={setRevokeTarget} />) : <p className="py-7 text-center text-sm text-[#918d84]">当前没有活跃客户端</p>}</div>
      {inactiveDevices.length > 0 && <details className="mt-3 border-t border-[#e8e4dc] pt-3"><summary className="cursor-pointer text-xs font-medium text-[#77736b]">其他已授权客户端 {inactiveDevices.length}</summary><div className="mt-2 divide-y divide-[#e8e4dc]">{inactiveDevices.map((device) => <DeviceRow key={device.id} device={device} active={false} onRevoke={setRevokeTarget} />)}</div></details>}
    </section>
    {message && <p role="status" className="rounded-xl bg-[#f4e7e2] px-3 py-2 text-xs text-[#8b4c3b]">{message}</p>}
    {toast && <div role="status" className="app-toast border-[#cdd2bf] text-[#536044]"><Check className="mr-1.5 inline" size={14} />{toast}</div>}
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
