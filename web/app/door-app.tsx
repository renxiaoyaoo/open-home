"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Check, Copy, KeyRound, List, LoaderCircle, LockKeyholeOpen, LogOut, Plus, RefreshCw, Smartphone, X } from "lucide-react";
import { useFeatureActivation } from "./use-feature-activation";

type Door = { id: string; name: string; communityName?: string | null; passwordSupported?: boolean; providerFeatured: boolean; selected: boolean; refreshedAt: number };
type Account = { id: string; username: string };
type DoorPassword = { value: string; validUntil: number };
type Toast = { text: string; kind: "success" | "error" | "info" };
type ApiResult<T = unknown> = { ok: boolean; message?: string; data?: T; meta?: { failedAccountCount?: number; expiredAccountCount?: number } };

async function request<T>(url: string, init?: RequestInit): Promise<ApiResult<T>> {
  const response = await fetch(url, { ...init, headers: { "content-type": "application/json", ...init?.headers } });
  const payload = (await response.json().catch(() => ({}))) as ApiResult<T>;
  if (!response.ok || !payload.ok) throw Object.assign(new Error(payload.message || "请求失败"), { status: response.status });
  return payload;
}

export function DoorApp({ activeByDefault = true }: { activeByDefault?: boolean }) {
  const active = useFeatureActivation("gate", activeByDefault);
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [loggedIn, setLoggedIn] = useState(false);
  const [initialized, setInitialized] = useState(false);
  const [showLogin, setShowLogin] = useState(true);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [doors, setDoors] = useState<Door[]>([]);
  const [manageDoors, setManageDoors] = useState(false);
  const [busy, setBusy] = useState<"sms" | "login" | "doors" | string | null>(null);
  const [countdown, setCountdown] = useState(0);
  const [now, setNow] = useState(() => Date.now());
  const [passwords, setPasswords] = useState<Record<string, DoorPassword>>({});
  const [toast, setToast] = useState<Toast | null>(null);
  const [logoutTarget, setLogoutTarget] = useState<Account | null>(null);
  const openingRef = useRef(false);
  const savingDoorIdsRef = useRef(new Set<string>());
  const selectionQueueRef = useRef<Promise<void>>(Promise.resolve());
  const [savingDoorIds, setSavingDoorIds] = useState<Set<string>>(() => new Set());
  const accountIdRef = useRef(crypto.randomUUID());

  useEffect(() => {
    if (countdown <= 0) return;
    const timer = window.setInterval(() => setCountdown((value) => Math.max(0, value - 1)), 1000);
    return () => window.clearInterval(timer);
  }, [countdown]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    if (!toast) return;
    const timer = window.setTimeout(() => setToast(null), 2600);
    return () => window.clearTimeout(timer);
  }, [toast]);

  const notify = useCallback((text: string, kind: Toast["kind"] = "info") => { setToast({ text, kind }); }, []);
  const loadDoors = useCallback(async () => {
    setBusy("doors");
    try {
      const result = await request<Door[]>("/api/v1/doors");
      setDoors(result.data || []); setLoggedIn(true);
      if (result.meta?.expiredAccountCount) notify(`${result.meta.expiredAccountCount} 个账号需要重新登录`, "error");
      else if (result.meta?.failedAccountCount) notify(`${result.meta.failedAccountCount} 个账号刷新失败`, "error");
      else if (!result.data?.length) notify("没有可用门禁");
      else if (result.message) notify(result.message);
    } catch (error) {
      if (error instanceof Error && "status" in error && error.status === 401) notify("账号需要重新登录", "error");
      else notify(error instanceof Error ? error.message : "门禁加载失败", "error");
    } finally { setBusy(null); }
  }, [notify]);

  async function loadAccounts() {
    const result = await request<Account[]>("/api/v1/accounts");
    const next = result.data || [];
    setAccounts(next); setLoggedIn(next.length > 0);
    return next;
  }

  useEffect(() => {
    if (!active || initialized) return;
    request<Account[]>("/api/v1/accounts")
      .then((result) => {
        const next = result.data || [];
        setAccounts(next); setLoggedIn(next.length > 0); setShowLogin(next.length === 0);
        return next.length > 0 ? loadDoors() : undefined;
      })
      .catch((error) => { setShowLogin(true); notify(error instanceof Error ? error.message : "加载失败", "error"); })
      .finally(() => setInitialized(true));
  }, [active, initialized, loadDoors, notify]);

  async function sendSms() {
    if (!/^1\d{10}$/.test(phone)) { notify("请输入正确的手机号", "error"); return; }
    setBusy("sms");
    try {
      const result = await request(`/api/v1/accounts/${accountIdRef.current}/sms`, { method: "POST", body: JSON.stringify({ mobile: phone }) });
      setCountdown(60); notify(result.message || "验证码已发送", "success");
    } catch (error) { notify(error instanceof Error ? error.message : "验证码发送失败", "error"); }
    finally { setBusy(null); }
  }

  async function login(smsCode = code) {
    if (!/^1\d{10}$/.test(phone) || !/^\d{6}$/.test(smsCode) || busy !== null) return;
    setBusy("login");
    try {
      await request(`/api/v1/accounts/${accountIdRef.current}/login`, { method: "POST", body: JSON.stringify({ mobile: phone, smsCode }) });
      accountIdRef.current = crypto.randomUUID(); setPhone(""); setCode(""); setCountdown(0); setShowLogin(false); setLoggedIn(true);
      await loadAccounts(); await loadDoors(); notify("登录成功", "success");
    } catch (error) { notify(error instanceof Error ? error.message : "登录失败", "error"); setBusy(null); }
  }

  async function logoutAccount(account: Account) {
    setBusy(`logout:${account.id}`);
    try {
      const result = await request(`/api/v1/accounts/${account.id}`, { method: "DELETE" });
      const remaining = await loadAccounts();
      setLogoutTarget(null); notify(result.message || "已退出", "success");
      if (!remaining.length) {
        setDoors([]); setPasswords({}); setShowLogin(true); setPhone(""); setCode(""); setCountdown(0); accountIdRef.current = crypto.randomUUID();
      } else await loadDoors();
    } catch (error) { notify(error instanceof Error ? error.message : "退出失败", "error"); }
    finally { setBusy(null); }
  }

  async function openDoor(door: Door) {
    if (openingRef.current) return;
    openingRef.current = true; setBusy(door.id);
    try {
      const result = await request(`/api/v1/doors/${door.id}/open`, { method: "POST", headers: { "Idempotency-Key": crypto.randomUUID() } });
      notify(result.message || `${door.name} 已开门`, "success");
    } catch (error) {
      if (error instanceof Error && "status" in error && error.status === 401) notify("账号需要重新登录", "error");
      else notify(error instanceof Error ? error.message : "开门失败", "error");
    } finally { openingRef.current = false; setBusy(null); }
  }

  function toggleDoor(door: Door) {
    if (savingDoorIdsRef.current.has(door.id)) return;
    const selected = !door.selected;
    savingDoorIdsRef.current.add(door.id);
    setSavingDoorIds((items) => new Set(items).add(door.id));
    setDoors((items) => items.map((item) => item.id === door.id ? { ...item, selected } : item));

    const save = async () => {
      try {
        await request(`/api/v1/doors/${door.id}`, { method: "PATCH", body: JSON.stringify({ selected }) });
      } catch (error) {
        setDoors((items) => items.map((item) => item.id === door.id ? { ...item, selected: !selected } : item));
        if (error instanceof Error && "status" in error && error.status === 401) notify("账号需要重新登录", "error");
        else notify(error instanceof Error ? error.message : "保存失败", "error");
      } finally {
        savingDoorIdsRef.current.delete(door.id);
        setSavingDoorIds((items) => {
          const next = new Set(items);
          next.delete(door.id);
          return next;
        });
      }
    };

    selectionQueueRef.current = selectionQueueRef.current.then(save, save);
  }

  async function showPassword(door: Door) {
    setBusy(`password:${door.id}`);
    try {
      const result = await request<{ password: string; validUntil: string }>(`/api/v1/doors/${door.id}/password`);
      if (!result.data?.password) throw new Error("获取密码失败");
      const next = { value: result.data.password, validUntil: Date.parse(result.data.validUntil) };
      setPasswords((value) => ({ ...value, [door.id]: next }));
      await navigator.clipboard?.writeText(next.value);
      notify("密码已复制", "success");
    } catch (error) { notify(error instanceof Error ? error.message : "获取密码失败", "error"); }
    finally { setBusy(null); }
  }

  function passwordLabel(doorId: string) {
    const item = passwords[doorId];
    if (!item) return "显示密码";
    const remaining = Math.max(0, Math.ceil((item.validUntil - now) / 1000));
    const minutes = Math.floor(remaining / 60).toString().padStart(2, "0");
    const seconds = (remaining % 60).toString().padStart(2, "0");
    return `${item.value}  ${minutes}:${seconds}`;
  }

  const visibleDoors = manageDoors ? doors : doors.filter((door) => door.selected);
  const selectedDoorCount = doors.filter((door) => door.selected).length;

  return (
    <main className="min-h-screen bg-[#f7f6f2] px-4 py-6 text-[#2d2d2a] sm:py-10">
      {toast && <div role="status" className={`app-toast ${toast.kind === "error" ? "border-[#e7b8aa] text-[#9b4d38]" : "border-[#dfc5b9] text-[#7d4938]"}`}>{toast.text}</div>}

      <section className="mx-auto w-full max-w-[520px]">
        {!initialized ? <div className="grid h-64 place-items-center"><LoaderCircle className="animate-spin text-[#526277]" size={26} /></div> : !loggedIn || showLogin ? (
          <form onSubmit={(event) => event.preventDefault()} className="rounded-[18px] border border-[#dedbd3] bg-[#fbfaf7] p-6 sm:p-8">
            <div className="mb-8"><div className="mb-5 grid h-10 w-10 place-items-center rounded-[10px] bg-[#f0ebe5] text-[#9a5a45]"><Smartphone size={19} /></div><h2 className="font-display text-[30px] font-medium tracking-[-.035em] text-[#2d2d2a]">{loggedIn ? "添加账号" : "登录"}</h2><p className="mt-2 text-sm text-[#77736b]">{loggedIn ? "连接另一个门禁账号" : "使用短信验证码登录"}</p></div>
            <div className="space-y-3">
              <input aria-label="手机号" autoComplete="tel" inputMode="numeric" maxLength={11} value={phone} onChange={(event) => setPhone(event.target.value.replace(/\D/g, ""))} placeholder="手机号" className="h-14 w-full rounded-[10px] border border-[#d8d4cb] bg-white px-4 text-base outline-none transition placeholder:text-[#aaa69d] focus:border-[#b97860] focus:ring-2 focus:ring-[#d97757]/10" />
              <div className="flex gap-2.5"><input aria-label="验证码" autoComplete="one-time-code" inputMode="numeric" maxLength={6} value={code} onChange={(event) => { const next = event.target.value.replace(/\D/g, ""); setCode(next); if (next.length === 6) void login(next); }} placeholder="6位验证码" className="h-14 min-w-0 flex-1 rounded-[10px] border border-[#d8d4cb] bg-white px-4 text-base outline-none transition placeholder:text-[#aaa69d] focus:border-[#b97860] focus:ring-2 focus:ring-[#d97757]/10" /><button type="button" disabled={busy !== null || countdown > 0} onClick={sendSms} className="min-w-[112px] rounded-[10px] bg-[#d97757] px-3 text-sm font-semibold text-white transition hover:bg-[#ca6c4d] active:scale-[.98] disabled:opacity-40">{busy === "sms" ? <LoaderCircle className="mx-auto animate-spin" size={18} /> : countdown > 0 ? `${countdown}s` : "获取验证码"}</button></div>
              {busy === "login" && <div role="status" className="flex h-8 items-center justify-center gap-2 text-sm text-[#9a5a45]"><LoaderCircle className="animate-spin" size={18} />正在登录</div>}
              {loggedIn && <button type="button" onClick={() => { setShowLogin(false); setPhone(""); setCode(""); setCountdown(0); }} className="h-11 w-full text-sm font-medium text-[#77736b]">取消</button>}
            </div>
          </form>
        ) : (
          <div className="space-y-4">
            <section className="flex items-center gap-2 overflow-x-auto rounded-[14px] border border-[#dedbd3] bg-[#fbfaf7] p-2.5">
              {accounts.map((account) => <div key={account.id} className="flex shrink-0 items-center gap-2 rounded-[10px] bg-[#eeeae3] py-2 pl-3 pr-1.5"><span className="max-w-36 truncate text-sm font-medium">{account.username}</span><button onClick={() => setLogoutTarget(account)} disabled={busy !== null} aria-label={`退出 ${account.username}`} className="grid h-7 w-7 place-items-center rounded-[8px] text-[#a65d48] disabled:opacity-40"><LogOut size={14} /></button></div>)}
              <button onClick={() => setShowLogin(true)} aria-label="添加账号" className="grid h-10 w-10 shrink-0 place-items-center rounded-[10px] bg-[#d97757] text-white"><Plus size={18} /></button>
              <button onClick={loadDoors} disabled={busy !== null} aria-label="刷新门禁" className="ml-auto grid h-10 w-10 shrink-0 place-items-center rounded-[10px] text-[#65625b] disabled:opacity-40"><RefreshCw size={17} className={busy === "doors" ? "animate-spin" : ""} /></button>
            </section>

            <div><div className="mb-3 flex items-center justify-between px-1"><h2 className="text-[15px] font-semibold tracking-[-.01em]">{manageDoors ? "选择常用门禁" : "常用门禁"}</h2><button onClick={() => setManageDoors((value) => !value)} aria-label={manageDoors ? "完成选择" : `选择常用门禁，已选 ${selectedDoorCount}/${doors.length}`} className="flex h-9 items-center gap-1.5 rounded-[9px] border border-[#dedbd3] bg-[#fbfaf7] px-3.5 text-sm font-medium text-[#65625b]">{manageDoors ? "完成" : <><List size={15} /><span className="tabular-nums text-[#9a968d]">{selectedDoorCount}/{doors.length}</span></>}</button></div>
              {busy === "doors" && !doors.length ? <div className="grid h-48 place-items-center rounded-[18px] border border-[#dedbd3] bg-[#fbfaf7]"><LoaderCircle className="animate-spin text-[#d97757]" /></div> : !visibleDoors.length && !manageDoors ? <button onClick={() => setManageDoors(true)} className="h-32 w-full rounded-[16px] border border-[#dedbd3] bg-[#fbfaf7] text-sm font-medium text-[#65625b]">选择首页门禁</button> : <div className="grid grid-cols-2 items-start gap-3">{visibleDoors.map((door) => (
                <article key={door.id} className={`relative flex self-start overflow-hidden rounded-[18px] border border-[#d9d3ca] shadow-[0_8px_24px_rgba(71,55,45,.045)] ${door.passwordSupported && !manageDoors ? "col-span-2 min-h-[104px]" : "min-h-[112px]"} ${door.selected ? "bg-[#f0e6df]" : "bg-[#efede8]"}`}>
                  <button onClick={() => manageDoors ? toggleDoor(door) : openDoor(door)} disabled={manageDoors ? savingDoorIds.has(door.id) : busy !== null} aria-busy={savingDoorIds.has(door.id)} className={`flex min-w-0 flex-1 gap-3 px-4 py-4 text-left transition active:scale-[.99] ${door.passwordSupported && !manageDoors ? "items-center" : "flex-col items-start justify-between"} ${manageDoors ? "" : "disabled:opacity-55"} ${door.selected ? "text-[#342d29]" : "text-[#67635d]"}`}>
                    <span className={`relative grid h-11 w-11 shrink-0 place-items-center rounded-[13px] ${door.selected ? "bg-[#9a654f] text-white" : "bg-[#fbfaf7] text-[#77736b]"}`}>{busy === door.id ? <LoaderCircle className="animate-spin" size={22} /> : manageDoors && door.selected ? <Check size={24} strokeWidth={2.3} /> : <LockKeyholeOpen size={22} strokeWidth={2.1} />}{savingDoorIds.has(door.id) && <LoaderCircle aria-hidden="true" className="absolute -right-1.5 -top-1.5 animate-spin rounded-full bg-[#fbfaf7] p-1 text-[#9a5a45]" size={20} />}</span>
                    <span className={`block min-w-0 max-w-full ${door.passwordSupported && !manageDoors ? "flex-1" : ""}`}>
                      <strong className={`block truncate font-semibold leading-tight tracking-[-.015em] ${door.passwordSupported && !manageDoors ? "text-[21px]" : "text-[17px]"}`}>{door.name}</strong>
                      {door.communityName && <span className="mt-1.5 block truncate text-[13px] font-medium leading-tight text-[#77736b]">{door.communityName}</span>}
                    </span>
                  </button>
                  {!manageDoors && door.passwordSupported && <button aria-label={`${door.name}开门密码`} onClick={() => showPassword(door)} disabled={busy !== null} className="m-2.5 flex w-[132px] shrink-0 flex-col items-center justify-center rounded-[14px] border border-[#d9d3ca] bg-[#fbfaf7] px-2 text-[#9a5a45] tabular-nums disabled:opacity-40">{busy === `password:${door.id}` ? <LoaderCircle className="animate-spin" size={18} /> : passwords[door.id] ? <><span className="flex items-center gap-1.5"><Copy size={14} /><strong className="font-mono text-[21px] tracking-[.12em]">{passwords[door.id].value}</strong></span><span className="mt-1.5 font-mono text-[11px] text-[#77736b]">剩余 {passwordLabel(door.id).split(/\s+/).at(-1)}</span></> : <><KeyRound size={18} /><span className="mt-1.5 text-xs font-semibold">查看密码</span></>}</button>}
                </article>
              ))}</div>}
            </div>
          </div>
        )}
      </section>

      {logoutTarget && <div className="fixed inset-0 z-40 grid place-items-center bg-[#2d2d2a]/35 p-5 backdrop-blur-sm" onMouseDown={(event) => { if (event.currentTarget === event.target) setLogoutTarget(null); }}><section role="dialog" aria-modal="true" aria-labelledby="logout-title" className="w-full max-w-[340px] rounded-[18px] border border-[#dedbd3] bg-[#fbfaf7] p-5 shadow-[0_24px_70px_rgba(45,45,42,.16)]"><div className="flex items-start justify-between"><h2 id="logout-title" className="font-display mt-1 text-[22px] font-medium tracking-[-.03em]">退出账号？</h2><button onClick={() => setLogoutTarget(null)} aria-label="取消退出" className="grid h-9 w-9 place-items-center rounded-[9px] bg-[#eeeae3] text-[#77736b]"><X size={18} /></button></div><p className="mt-3 truncate text-sm text-[#77736b]">{logoutTarget.username}</p><div className="mt-6 grid grid-cols-2 gap-2.5"><button onClick={() => setLogoutTarget(null)} className="h-12 rounded-[10px] bg-[#eeeae3] text-sm font-medium text-[#56534d]">取消</button><button onClick={() => logoutAccount(logoutTarget)} disabled={busy !== null} className="h-12 rounded-[10px] bg-[#d97757] text-sm font-semibold text-white disabled:opacity-50">{busy === `logout:${logoutTarget.id}` ? <LoaderCircle className="mx-auto animate-spin" size={18} /> : "确认退出"}</button></div></section></div>}
    </main>
  );
}
