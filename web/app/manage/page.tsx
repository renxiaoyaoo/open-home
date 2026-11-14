import { ArrowLeft } from "lucide-react";
import Link from "next/link";
import { ClientManagement } from "../client-management";

export default function ManagePage() {
  return <div className="min-h-screen bg-[#f5f4ef] text-[#292a27]">
    <header className="sticky top-0 z-20 border-b border-[#dedbd3]/90 bg-[#f5f4ef]/95 px-4 py-3 backdrop-blur"><div className="mx-auto flex w-full max-w-[520px] items-center gap-3"><Link href="/" aria-label="返回" className="icon-button bg-[#ece8e0]"><ArrowLeft size={17} /></Link><div><strong className="block text-base font-semibold">管理</strong><span className="block text-[10px] text-[#918d84]">OpenHome 客户端</span></div></div></header>
    <ClientManagement />
  </div>;
}
