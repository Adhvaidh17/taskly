import type { Metadata } from 'next';
import './globals.css';
import '@/styles/generated-theme.css';

export const metadata: Metadata = {
  title: 'Taskly Web',
  description: 'Taskly desktop web app for chats, tasks, groups and team work.',
  metadataBase: new URL(process.env.NEXT_PUBLIC_TASKLY_DOMAIN || 'https://taskly.madrascreatives.com'),
  icons: { icon: '/taskly-logo.svg' },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en" suppressHydrationWarning><body>{children}</body></html>;
}
