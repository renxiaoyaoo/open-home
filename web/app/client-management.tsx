"use client";

import Image from "next/image";
import { Copy, LoaderCircle, Plus, Smartphone, Trash2 } from "lucide-react";
import { useEffect, useState } from "react";

type Device = { id: string; name: string; createdAt: number; lastSeenAt: number };
type Activation = { activationCode: string; activationURL: string; activationQRCode: string; expiresAt: number };
type Result<T> = { ok: boolean; data?: T; message?: string };

async function api<T>(path: string, init?: RequestInit) {
  const response = await fetch(path, { ...init, headers: { "content-type": "application/json", ...init?.headers } });
  const payload = await response.json() as Result<T>;
  if (!response.ok || !payload.ok || payload.data === undefined) throw new Error(payload.message || "请求失败");
  return payload.data;
}

export function ClientManagement() {
  const [devices, setDevices] = useState<Device[]>([]);
  const [activation, setActivation] = useState<Activation>();
  const [busy, setBusy] = useState("");
  const [message, setMessage] = useState("");
  const [revokeTarget, setRevokeTarget] = useState<Device>();
  async function load() { try { setDevices(await api<Device[]>("/api/v1/client/devices")); setMessage(""); } catch (error) { setMessage(error instanceof Error ? error.message : "加载失败"); } }
  useEffect(() => {
    let active = true;
    void api<Device[]>("/api/v1/client/devices").then((value) => { if (active) setDevices(value); }).catch((error) => { if (active) setMessage(error instanceof Error ? error.message : "加载失败"); });
    return () => { active = false; };
  }, []);

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
      <h2 className="text-base font-semibold">已连接客户端</h2>
      <div className="mt-3 divide-y divide-[#e8e4dc]">{devices.length ? devices.map((device) => <div key={device.id} className="flex items-center gap-3 py-3"><span className="grid h-10 w-10 place-items-center rounded-xl bg-[#ece8e0] text-[#6b7562]"><Smartphone size={18} /></span><div className="min-w-0 flex-1"><strong className="block truncate text-sm">{device.name}</strong><span className="text-[10px] text-[#918d84]">最近连接 {new Date(device.lastSeenAt).toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" })}</span></div><button onClick={() => setRevokeTarget(device)} aria-label={`撤销 ${device.name}`} className="icon-button text-[#a65d48]"><Trash2 size={16} /></button></div>) : <p className="py-8 text-center text-sm text-[#918d84]">暂无客户端</p>}</div>
    </section>
    {message && <p role="status" className="rounded-xl bg-[#f4e7e2] px-3 py-2 text-xs text-[#8b4c3b]">{message}</p>}
    {revokeTarget && <div className="dialog-backdrop"><section role="dialog" aria-modal="true" className="dialog-card"><h2 className="font-display text-[22px]">撤销客户端？</h2><p className="mt-2 truncate text-sm text-[#77736b]">{revokeTarget.name}</p><div className="mt-6 grid grid-cols-2 gap-2"><button onClick={() => setRevokeTarget(undefined)} className="secondary-button">取消</button><button onClick={() => void revoke()} disabled={busy !== ""} className="primary-button bg-[#9b5e52]">{busy === revokeTarget.id ? <LoaderCircle className="mx-auto animate-spin" size={17} /> : "确认撤销"}</button></div></section></div>}
  </main>;
}
