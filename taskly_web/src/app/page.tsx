import { DesktopGuard } from '@/components/desktop-guard';
import { TasklyRoot } from '@/components/taskly-root';

export default function Home() {
  return <DesktopGuard><TasklyRoot /></DesktopGuard>;
}
