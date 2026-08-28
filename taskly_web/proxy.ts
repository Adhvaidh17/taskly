import { NextRequest, NextResponse } from 'next/server';

const MOBILE_UA = /Android|webOS|iPhone|iPod|BlackBerry|IEMobile|Opera Mini|Mobile/i;

export function proxy(request: NextRequest) {
  const pathname = request.nextUrl.pathname;
  if (pathname.startsWith('/mobile') || pathname.startsWith('/_next') || pathname.includes('.')) {
    return NextResponse.next();
  }
  const ua = request.headers.get('user-agent') ?? '';
  if (MOBILE_UA.test(ua)) {
    const url = request.nextUrl.clone();
    url.pathname = '/mobile';
    return NextResponse.redirect(url);
  }
  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!api).*)'],
};
