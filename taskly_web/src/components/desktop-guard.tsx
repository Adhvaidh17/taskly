'use client';

import { useEffect } from 'react';
import { usePathname, useRouter } from 'next/navigation';

export function DesktopGuard({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  useEffect(() => {
    if (pathname === '/mobile') return;
    const min = Number(process.env.NEXT_PUBLIC_TASKLY_DESKTOP_MIN_WIDTH || 900);
    const check = () => { if (window.innerWidth < min) router.replace('/mobile'); };
    check();
    window.addEventListener('resize', check);
    return () => window.removeEventListener('resize', check);
  }, [pathname, router]);
  return <>{children}</>;
}
